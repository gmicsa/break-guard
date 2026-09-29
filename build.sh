#!/bin/bash
set -e

BUNDLE="BreakGuard.app"
CONTENTS="$BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"

# Build release binary
swift build -c release

# Assemble .app bundle
rm -rf "$BUNDLE"
mkdir -p "$MACOS"
cp .build/release/BreakGuard "$MACOS/BreakGuard"
cp Info.plist "$CONTENTS/Info.plist"

# Copy app icon
mkdir -p "$CONTENTS/Resources"
cp AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

# Ad-hoc sign so macOS allows it to run
codesign --deep --force --sign - "$BUNDLE"

echo "Built: $BUNDLE"
echo "Run:   open $BUNDLE"
