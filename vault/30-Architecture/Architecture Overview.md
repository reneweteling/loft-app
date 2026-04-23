---
title: Architecture Overview
tags: [architecture, components, swiftui, menubar]
project: Loft
created: 2026-04-23
---

# Architecture Overview

Loft is a native macOS agent application (no Dock icon) built on Swift 5.9 + SwiftUI. It runs as a `MenuBarExtra`, exposes a drag-target popover, queues uploads through an actor, writes to S3 via AWS SDK Swift, and surfaces results through native notifications.

## Component Diagram

```
┌─────────────────────────────────────────────┐
│  MenuBarExtra (status item in menu bar)     │
│  - idle icon                                 │
│  - accepts drag-enter, expands popover       │
│  - spinner during active uploads             │
└─────────────────────────────────────────────┘
                   │ drag hover
                   ▼
┌─────────────────────────────────────────────┐
│  PopoverView (SwiftUI)                       │
│  ┌───────┐ ┌─────┐ ┌──────┐ ┌────┐          │
│  │Private│ │ 1d  │ │ 30d  │ │Pub │          │
│  │  (🔒) │ │(📅) │ │(📆)  │ │(🌐)│          │
│  └───┬───┘ └──┬──┘ └──┬───┘ └─┬──┘          │
└──────┼────────┼───────┼───────┼─────────────┘
       │        │       │       │
       ▼        ▼       ▼       ▼
┌─────────────────────────────────────────────┐
│  UploadQueue (actor)                         │
│  - per-item progress                         │
│  - retries with backoff                      │
│  - multipart for >5 MB, 8 MB parts, 4 concurrent │
└────────────────────┬────────────────────────┘
                     ▼
┌─────────────────────────────────────────────┐
│  S3Client (AWS SDK Swift)                    │
│  putObject / createMultipartUpload           │
│  - tags: app, ttl, uploaded_at               │
│  - ACL: public-read only on public pane      │
└────────────────────┬────────────────────────┘
                     ▼
             (S3 + optional CDN)
                     │
                     ▼
┌─────────────────────────────────────────────┐
│  NotificationManager                         │
│  - success: shows URL, click → copy + toast  │
│  - failure: shows error, click → retry       │
└─────────────────────────────────────────────┘
```

### Telemetry & Analytics

Two complementary stacks, one opt-out toggle (`AppConfig.analyticsEnabled`, surfaced in Settings → General → Privacy):

- **`Telemetry`** wraps the Sentry Cocoa SDK — crashes, app hangs, handled upload errors, anonymous sessions.
- **`Analytics`** wraps PostHog-iOS — product events (`app.launched`, `upload.*`) with `app_version` / `build_type` super-properties. Neither stack receives file names, URLs, or credentials. See [[Telemetry]] for the full data contract, dashboard links, and how to add new events.

## Components

### MenuBarExtra

`MenuBarExtra` is the SwiftUI scene type (macOS 13+) that anchors Loft to the status bar. It owns the status item icon (a template image so it adapts to light/dark mode and system tinting) and hosts the popover window. The icon switches to an animated spinner glyph while the `UploadQueue` has active transfers. Loft uses `MenuBarExtra(.window)` style so the popover is a proper floating window rather than a pull-down menu.

### StatusItemController

`StatusItemController` wraps the underlying `NSStatusItem` and installs a custom `NSView` that registers for `kUTTypeFileURL` drag types. When the system delivers a drag-enter event to the status item area the controller programmatically shows the popover; if the drag exits without a drop the controller starts a 3-second auto-dismiss timer. This indirect drag-detect pattern is necessary because macOS menu bar items do not open on plain hover — see [[Upload Pipeline]] for the full drop-to-upload flow.

### PopoverView

`PopoverView` is the root SwiftUI view rendered inside the `MenuBarExtra` popover. It lays out one `DropPaneView` cell per enabled `Pane` in display-order and includes a tab bar for switching to the history panel. Each `DropPaneView` accepts dropped file URLs, resolves them to `UploadItem` values, and hands them to `UploadQueue`. See [[Panes & TTLs]] for how panes are defined and configured.

### UploadQueue

`UploadQueue` is a Swift `actor` (one per app lifecycle) that serializes access to the upload list and drives concurrency. It maintains an array of `UploadItem` models whose `@Published` progress fields the UI observes. For each item it calls `S3Uploader`, which chooses single `PutObject` or multipart depending on file size — full details in [[Upload Pipeline]].

### S3Uploader

`S3Uploader` is a thin wrapper around AWS SDK Swift's `S3Client`. It handles single-object `putObject` calls for small files and orchestrates `createMultipartUpload → uploadPart (concurrent TaskGroup) → completeMultipartUpload` for larger files. It attaches the required object tags (`app`, `ttl`, `uploaded_at`) on every request and applies the `public-read` ACL only for the Public pane. After a successful upload it invokes `URLBuilder` to produce the final shareable URL. See [[S3 Multipart Notes]] for S3 constraints and [[SigV4 Signing]] for credential signing details.

### NotificationManager

`NotificationManager` requests `UNUserNotificationCenter` authorization on first run and degrades gracefully if the user denies it (the URL is still copied to the clipboard). On upload success it posts a notification with the URL in the body; the user's click triggers a `UNNotificationResponse` handler that copies the URL and posts a brief confirmation toast. On failure it posts an actionable notification whose click triggers a retry through `UploadQueue`.

> [!info] No Dock icon
> `LSUIElement = YES` in `Info.plist` suppresses the Dock tile and cmd-tab entry. Loft is a pure agent app — the menu bar icon is the only affordance. See [[File Layout]] for the full `Info.plist` key list.

## Data flow summary

1. User drops file(s) onto a `DropPaneView`.
2. `DropPaneView` creates `UploadItem(url:, pane:)` and enqueues it via `UploadQueue`.
3. `UploadQueue` calls `S3Uploader.upload(item:)`.
4. `S3Uploader` decides single vs multipart, attaches tags, executes the upload.
5. `URLBuilder` constructs the result URL (CDN / raw S3 / presigned).
6. `NotificationManager` posts the success notification.
7. Click on notification copies URL to clipboard.

## Related

- [[Panes & TTLs]]
- [[Upload Pipeline]]
- [[Settings]]
- [[File Layout]]
- [[S3 Multipart Notes]]
- [[Presigned URL Notes]]
- [[SigV4 Signing]]
- [[Telemetry]]
- [[Loft Overview]]
