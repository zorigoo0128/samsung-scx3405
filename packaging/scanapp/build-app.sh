#!/bin/bash
# Build "Scan SCX3405.app" from the single Swift source file with swiftc.
# No Xcode project: the app is pure SwiftUI + AppKit.
# Usage: build-app.sh "/path/to/Scan SCX3405.app"
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="${1:?usage: build-app.sh <output .app>}"
BIN="Scan SCX3405"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc -O -parse-as-library -target arm64-apple-macos13.0 \
    -o "$APP/Contents/MacOS/$BIN" "$HERE/ScanSCX3405.swift"

cp "$HERE/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature so the bundle is valid on Apple Silicon.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"
