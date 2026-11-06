#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
OUTPUT="${1:-$PROJECT_DIR/.build/ClashVergeWidget-preview.png}"
BINARY="$PROJECT_DIR/.build/preview-renderer"

mkdir -p "$(dirname "$OUTPUT")"
xcrun swiftc \
    -parse-as-library \
    -O \
    -swift-version 6 \
    -warnings-as-errors \
    -module-name ClashVergeWidgetPreview \
    -target "$ARCH-apple-macos14.0" \
    -sdk "$SDK" \
    -framework AppKit \
    -framework Foundation \
    -framework SwiftUI \
    -framework WidgetKit \
    "$PROJECT_DIR/Sources/ClashVergeWidgetCore/GeneratedBridgeSecret.swift" \
    "$PROJECT_DIR/Sources/ClashVergeWidgetCore/BridgeContract.swift" \
    "$PROJECT_DIR/Sources/ClashVergeWidgetExtension/BridgeClient.swift" \
    "$PROJECT_DIR/Sources/ClashVergeWidgetExtension/StatusProvider.swift" \
    "$PROJECT_DIR/Sources/ClashVergeWidgetExtension/WidgetView.swift" \
    "$PROJECT_DIR/Sources/PreviewRenderer/main.swift" \
    -o "$BINARY"

"$BINARY" "$OUTPUT"
