#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
SAVER_BUNDLE="$BUILD_DIR/SHFTScreenSaver.saver"
CONTENTS_DIR="$SAVER_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "=== Building SHFT Screen Saver ==="

# Check for logo
if [ ! -f "$PROJECT_DIR/shft_logo.png" ]; then
    echo "ERROR: shft_logo.png not found in $PROJECT_DIR"
    exit 1
fi

# Clean
rm -rf "$BUILD_DIR"

# Create bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Compile
echo "Compiling..."
clang \
    -bundle \
    -framework ScreenSaver \
    -framework AppKit \
    -framework QuartzCore \
    -fobjc-arc \
    -o "$MACOS_DIR/SHFTScreenSaver" \
    "$PROJECT_DIR/SHFTScreenSaverView.m"

# Copy resources
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PROJECT_DIR/shft_logo.png" "$RESOURCES_DIR/shft_logo.png"

echo ""
echo "=== Build successful! ==="
echo "Screen saver bundle: $SAVER_BUNDLE"
