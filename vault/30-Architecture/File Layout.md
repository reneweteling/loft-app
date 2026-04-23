---
title: File Layout
tags: [architecture, source-tree, xcode, swift]
project: Loft
created: 2026-04-23
---

# File Layout

The Loft source tree under `/Users/rene/projects/loft/`. Every directory and file is annotated with its role.

## Full tree

```
loft/
├── Loft.xcodeproj/                 ← Xcode project; checked into git
├── Loft/                           ← Main app target sources
│   ├── LoftApp.swift               ← @main entry point; declares MenuBarExtra and Settings scenes
│   ├── MenuBar/
│   │   ├── StatusItemController.swift  ← NSStatusItem wrapper; installs drag-type registration on the status item NSView; shows/hides popover; drives 3-second auto-dismiss timer
│   │   ├── PopoverView.swift           ← Root SwiftUI view for the popover; lays out DropPaneView cells; hosts History tab toggle
│   │   └── DropPaneView.swift          ← Single pane cell; DropDelegate conformance; resolves NSItemProvider → file URL; hands off to UploadQueue
│   ├── Upload/
│   │   ├── UploadQueue.swift           ← Swift actor; owns items[]; drives per-item Task; manages concurrency; retry loop
│   │   ├── S3Uploader.swift            ← Wraps AWS SDK Swift S3Client; single PutObject + multipart (CreateMultipartUpload / UploadPart / CompleteMultipartUpload / AbortMultipartUpload)
│   │   ├── UploadItem.swift            ← ObservableObject model: file URL, target pane, progress Double, state enum (.pending/.zipping/.uploading/.complete/.failed)
│   │   └── URLBuilder.swift            ← Builds the final shareable URL; branches on pane visibility, CDN config, custom endpoint, presigning for private pane
│   ├── Settings/
│   │   ├── SettingsView.swift          ← TabView container for all 4 settings tabs; opened by ⌘,
│   │   ├── PanesSettingsView.swift     ← Pane list editor: add/remove/reorder/edit panes; writes AppConfig
│   │   ├── S3SettingsView.swift        ← S3 credentials form + Public URL (CDN base URL) section; Test connection button (HeadBucket); writes to Keychain + UserDefaults
│   │   └── KeychainStore.swift         ← Thin Security.framework wrapper: read/write kSecClassGenericPassword items for access key ID and secret
│   ├── Notifications/
│   │   └── NotificationManager.swift   ← Requests UNUserNotificationCenter auth on first run; posts success/failure notifications; handles UNNotificationResponse click (copy URL, retry)
│   ├── Models/
│   │   ├── Pane.swift                  ← Pane struct (Codable, Identifiable); TTL and Visibility enums; default pane seed values
│   │   └── AppConfig.swift             ← Top-level Codable config: pane array, region, bucket, endpoint, CDN URL; persisted to UserDefaults; single source of truth for all settings
│   ├── History/
│   │   ├── HistoryStore.swift          ← Persists last N upload records as JSON to ~/Library/Application Support/com.weteling.loft/history.json; trims oldest when over limit
│   │   └── HistoryView.swift           ← Popover tab showing upload history; actions: re-copy URL, open in browser, delete from S3
│   ├── Archive/
│   │   └── FolderZipper.swift          ← Detects dropped directories; streams a ZIP archive via Compression.framework into a temp file; reports zipping progress; cleans up temp file after upload
│   └── Resources/
│       ├── Assets.xcassets
│       │   ├── AppIcon.appiconset      ← App icon, sizes 16–1024 pt
│       │   ├── MenuBarIcon.imageset    ← Monochrome template image for the status item; renders correctly in light/dark mode and with system tinting
│       │   └── PaneIcons/              ← One imageset per pane (Private, 1Day, 30Days, Public); colorful 64 pt icons used in DropPaneView
│       └── Info.plist                  ← LSUIElement=YES (agent app, no Dock icon); NSUserNotificationsUsageDescription; NSAppTransportSecurity for custom endpoints; hardened runtime entitlements
├── infra/
│   └── bucket-setup.md               ← AWS CLI one-liners for bucket creation, lifecycle rules (1d/30d tags), CORS config, minimal IAM policy; no CDK required
├── scripts/
│   └── build.sh                       ← Runs xcodebuild → copies .app to build/ → applies ad-hoc code signature with codesign -s -
└── README.md                          ← Project overview; install steps; Gatekeeper bypass note; bucket setup pointer
```

## Key relationships

- `LoftApp.swift` instantiates `MenuBarExtra` and `Settings`, bridging SwiftUI scenes to AppKit's `NSStatusItem` via `StatusItemController`.
- `UploadQueue` is the single shared actor instance; both `DropPaneView` (enqueue) and `HistoryView` (delete) call into it.
- `AppConfig` is observed by `PanesSettingsView`, `PopoverView`, and `S3Uploader`; changes propagate via `@Published` without manual notification.
- `KeychainStore` is called only from `S3SettingsView` (write on save) and `S3Uploader` (read at upload time); credentials never pass through `AppConfig` or `UserDefaults`.

## Info.plist essentials

| Key | Value | Why |
|---|---|---|
| `LSUIElement` | `YES` | Hides Dock tile and cmd-tab entry; pure menu bar agent |
| `NSUserNotificationsUsageDescription` | Usage string | Required for `UNUserNotificationCenter` authorization prompt |
| `NSAppTransportSecurity` | Allow arbitrary loads off by default; add exception only for custom endpoint host | Needed if user points at a local MinIO instance over HTTP |
| `com.apple.security.network.client` | `true` (entitlement) | Allows outbound HTTPS to S3 |
| `com.apple.security.files.user-selected.read-only` | `true` (entitlement) | Allows reading dropped files; sandbox is off for ad-hoc personal build, but entitlement is best practice |

> [!info] Sandbox off
> For a personal ad-hoc build, the App Sandbox is disabled. This avoids the complexity of security-scoped bookmarks for arbitrary drag-and-drop file paths. If you ever want to distribute through the Mac App Store, sandbox must be re-enabled and `NSOpenPanel` or security-scoped bookmarks must wrap every file access.

> [!tip] Bundle ID
> The bundle identifier is `com.weteling.loft`. This is used as the Keychain service name, UserDefaults suite name, and the `SMAppService` registration identifier. Change it before distributing to avoid conflicts.

## Related

- [[Architecture Overview]]
- [[Settings]]
- [[Upload Pipeline]]
- [[Panes & TTLs]]
- [[Loft Overview]]
