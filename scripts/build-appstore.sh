#!/usr/bin/env bash
set -euo pipefail

# Mac App Store build. Generates the Xcode project from project.yml, archives
# the sandboxed APP_STORE flavour, and exports a signed installer package
# ready for App Store Connect. Signing is automatic: Xcode picks the Apple
# Distribution certificate and creates or refreshes the Mac App Store
# provisioning profile for com.weteling.loft.
#
# Usage:
#   ./scripts/build-appstore.sh            archive + export build/appstore/Loft.pkg
#   UPLOAD=1 ./scripts/build-appstore.sh   ...and upload it to App Store Connect
#
# Authentication for provisioning and upload, either:
#   - Xcode signed in to the Apple ID (Xcode > Settings > Accounts), or
#   - an App Store Connect API key via ASC_KEY_ID, ASC_ISSUER_ID and
#     ASC_KEY_PATH (the .p8 file). CI uses the key.
#
# CFBundleVersion must grow with every upload; BUILD_NUMBER defaults to a
# minute-resolution timestamp so local and CI uploads never collide.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_ROOT/build/appstore"
ARCHIVE="$OUT_DIR/Loft.xcarchive"
PLIST="$REPO_ROOT/Sources/Loft/Resources/Info.plist"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%y%m%d%H%M)}"

cd "$REPO_ROOT"

AUTH_ARGS=()
if [[ -n "${ASC_KEY_PATH:-}" ]]; then
    AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH"
               -authenticationKeyID "${ASC_KEY_ID:?ASC_KEY_ID is required with ASC_KEY_PATH}"
               -authenticationKeyIssuerID "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required with ASC_KEY_PATH}")
fi

echo "→ Generating Loft.xcodeproj from project.yml..."
xcodegen generate --quiet

echo "→ Stamping CFBundleVersion $BUILD_NUMBER..."
# PlistBuddy re-serialises the whole file (tabs, key order), so restore the
# exact original bytes afterwards rather than setting the value back.
PLIST_BACKUP="$(mktemp)"
cp "$PLIST" "$PLIST_BACKUP"
trap 'cp "$PLIST_BACKUP" "$PLIST"; rm -f "$PLIST_BACKUP"' EXIT
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"

echo "→ Archiving (Release, App Store flavour)..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
LOG="$OUT_DIR/xcodebuild.log"
if ! xcodebuild archive \
    -project Loft.xcodeproj \
    -scheme Loft \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} > "$LOG" 2>&1; then
    grep -E "error:|error " "$LOG" | head -20
    echo "✗ Archive failed, full log: $LOG"
    exit 1
fi

METHOD_DESTINATION="export"
[[ "${UPLOAD:-0}" == "1" ]] && METHOD_DESTINATION="upload"

EXPORT_OPTIONS="$OUT_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>$METHOD_DESTINATION</string>
    <key>teamID</key>
    <string>ND82KXRD2Q</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
PLIST

echo "→ Exporting for App Store Connect ($METHOD_DESTINATION)..."
if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$OUT_DIR" \
    -allowProvisioningUpdates \
    ${AUTH_ARGS[@]+"${AUTH_ARGS[@]}"} >> "$LOG" 2>&1; then
    grep -E "error:|error " "$LOG" | tail -20
    echo "✗ Export failed, full log: $LOG"
    exit 1
fi

if [[ "$METHOD_DESTINATION" == "export" ]]; then
    test -f "$OUT_DIR/Loft.pkg" || { echo "✗ Export produced no Loft.pkg"; exit 1; }
    echo "✓ $OUT_DIR/Loft.pkg (build $BUILD_NUMBER)"
    echo "  Upload with UPLOAD=1, or drop it on Transporter."
else
    echo "✓ Uploaded build $BUILD_NUMBER to App Store Connect"
fi
