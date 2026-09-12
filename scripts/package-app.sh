#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INFO_PLIST="$PROJECT_ROOT/Packaging/Info.plist"
ENTITLEMENTS="$PROJECT_ROOT/Packaging/Ziki.entitlements"
ASSETS_DIR="$PROJECT_ROOT/Packaging/Assets"
OUTPUT_DIR="$PROJECT_ROOT/outputs"
APP_BUNDLE="$OUTPUT_DIR/Ziki.app"
SIGN_IDENTITY="${ZIKI_CODESIGN_IDENTITY:--}"
TIMESTAMP_MODE="${ZIKI_CODESIGN_TIMESTAMP:-auto}"

for tool in swift plutil codesign; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'error: required tool not found: %s\n' "$tool" >&2
        exit 1
    fi
done

if [[ ! -f "$INFO_PLIST" || ! -f "$ENTITLEMENTS" \
   || ! -f "$ASSETS_DIR/AppIcon.icns" \
   || ! -f "$ASSETS_DIR/ZikiMenuBarTemplate.png" ]]; then
    printf 'error: packaging metadata is incomplete under %s/Packaging\n' "$PROJECT_ROOT" >&2
    exit 1
fi

plutil -lint "$INFO_PLIST" >/dev/null
plutil -lint "$ENTITLEMENTS" >/dev/null

printf 'Building Ziki in release mode…\n'
swift build \
    --package-path "$PROJECT_ROOT" \
    --configuration release \
    --product Ziki
swift build \
    --package-path "$PROJECT_ROOT" \
    --configuration release \
    --product ZikiUpdater

BIN_DIR="$(swift build \
    --package-path "$PROJECT_ROOT" \
    --configuration release \
    --show-bin-path)"
BINARY="$BIN_DIR/Ziki"
UPDATER_BINARY="$BIN_DIR/ZikiUpdater"

if [[ ! -x "$BINARY" || ! -x "$UPDATER_BINARY" ]]; then
    printf 'error: release executables were not found under %s\n' "$BIN_DIR" >&2
    exit 1
fi

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ziki-package.XXXXXX")"
STAGED_APP="$STAGING_ROOT/Ziki.app"
trap 'rm -rf -- "$STAGING_ROOT"' EXIT

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
install -m 0755 "$BINARY" "$STAGED_APP/Contents/MacOS/Ziki"
install -m 0755 \
    "$UPDATER_BINARY" \
    "$STAGED_APP/Contents/MacOS/ZikiUpdater"
install -m 0644 "$INFO_PLIST" "$STAGED_APP/Contents/Info.plist"
install -m 0644 "$ASSETS_DIR/AppIcon.icns" "$STAGED_APP/Contents/Resources/AppIcon.icns"
install -m 0644 \
    "$ASSETS_DIR/ZikiMenuBarTemplate.png" \
    "$STAGED_APP/Contents/Resources/ZikiMenuBarTemplate.png"

GIT_COMMIT="$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
if [[ -n "$GIT_COMMIT" ]]; then
    /usr/libexec/PlistBuddy \
        -c "Add :ZikiBuildCommit string $GIT_COMMIT" \
        "$STAGED_APP/Contents/Info.plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy \
            -c "Set :ZikiBuildCommit $GIT_COMMIT" \
            "$STAGED_APP/Contents/Info.plist"
fi

printf 'Signing app bundle with identity %s…\n' "$SIGN_IDENTITY"
case "$TIMESTAMP_MODE" in
    auto)
        if [[ "$SIGN_IDENTITY" == "-" ]]; then
            TIMESTAMP_ARGUMENT=(--timestamp=none)
        else
            TIMESTAMP_ARGUMENT=(--timestamp)
        fi
        ;;
    none)
        TIMESTAMP_ARGUMENT=(--timestamp=none)
        ;;
    secure)
        TIMESTAMP_ARGUMENT=(--timestamp)
        ;;
    *)
        printf 'error: ZIKI_CODESIGN_TIMESTAMP must be auto, none, or secure\n' >&2
        exit 1
        ;;
esac
codesign \
    --force \
    --options runtime \
    "${TIMESTAMP_ARGUMENT[@]}" \
    --sign "$SIGN_IDENTITY" \
    "$STAGED_APP/Contents/MacOS/ZikiUpdater"
codesign \
    --force \
    --options runtime \
    "${TIMESTAMP_ARGUMENT[@]}" \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$STAGED_APP"

codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
plutil -lint "$STAGED_APP/Contents/Info.plist" >/dev/null

mkdir -p "$OUTPUT_DIR"
if [[ -e "$APP_BUNDLE" ]]; then
    rm -rf -- "$APP_BUNDLE"
fi
mv "$STAGED_APP" "$APP_BUNDLE"

printf '\nPackaged: %s\n' "$APP_BUNDLE"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    printf 'Signature: ad hoc (not notarized; intended for local testing)\n'
else
    printf 'Signature: %s (not notarized by this script)\n' "$SIGN_IDENTITY"
fi
printf 'Launch with: open %q\n' "$APP_BUNDLE"
