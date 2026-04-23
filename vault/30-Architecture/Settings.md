---
title: Settings
tags: [architecture, settings, keychain, userdefaults, configuration]
project: Loft
created: 2026-04-23
---

# Settings

Loft's settings window is opened via the standard macOS shortcut `⌘,` (or via the menu bar icon's right-click menu). It is implemented as a SwiftUI `Settings` scene, which automatically binds `⌘,` and renders a native `NSWindow` with a system-style toolbar.

```swift
@main
struct LoftApp: App {
    var body: some Scene {
        MenuBarExtra("Loft", systemImage: "arrow.up.circle") {
            PopoverView()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
```

`SettingsView` hosts a `TabView` with four tabs.

## Tab 1 — General

Controls app-level behaviour that is not specific to any pane or AWS configuration.

| Field | Type | What it controls |
|---|---|---|
| Launch at login | Toggle | Registers / unregisters via `SMAppService.mainApp` |
| Show in menu bar | Toggle | Always `true` for a menu bar app; controls whether the icon is visible when another full-screen app is active |
| Notification sound | Toggle | Whether `UNNotificationContent.sound` is `.default` or `nil` |
| History limit | Stepper (25–500) | Max records kept by `HistoryStore`; oldest trimmed when exceeded |

Persistence: all General fields → `UserDefaults` under `com.weteling.loft` domain.

> [!tip] Launch at login
> `SMAppService.mainApp.register()` is the modern replacement for `LoginItems` and `LaunchAgents` on macOS 13+. It does not require a helper bundle. The toggle in General reads `SMAppService.mainApp.status == .enabled` to initialise its state.

## Tab 2 — Panes

Shows the list of configured `Pane` objects in display order. Users can:

- Add a new pane (opens an inline editor)
- Remove a pane (confirmed with an alert)
- Reorder panes via drag handle
- Edit name, icon, TTL, visibility, key prefix, per-pane bucket override
- Toggle enabled/disabled per pane

| Field | Type | What it controls |
|---|---|---|
| Name | TextField | Display name shown in `PopoverView` |
| Icon | Picker | `iconName` used by `DropPaneView` |
| TTL | Picker | `.none`, `.days(1)`, `.days(30)` |
| Visibility | Picker | `.private`, `.public` |
| Key prefix | TextField | S3 key prefix, e.g. `private/` |
| Bucket override | TextField (optional) | Per-pane bucket; empty = use default bucket from S3 tab |
| Enabled | Toggle | Whether pane appears in the popover |

Persistence: `Pane` array → JSON-encoded into `UserDefaults` via `AppConfig`. `AppConfig` is `Codable` and written on every change.

> [!info] Custom TTL panes
> If a user adds a pane with a custom day count (e.g. 7 days), they must also create a matching lifecycle rule on the S3 bucket using `tag key=ttl, value=7d`. Loft does not create lifecycle rules itself.

## Tab 3 — S3

Configures the S3 connection. Credentials are stored in the macOS Keychain; all other fields go to `UserDefaults`.

| Field | Type | Persistence | What it controls |
|---|---|---|---|
| Access Key ID | SecureField | Keychain | AWS IAM access key |
| Secret Access Key | SecureField | Keychain | AWS IAM secret |
| Region | TextField / Picker | UserDefaults | e.g. `us-east-1`, `eu-west-1` |
| Bucket | TextField | UserDefaults | Default S3 bucket name |
| Custom endpoint | TextField (optional) | UserDefaults | Overrides AWS endpoint; used for R2, B2, MinIO, Spaces |
| Force path-style | Toggle | UserDefaults | Required for MinIO and some S3-compatible services that don't support virtual-hosted-style URLs |
| Test connection | Button | — | Runs `HeadBucket` and shows a success/failure banner |

### Public URL

The S3 tab also contains a **Public URL** section for an optional CDN or reverse proxy fronting the bucket.

| Field | Type | What it controls |
|---|---|---|
| CDN base URL | TextField (optional) | e.g. `https://cdn.example.com`; if set, all non-private URLs are built as `{base}/{key}` |
| Per-pane override | Toggle + TextField (per pane) | Allows different CDN domains per pane |

When a CDN base URL is configured, `URLBuilder` uses it in preference to the raw S3 URL for all panes except Private (which always uses a presigned URL regardless of CDN config). See [[Panes & TTLs]] for the full URL-type matrix.

Persistence: CDN base URL → `UserDefaults` (`cdnBaseURL`).

> [!tip] CloudFront OAC
> If you use CloudFront with Origin Access Control (OAC), the S3 bucket stays fully private. The CDN base URL here would be your CloudFront distribution domain. This is the recommended configuration for the Public pane — it avoids enabling public S3 access. See [[Presigned URL Notes]] for how OAC differs from presigned URLs.

> [!warning] Credential storage
> Access Key ID and Secret Access Key are never written to `UserDefaults`, plist, or JSON files. They are stored exclusively in the macOS Keychain via `Security.framework` using `kSecClassGenericPassword` items scoped to the `com.weteling.loft` service name. See `KeychainStore.swift` for the read/write helpers.

> [!warning] Minimal IAM policy
> Credentials should have only the permissions the app actually uses: `s3:PutObject`, `s3:PutObjectTagging`, `s3:PutObjectAcl` (public pane only), `s3:DeleteObject` (history delete), `s3:HeadBucket`, `s3:GetObject` — all scoped to the single configured bucket. Do not use an admin key.

## Tab 4 — About

Read-only informational tab.

| Item | Source |
|---|---|
| App version | `Bundle.main.infoDictionary["CFBundleShortVersionString"]` |
| Build number | `Bundle.main.infoDictionary["CFBundleVersion"]` |
| Open-source licenses | Link to bundled `LICENSES` file |
| Bucket setup guide | Opens `infra/bucket-setup.md` in the default Markdown viewer |
| GitHub link | Opens project repository in browser |

## Persistence summary

| Data | Storage location | Key/service |
|---|---|---|
| Access Key ID | Keychain `kSecClassGenericPassword` | service: `com.weteling.loft`, account: `aws-access-key-id` |
| Secret Access Key | Keychain `kSecClassGenericPassword` | service: `com.weteling.loft`, account: `aws-secret-access-key` |
| Pane definitions | `UserDefaults` JSON | `panesJSON` |
| Region, bucket, endpoint | `UserDefaults` | `awsRegion`, `awsBucket`, `awsEndpoint` |
| Force path-style | `UserDefaults` | `awsForcePathStyle` |
| CDN base URL | `UserDefaults` | `cdnBaseURL` |
| General toggles | `UserDefaults` | `notificationSound`, `historyLimit` |
| Upload history | JSON file on disk | `~/Library/Application Support/com.weteling.loft/history.json` |

## Related

- [[Architecture Overview]]
- [[Panes & TTLs]]
- [[Upload Pipeline]]
- [[File Layout]]
- [[Glossary]]
- [[Loft Overview]]
