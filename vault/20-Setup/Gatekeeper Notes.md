---
title: Gatekeeper Notes
tags: [setup, macos, gatekeeper, install, security]
project: Loft
created: 2026-04-23
---

# Gatekeeper Notes

Loft is distributed as an **ad-hoc signed** `.app` — it is signed with a local certificate but not notarized by Apple. This is intentional for a personal-use tool: notarization requires an Apple Developer Program membership ($99/year) and Apple's automated review, which is overkill for a private tool.

The consequence is that macOS Gatekeeper will quarantine the app on first launch. This page explains what happens and how to clear the quarantine.

---

## What Gatekeeper does

When you download or copy any `.app` that has not been notarized, macOS sets an extended attribute `com.apple.quarantine` on it. On first launch, Gatekeeper sees this attribute and shows a blocking dialog:

> "Loft" cannot be opened because Apple cannot check it for malicious software.

This is not a virus warning — it is Gatekeeper doing its job. The app has not been reviewed by Apple, so macOS won't open it without your explicit consent.

---

## Method 1 — Right-click → Open (easiest)

This is the simplest method and requires no Terminal.

1. Copy `Loft.app` to `/Applications/`
2. Do **not** double-click it
3. Right-click (or Control-click) `Loft.app` in Finder
4. Select **Open** from the context menu
5. A dialog appears: **"macOS cannot verify the developer. Are you sure you want to open it?"**
6. Click **Open**

The quarantine flag is cleared for this app. Future launches work normally with a double-click.

> [!note]
> This right-click → Open flow must be done **once per Mac**. The preference is saved per-app in Gatekeeper's database.

---

## Method 2 — xattr one-liner (fastest for technical users)

Open Terminal and run:

```bash
xattr -dr com.apple.quarantine /Applications/Loft.app
```

- `-d` removes the named attribute
- `-r` applies recursively (covers all files inside the bundle)
- `com.apple.quarantine` is the specific attribute Gatekeeper checks

After this command, Loft opens normally on double-click.

> [!tip]
> If you installed the app somewhere other than `/Applications/`, adjust the path accordingly. Example for a user-local install:
> ```bash
> xattr -dr com.apple.quarantine ~/Applications/Loft.app
> ```

---

## Method 3 — System Settings override

If right-click → Open fails or the dialog does not appear:

1. Try to open `Loft.app` by double-clicking — it will be blocked
2. Open **System Settings → Privacy & Security**
3. Scroll down to the **Security** section
4. You will see: **"Loft was blocked from use because it is not from an identified developer."**
5. Click **Open Anyway**
6. Authenticate with your password or Touch ID

---

## Copying to another Mac

Ad-hoc signed apps can only be opened on the Mac that built them without the right-click workaround. When you copy `Loft.app` to a second Mac:

- The quarantine flag will be set again on the receiving Mac
- Repeat **Method 1 or Method 2** on the new Mac

> [!warning]
> The ad-hoc signature ties the app binary to the signing certificate on the build machine. The signature is valid for Gatekeeper-bypass purposes on macOS 14+ with SIP enabled, but it is not a Developer ID signature. Do not distribute this build to other users — they will hit the same quarantine flow, and you have no recourse if the binary is tampered with in transit.

---

## Installing Loft as a login item

After clearing Gatekeeper, enable **Launch at Login** in Loft:

1. Open Loft (click the menu bar icon)
2. Open **Settings (⌘,)** → **General** tab
3. Toggle **Launch at login** on

Loft uses `SMAppService` — the modern macOS API for login items — which registers it as a proper login item, visible in **System Settings → General → Login Items**.

---

## Checking the app is unsigned (for the curious)

```bash
codesign -dv --verbose=4 /Applications/Loft.app 2>&1 | head -20
```

You will see something like:

```
Executable=/Applications/Loft.app/Contents/MacOS/Loft
Identifier=com.weteling.loft
Format=app bundle with Mach-O universal (x86_64 arm64)
CodeDirectory v=20500 size=... flags=0x2(adhoc) ...
Signature=adhoc
```

`Signature=adhoc` confirms the app is ad-hoc signed, not Developer ID signed. This is expected.

---

## Build script reference

The `scripts/build.sh` in the repository handles the ad-hoc signing step:

```bash
xcodebuild -scheme Loft -configuration Release -archivePath build/Loft.xcarchive archive
xcodebuild -exportArchive \
  -archivePath build/Loft.xcarchive \
  -exportPath build/ \
  -exportOptionsPlist scripts/ExportOptions.plist
codesign --force --deep --sign - build/Loft.app
```

The `--sign -` flag means "sign with an ad-hoc identity". The resulting `.app` passes Gatekeeper after the one-time right-click → Open or `xattr` step.

---

## Related

- [[Bucket Setup]] — S3 configuration required before using the app
- [[IAM Policy]] — credentials needed in Loft Settings
- [[Loft Overview]]
