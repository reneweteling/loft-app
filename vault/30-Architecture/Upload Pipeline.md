---
title: Upload Pipeline
tags: [architecture, upload, multipart, s3, concurrency]
project: Loft
created: 2026-04-23
---

# Upload Pipeline

This page describes the complete path a file takes from the moment it is dropped onto a pane until the shareable URL lands in the user's clipboard.

## End-to-end flow

```
1. User drops file(s) onto DropPaneView
        │
        ▼
2. DropPaneView.performDrop(_ info:)
   - resolve NSItemProvider → local file URL
   - detect folder: hand off to FolderZipper → get a .zip URL
   - create UploadItem(url:, pane:, state: .pending)
        │
        ▼
3. UploadQueue.enqueue(_ item: UploadItem)   [actor]
   - append item to items[]
   - publish change → UI shows queued badge
   - call upload(item:) inside a Task
        │
        ▼
4. S3Uploader.upload(item:)
   - stat file → fileSize
   - choose path: single (< 5 MB) or multipart (≥ 5 MB)
        │
        ├── single ──────────────────────────────────────────▶ PutObject
        │                                                         │
        └── multipart ──────────────────────────────────────▶ see §Multipart
                                                                  │
        ◀──────────────────────────── result (key, etag) ─────────┘
        │
        ▼
5. URLBuilder.build(key:, pane:)
   - Private pane  → presigned GET URL (7-day SigV4)
   - CDN configured → https://cdn.example.com/{key}
   - else           → https://{bucket}.s3.{region}.amazonaws.com/{key}
        │
        ▼
6. item.state = .complete(url:)
   UploadQueue publishes update → UI shows checkmark
        │
        ▼
7. NotificationManager.postSuccess(url:, filename:)
   - UNMutableNotificationContent with URL in body
   - user click → UNNotificationResponse
       → copy URL to pasteboard
       → post brief "Copied!" toast notification
        │
        ▼
8. HistoryStore.append(UploadRecord)
   - persisted as JSON; last 100 records kept
```

## Drop event handling

`DropPaneView` conforms to SwiftUI's `DropDelegate`. The `performDrop` method iterates the incoming `NSItemProvider` array and loads `kUTTypeFileURL` representations asynchronously. Folders are detected by checking `URLResourceValues.isDirectory`; if a folder is found it is handed to `FolderZipper` which streams a ZIP archive using `Compression.framework` before returning a temporary file URL. The resulting file URL (original or zipped) is wrapped in an `UploadItem` and enqueued.

## UploadQueue actor

```swift
actor UploadQueue: ObservableObject {
    @MainActor @Published var items: [UploadItem] = []

    func enqueue(_ item: UploadItem) async {
        await MainActor.run { items.append(item) }
        await upload(item)
    }

    private func upload(_ item: UploadItem) async {
        do {
            let url = try await S3Uploader.shared.upload(item: item)
            await item.finish(url: url)
            NotificationManager.shared.postSuccess(url: url, item: item)
            await HistoryStore.shared.append(item)
        } catch {
            await item.fail(error: error)
            NotificationManager.shared.postFailure(item: item)
        }
    }
}
```

> [!info] Concurrency model
> Multiple files dropped simultaneously each get their own `Task` inside the actor. The actor serializes access to shared state (the `items` array) but the individual `S3Uploader.upload` calls run concurrently. Within a single multipart upload, part uploads use a `TaskGroup` capped at 4 concurrent parts.

## Multipart upload logic

Files 5 MB or larger use S3 multipart upload. The threshold and part geometry match AWS SDK Swift's `TransferManager` defaults, but Loft wraps it with per-part progress callbacks for UI feedback.

```
if fileSize < 5_000_000:
    PutObject(body: fileData, tagging: tags)

else:
    partSize = max(8_000_000, ceil(fileSize / 10_000))
    // ensures we never exceed S3's 10,000-part limit

    createMultipartUpload(key:, tagging:, acl:)
      → uploadId

    TaskGroup (max 4 concurrent):
        for each part:
            uploadPart(uploadId:, partNumber:, body:)
            → CompletedPart(partNumber:, eTag:)
            → item.progress += partSize / fileSize

    completeMultipartUpload(uploadId:, parts:)
      → final ETag

    on any part failure:
        abortMultipartUpload(uploadId:)
        → retry whole file (see §Retry policy)
```

