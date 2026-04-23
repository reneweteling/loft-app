---
title: Glossary
tags: [reference, glossary, definitions]
project: Loft
created: 2026-04-23
---

# Glossary

Definitions for terms used across the Loft vault.

## MenuBarExtra

A SwiftUI scene type introduced in macOS 13 that anchors an app to the macOS status bar (the right side of the menu bar). Loft uses `MenuBarExtra(.window)` style, which renders its content in a floating popover window attached to the status item rather than as a pull-down menu. `MenuBarExtra` replaces older `NSStatusItem` + `NSPopover` boilerplate while retaining access to the underlying `NSStatusItem` for low-level customization (e.g. drag-type registration). See [[Architecture Overview]].

## LSUIElement

An `Info.plist` key (`LSUIElement = YES`) that marks an app as a "UI element" or agent application. An agent app does not appear in the Dock, does not show a menu bar application menu, and is excluded from the cmd-tab switcher. Used by menu bar apps and background daemons that should be invisible except for their status item. Loft sets this in `Info.plist` to remain a pure menu bar experience. See [[File Layout]].

## NSStatusItem

The AppKit class that represents a single item (icon + optional menu/popover) in the macOS status bar area. Underlying `MenuBarExtra` instances. Loft's `StatusItemController` accesses the raw `NSStatusItem` to install a custom `NSView` that registers for drag types — enabling the drag-hover-to-reveal popover behavior. See [[Architecture Overview]].

## Presigned URL

An S3 URL with AWS credentials embedded in the query string so that any HTTP client can access the object without having AWS credentials of its own. The URL is valid only until its expiry time (maximum 7 days with SigV4). Loft generates presigned GET URLs for Private pane uploads. After expiry, S3 returns HTTP 403. See [[Presigned URL Notes]] and [[SigV4 Signing]].

## OAC (Origin Access Control)

CloudFront's mechanism for allowing a CloudFront distribution to access a private S3 bucket without making the bucket publicly readable. OAC replaces the older Origin Access Identity (OAI). With OAC, the S3 bucket policy grants access only to the specific CloudFront distribution; direct S3 URLs return 403. Loft recommends OAC over `public-read` ACL for the Public pane when a CDN is configured. See [[Panes & TTLs]].

## SigV4

AWS Signature Version 4 — the current authentication scheme for all AWS API requests. It derives a request signature by hashing a canonical representation of the HTTP request with an HMAC-SHA256 key derived from the secret access key, date, region, and service name. SigV4 is used for both regular authenticated requests (Authorization header) and presigned URLs (query string). See [[SigV4 Signing]].

## Multipart upload

An S3 mechanism for uploading large objects in parts that can be transmitted concurrently. The workflow is: `CreateMultipartUpload` → N × `UploadPart` → `CompleteMultipartUpload`. Each part (except the last) must be at least 5 MiB. S3 supports up to 10,000 parts and objects up to 5 TiB. On failure, `AbortMultipartUpload` must be called to release incomplete part storage. Loft uses multipart for files ≥ 5 MB with 8 MB parts and 4-way concurrency. See [[S3 Multipart Notes]] and [[Upload Pipeline]].

## TTL

Time to live — the duration after which an S3 object is automatically deleted. Loft encodes TTL as an object tag (`ttl=1d`, `ttl=30d`, `ttl=none`) and relies on S3 lifecycle rules to act on those tags. Lifecycle evaluation runs approximately once per day, so deletion can lag by up to ~24 hours. See [[Panes & TTLs]].

## Gatekeeper

macOS security technology that prevents users from running downloaded apps that are not signed with a trusted Developer ID certificate or distributed through the Mac App Store. Loft is ad-hoc signed (for personal use only) and will trigger a Gatekeeper warning on first launch on a new Mac. The workaround is to right-click → Open the first time, or run `xattr -dr com.apple.quarantine /Applications/Loft.app` in Terminal. See `README.md`.

## SMAppService

A macOS 13+ framework (`ServiceManagement`) API for registering an app to launch at login without requiring a helper bundle or a `LaunchAgent` plist. `SMAppService.mainApp.register()` registers the app; `.unregister()` removes it. The current registration state is readable via `SMAppService.mainApp.status`. Loft uses this in the [[Settings]] General tab for the "Launch at login" toggle.

## Keychain

macOS secure credential storage managed by the Security framework. Keychain items are encrypted at rest and access-controlled per application. Loft stores the AWS Access Key ID and Secret Access Key as `kSecClassGenericPassword` Keychain items scoped to the `com.weteling.loft` service name. Credentials never touch `UserDefaults`, JSON files, or logs. See [[Settings]].

## Template Image

An `NSImage` rendering mode where macOS ignores the image's original colors and uses only the alpha channel to draw the glyph. The system tints the glyph to match the current appearance (dark/light mode, selected state, system accent color). All macOS status item icons should be template images so they adapt automatically. Loft's `MenuBarIcon` imageset has its rendering set to "Template Image" in Xcode's asset catalog. See [[File Layout]].

## UTType

Apple's Uniform Type Identifier system (Swift API: `import UniformTypeIdentifiers`). `UTType` values describe file formats and content kinds (e.g. `UTType.png`, `UTType.pdf`, `UTType.folder`). Loft uses `UTType.preferredMIMEType` to set the `Content-Type` header on S3 uploads so that browsers render images and PDFs inline rather than downloading them. `kUTTypeFileURL` (the legacy Core Services constant) is used in `StatusItemController` to register the status item view for file drag types. See [[Upload Pipeline]].

## Related

- [[Architecture Overview]]
- [[Panes & TTLs]]
- [[Upload Pipeline]]
- [[Settings]]
- [[Presigned URL Notes]]
- [[SigV4 Signing]]
- [[S3 Multipart Notes]]
- [[Loft Overview]]
