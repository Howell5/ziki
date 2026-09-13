#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INFO_PLIST="$PROJECT_ROOT/Packaging/Dev-Info.plist"
ENTITLEMENTS="$PROJECT_ROOT/Packaging/Ziki.entitlements"
ASSETS_DIR="$PROJECT_ROOT/Packaging/Assets"
OUTPUT_DIR="$PROJECT_ROOT/outputs"
APP_BUNDLE="$OUTPUT_DIR/Ziki-Dev.app"
SIGN_IDENTITY="${ZIKI_DEVELOPMENT_CODESIGN_IDENTITY:-Sotto Local Development}"
BUILD_SCRATCH_PATH="${ZIKI_BUILD_SCRATCH_PATH:-$PROJECT_ROOT/.build-dev}"

for tool in swift plutil codesign security; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        printf 'error: required tool not found: %s\n' "$tool" >&2
        exit 1
    fi
done

if [[ ! -f "$INFO_PLIST" || ! -f "$ENTITLEMENTS" \
   || ! -f "$ASSETS_DIR/AppIcon.icns" \
   || ! -f "$ASSETS_DIR/ZikiMenuBarTemplate.png" ]]; then
    printf 'error: development packaging metadata is incomplete\n' >&2
    exit 1
fi

plutil -lint "$INFO_PLIST" >/dev/null
plutil -lint "$ENTITLEMENTS" >/dev/null

AVAILABLE_IDENTITIES="$(security find-identity -v -p codesigning 2>&1)"
if [[ "$AVAILABLE_IDENTITIES" != *"\"$SIGN_IDENTITY\""* ]]; then
    cat >&2 <<EOF
error: code-signing identity "$SIGN_IDENTITY" was not found.

Create it once in Keychain Access:
  1. Keychain Access > Certificate Assistant > Create a Certificate
  2. Name: $SIGN_IDENTITY
  3. Identity Type: Self Signed Root
  4. Certificate Type: Code Signing
  5. Enable "Let me override defaults" and accept the remaining defaults

Then verify it with:
  security find-identity -v -p codesigning
EOF
    exit 1
fi

printf 'Building Ziki development app in debug mode…\n'
BUILD_ARGS=(
    --package-path "$PROJECT_ROOT"
    --scratch-path "$BUILD_SCRATCH_PATH"
    --configuration debug
)
swift build \
    "${BUILD_ARGS[@]}" \
    --product Ziki

BIN_DIR="$(swift build \
    "${BUILD_ARGS[@]}" \
    --show-bin-path)"
BINARY="$BIN_DIR/Ziki"

if [[ ! -x "$BINARY" ]]; then
    printf 'error: debug executable was not found under %s\n' "$BIN_DIR" >&2
    exit 1
fi

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ziki-dev-package.XXXXXX")"
STAGED_APP="$STAGING_ROOT/Ziki-Dev.app"
trap 'rm -rf -- "$STAGING_ROOT"' EXIT

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
install -m 0755 "$BINARY" "$STAGED_APP/Contents/MacOS/Ziki"
install -m 0644 "$INFO_PLIST" "$STAGED_APP/Contents/Info.plist"
install -m 0644 "$ASSETS_DIR/AppIcon.icns" \
    "$STAGED_APP/Contents/Resources/AppIcon.icns"
install -m 0644 "$ASSETS_DIR/ZikiMenuBarTemplate.png" \
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

printf 'Signing isolated development app with identity %s…\n' "$SIGN_IDENTITY"
codesign \
    --force \
    --options runtime \
    --timestamp=none \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$STAGED_APP"

codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
plutil -lint "$STAGED_APP/Contents/Info.plist" >/dev/null

mkdir -p "$OUTPUT_DIR"
if [[ -e "$APP_BUNDLE" ]]; then
    BACKUP_APP_BUNDLE="$OUTPUT_DIR/Ziki-Dev.app.backup-$(date +%Y%m%d-%H%M%S)"
    backup_index=0
    while [[ -e "$BACKUP_APP_BUNDLE" ]]; do
        backup_index=$((backup_index + 1))
        BACKUP_APP_BUNDLE="$OUTPUT_DIR/Ziki-Dev.app.backup-$(date +%Y%m%d-%H%M%S).$backup_index"
    done
    mv "$APP_BUNDLE" "$BACKUP_APP_BUNDLE"
    printf 'Preserved previous development app: %s\n' "$BACKUP_APP_BUNDLE"
fi
mv "$STAGED_APP" "$APP_BUNDLE"

printf '\nPackaged isolated development app: %s\n' "$APP_BUNDLE"
printf 'Bundle identifier: com.willhong.sotto.dev\n'
printf 'Production updater: disabled\n'
printf 'Launch only when explicitly requested: open %q\n' "$APP_BUNDLE"
