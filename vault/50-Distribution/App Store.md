---
title: App Store
tags: [distribution, app-store, sandbox, signing, xcodegen]
project: Loft
created: 2026-09-11
---

# App Store

Loft ships through two channels from one codebase. The GitHub release is the source-available build (PolyForm Noncommercial, see `LICENSE.md`), the Mac App Store edition is the paid copy for people who want automatic updates and a commercial license.

## Two flavours, one flag

`Distribution.current` (`Sources/Loft/Distribution.swift`) is decided at compile time. The Xcode project sets `SWIFT_ACTIVE_COMPILATION_CONDITIONS = APP_STORE`; the SwiftPM build behind `scripts/build.sh` does not.

| | GitHub build | App Store edition |
|---|---|---|
| Sandbox | off | on (`Loft.entitlements`) |
| Updates | `UpdateChecker` polls GitHub releases, About shows a Download button | off; About says updates arrive through the store, plus "Rate Loft" once `Distribution.appStoreID` is set |
| Finder | Quick Actions written to `~/Library/Services` | none yet; the sandbox cannot write there (see below) |
| Feedback | "Report a problem" opens a prefilled GitHub issue | same, channel prefilled as Mac App Store |
| Review prompt | never | `ReviewPrompt` asks once after 10 successful uploads |
| Telemetry | `channel = github` | `channel = appstore` |
| Signing | Developer ID + notarization (`release.yml`) | Apple Distribution + Mac App Store profile (`appstore.yml`) |

Everything App Review or the sandbox rules out for the store copy is a property on `Distribution`, so call sites read as policy.

## Build

- `project.yml` is the XcodeGen spec. `Loft.xcodeproj` is generated and git-ignored.
- `scripts/build-appstore.sh` generates the project, stamps `CFBundleVersion` with a minute-resolution timestamp (App Store Connect needs a strictly increasing build number per version), archives with automatic signing and `-allowProvisioningUpdates`, and exports `build/appstore/Loft.pkg`. `UPLOAD=1` uploads instead.
- Authentication is either Xcode signed in to the Apple ID, or an App Store Connect API key via `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`. CI (`.github/workflows/appstore.yml`) uses the key and Xcode's cloud-managed certificates, so no certificate export lives in GitHub secrets.
- `ITSAppUsesNonExemptEncryption = false` in Info.plist (HTTPS only) skips the export compliance question on every upload.
- `Sources/Loft/Resources/PrivacyInfo.xcprivacy` declares what Sentry and PostHog collect and the required-reason APIs (UserDefaults, file timestamps). Keep it in step with Settings > General > Privacy and with the App Store privacy label.
- `AppIcon.icns` is committed under Resources for the Xcode build; `scripts/make-icon.swift` stays the source and `build.sh` still regenerates it for the GitHub build.

## What the sandbox changed

- Folder zipping moved from a `ditto` child process to ZIPFoundation, in-process. A child process is not guaranteed the access a drop grants on the folder, and the two builds should behave the same.
- Drops keep working: `files.user-selected.read-only` covers files handed over by drag and drop.
- Settings, history and panes live in `~/Library/Containers/com.weteling.loft/` for the store copy. Someone moving from the GitHub build enters the S3 credentials once more; the keychain item of the Developer ID build is not readable by the differently signed store build.
- Quick Actions are off in the store copy. The MAS-compliant replacement is a Finder Sync extension plus a one-time "grant access to your home folder" (the `bookmarks.app-scope` entitlement is already in place for that). Not built yet.
- Xcode (14 and later) also manages the sandbox, network and user-selected-files entitlements through build settings (`ENABLE_APP_SANDBOX`, `ENABLE_OUTGOING_NETWORK_CONNECTIONS`, `ENABLE_USER_SELECTED_FILES` in `project.yml`); with those off it strips the keys from the file. Keep file and settings in step, and after touching either check `codesign -d --entitlements - build/appstore/Loft.xcarchive/Products/Applications/Loft.app`.
- XcodeGen's `info:` and `entitlements:` keys *generate* files at the given paths. project.yml deliberately uses plain `INFOPLIST_FILE` and `CODE_SIGN_ENTITLEMENTS` settings instead, so the tracked files survive `xcodegen generate`.

## Release rhythm

1. semantic-release cuts vX.Y.Z on GitHub as before.
2. Run the App Store workflow by hand (or `UPLOAD=1 ./scripts/build-appstore.sh`). It builds from the latest tag.
3. Wait for App Store Connect to process the build, attach it to the version, submit for review. Reviewers need a test bucket with credentials in the review notes, otherwise they only see the "Set up AWS credentials first" screen.
4. Once the app record exists, put its Apple ID in `Distribution.appStoreID` so the About tab shows "Rate Loft".

## Related

- [[Architecture Overview]]
- [[Finder Quick Actions]]
- [[Telemetry]]
