#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
RELEASE_DIR="${2:-$PROJECT_DIR/release}"
APP="$PROJECT_DIR/dist/Clash Verge Widget.app"

if [[ -z "$VERSION" || ! "$VERSION" =~ ^v?[0-9A-Za-z._-]+$ ]]; then
    echo "Usage: $0 <version> [release-directory]" >&2
    exit 2
fi

if [[ "${CLASH_WIDGET_SKIP_BUILD:-0}" != "1" ]]; then
    "$PROJECT_DIR/Scripts/build.sh"
elif [[ ! -d "$APP" ]]; then
    echo "Missing built app: $APP" >&2
    exit 1
fi

ARCH="$(uname -m)"
PACKAGE_NAME="Clash-Verge-Widget-$VERSION-macOS-$ARCH"
mkdir -p "$PROJECT_DIR/.build"
STAGING_ROOT="$(mktemp -d "$PROJECT_DIR/.build/release.XXXXXX")"
PACKAGE_ROOT="$STAGING_ROOT/$PACKAGE_NAME"
ZIP_PATH="$RELEASE_DIR/$PACKAGE_NAME.zip"
CHECKSUM_PATH="$RELEASE_DIR/SHA256SUMS.txt"

cleanup() {
    rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

mkdir -p "$PACKAGE_ROOT" "$RELEASE_DIR"
codesign --verify --deep --strict --verbose=2 "$APP"
ditto "$APP" "$PACKAGE_ROOT/Clash Verge Widget.app"
cp "$PROJECT_DIR/Scripts/install-release.sh" "$PACKAGE_ROOT/Install.command"
cp "$PROJECT_DIR/Scripts/uninstall.sh" "$PACKAGE_ROOT/Uninstall.command"
cp "$PROJECT_DIR/Resources/LaunchAgent.plist.template" "$PACKAGE_ROOT/LaunchAgent.plist.template"
cp "$PROJECT_DIR/Resources/Release-README.txt" "$PACKAGE_ROOT/README.txt"
cp "$PROJECT_DIR/LICENSE" "$PACKAGE_ROOT/LICENSE.txt"
chmod +x "$PACKAGE_ROOT/Install.command" "$PACKAGE_ROOT/Uninstall.command"

rm -f "$ZIP_PATH" "$CHECKSUM_PATH"
ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_ROOT" "$ZIP_PATH"
(
    cd "$RELEASE_DIR"
    shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
