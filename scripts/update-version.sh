#!/usr/bin/env bash
# update-version.sh — sets CFBundleShortVersionString in Info.plist
# Usage: ./scripts/update-version.sh 1.2.3
set -euo pipefail

VERSION="${1:?Usage: $0 <version>}"
PLIST="Sources/Loft/Resources/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${PLIST}"
echo "Set CFBundleShortVersionString to ${VERSION} in ${PLIST}"
