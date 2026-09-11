---
title: Finder Quick Actions
tags: [architecture, finder, services, automator, url-scheme]
project: Loft
created: 2026-09-11
---

# Finder Quick Actions

Right-clicking a file in Finder shows Quick Actions ▸ "Upload to Loft (Private)", "(1 Day)", "(30 Days)", "(Public)": one entry per enabled pane. Choosing one uploads the selection to that pane exactly like a drop on the popover, folders zipped, videos routed through the compression policy.

## Why not NSServices in Loft's Info.plist

An `NSServices` entry in the app's own Info.plist is static and signed. It cannot carry the pane names from Settings, cannot add or remove entries when panes change, and only ever gives one fixed menu item. The user-facing goal is a second-level menu that mirrors the panes, so the entries have to be generated.

Finder Sync extensions can add a real top-level "Loft ▸" submenu, but they need an app-extension target (an Xcode project, not SwiftPM), the user has to enable them in System Settings, and they only apply inside directories the extension registers for. Too heavy for this app.

## What Loft does instead

`FinderQuickActions.sync(panes:)` writes one Automator bundle per enabled pane to `~/Library/Services`:

```
Upload to Loft (1 Day).workflow/
└── Contents/
    ├── Info.plist       NSServices entry, NSMessage = runWorkflowAsService, LoftPaneID = <uuid>
    └── document.wflow   one "Run Shell Script" action, files passed as arguments
```

The shell script hex-encodes every selected path with `od` and calls:

```
open "loft://upload?pane=<pane uuid>&f=<hex path>&f=<hex path>"
```

in batches of 40 files. `AppDelegate.application(_:open:)` receives the URL, `UploadURL.parse` turns it back into file URLs, and `UploadQueue.enqueue(droppedURLs:pane:)` takes over. `StatusItemController.flashPopover()` shows the popover for a few seconds so the upload row is visible, the same feedback a drag gives.

Hex instead of percent-encoding keeps the shell side free of quoting rules and survives any byte a file name can contain. The pane id is a random UUID from `panes.json`, so a web page cannot forge a valid `loft://` URL and trigger an upload of a local file.

## When the bundles are (re)written

- On every launch.
- 500 ms after `AppConfig.panes` changes (the Panes tab edits names live).
- When the Settings → General → Finder toggle flips. Off removes every bundle Loft wrote.

Sync is idempotent: it compares the serialized plist bytes and only touches the disk when something differs, then calls `NSUpdateDynamicServices()` so `pbs` rescans. Bundles are recognised by the `LoftPaneID` key in their Info.plist, so workflows the user created by hand are never touched. Renamed panes get a new bundle name and the old one is removed; disabled or deleted panes lose their bundle.

## Failure modes

- A workflow that outlived its pane (pane deleted while Loft was not running) opens Loft, which cannot find the pane id. Loft resyncs the bundles and posts a failure notification asking the user to right-click again.
- Quick Actions can be switched off per item in System Settings → General → Login Items & Extensions → Finder. Loft cannot flip that from the outside.
- Uninstalling Loft leaves the bundles in `~/Library/Services`; clicking one then fails silently because nothing handles `loft://`. The README tells users to turn the toggle off first.

## Related

- [[Architecture Overview]]
- [[Upload Pipeline]]
- [[Panes & TTLs]]
- [[Telemetry]] (`quickaction.invoked`)