> [!warning] Part size floor
> AWS requires every part except the last to be at least 5 MiB (5,242,880 bytes). Using 8 MB parts satisfies this with headroom. Do not reduce part size below 5 MiB or `CompleteMultipartUpload` will return `EntityTooSmall`. See [[S3 Multipart Notes]] for the full constraint list.

### Part size formula

```swift
let minPartSize = 8 * 1_000_000            // 8 MB
let maxParts = 10_000
let computed = Int(ceil(Double(fileSize) / Double(maxParts)))
let partSize = max(minPartSize, computed)
// For a 100 GB file: ceil(100_000_000_000 / 10_000) = 10_000_000 (10 MB) → 10 MB used
// For a 10 MB file:  ceil(10_000_000 / 10_000)       = 1_000 → 8 MB floor used
```

## Tag headers

Every S3 request (single and multipart) includes an `x-amz-tagging` header (URL-encoded key=value pairs) with:

| Tag | Value |
|---|---|
| `app` | `loft` |
| `ttl` | `1d`, `30d`, or `none` |
| `uploaded_at` | Unix epoch seconds as a string |

For multipart uploads the tagging header is set on `CreateMultipartUpload`; individual `UploadPart` calls do not carry it.

The `public-read` ACL (`x-amz-acl: public-read`) is set only when the pane's `visibility == .public`. All other panes omit the ACL header and inherit the bucket default (private).

## Progress reporting

`UploadItem` is an `ObservableObject` with a `@Published var progress: Double` in `[0.0, 1.0]`. For single uploads, progress is set to `0.0` at start and `1.0` on completion (binary). For multipart uploads, `S3Uploader` increments progress after each part completes:

```swift
item.progress += Double(partSize) / Double(fileSize)
```

The `PopoverView` observes each item's progress and renders an `indeterminateProgressIndicator` for single uploads and a `ProgressView(value:)` for multipart. The `MenuBarExtra` icon switches to a spinner glyph when `uploadQueue.items.contains { $0.isActive }`.

## Retry policy

| Attempt | Delay before retry |
|---|---|
| 1st failure | immediate retry |
| 2nd failure | 2 seconds |
| 3rd failure (final) | post failure notification |

Backoff is exponential with base 2 seconds, capped at 2 attempts after the first. On final failure the `UploadItem` enters `.failed(error:)` state, `NotificationManager` posts an actionable notification, and the user can click to trigger one more manual retry cycle through the queue.

On any multipart failure, `abortMultipartUpload` is called before the retry to release incomplete part storage on S3. See [[S3 Multipart Notes]] for why aborting is important.

## Key naming

```
{prefix}/{yyyy}/{mm}/{dd}/{nanoid-10}-{safe-original-name}

Examples:
  private/2026/04/23/aB3xY7mNqP-my-document.pdf
  pub/2026/04/23/kL9rT2vWcE-screenshot.png
```

- `nanoid-10`: 10-character URL-safe random ID to prevent collisions
- `safe-original-name`: original filename with non-`[A-Za-z0-9._-]` characters stripped or replaced by `-`, consecutive dashes collapsed, leading/trailing dashes removed

## Folder drop → ZIP

When the item provider delivers a directory URL, `FolderZipper.zip(folder:)` is called before enqueueing. It streams a ZIP archive into a temporary file using `Compression.framework` (no external dependencies). The resulting ZIP's progress feeds into the `UploadItem`'s `.zipping` state which is shown in the UI before the `.uploading` phase begins. The temporary ZIP file is deleted after upload completes or fails.

## Related

- [[Architecture Overview]]
- [[Panes & TTLs]]
- [[S3 Multipart Notes]]
- [[Presigned URL Notes]]
- [[SigV4 Signing]]
- [[Settings]]
- [[Loft Overview]]
