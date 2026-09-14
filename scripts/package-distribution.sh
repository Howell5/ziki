#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$PROJECT_ROOT/outputs"
APP_BUNDLE="$OUTPUT_DIR/Ziki.app"
INFO_PLIST="$PROJECT_ROOT/Packaging/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
ARCHITECTURE="$(uname -m)"
ARTIFACT_BASENAME="Ziki-${VERSION}-macOS-${ARCHITECTURE}"
ZIP_PATH="$OUTPUT_DIR/${ARTIFACT_BASENAME}.zip"
DMG_PATH="$OUTPUT_DIR/${ARTIFACT_BASENAME}.dmg"

for tool in hdiutil ditto; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'error: required tool not found: %s\n' "$tool" >&2
        exit 1
    fi
done

if [[ -n "${ZIKI_CODESIGN_IDENTITY:-}" ]]; then
    "$SCRIPT_DIR/package-app.sh"
else
    # The isolated debug bundle is not a distribution candidate.
    ZIKI_CODESIGN_IDENTITY="Sotto Local Development" \
        ZIKI_CODESIGN_TIMESTAMP=none "$SCRIPT_DIR/package-app.sh"
fi

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ziki-distribution.XXXXXX")"
DMG_SOURCE="$STAGING_ROOT/dmg"
TEMP_DMG="$STAGING_ROOT/${ARTIFACT_BASENAME}.dmg"
trap 'rm -rf -- "$STAGING_ROOT"' EXIT

mkdir -p "$DMG_SOURCE"
ditto "$APP_BUNDLE" "$DMG_SOURCE/Ziki.app"
ln -s /Applications "$DMG_SOURCE/Applications"

if [[ -e "$ZIP_PATH" ]]; then
    rm -f -- "$ZIP_PATH"
fi
ditto \
    -c \
    -k \
    --sequesterRsrc \
    --keepParent \
    "$APP_BUNDLE" \
    "$ZIP_PATH"

hdiutil create \
    -volname "Ziki" \
    -srcfolder "$DMG_SOURCE" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$TEMP_DMG" >/dev/null

if [[ -e "$DMG_PATH" ]]; then
    rm -f -- "$DMG_PATH"
fi
mv "$TEMP_DMG" "$DMG_PATH"

printf '\nDistribution artifacts:\n'
printf '  App: %s\n' "$APP_BUNDLE"
printf '  DMG: %s\n' "$DMG_PATH"
printf '  ZIP: %s\n' "$ZIP_PATH"
printf '\nInstall by opening the DMG and dragging Ziki.app to Applications.\n'
