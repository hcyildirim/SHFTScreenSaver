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
    echo "Please place the SHFT logo PNG file as 'shft_logo.png' in the project directory."
    exit 1
fi

# Clean
rm -rf "$BUILD_DIR"

# Create bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Compile Objective-C source into a bundle
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
if [ -f "$PROJECT_DIR/shft_logo_green.png" ]; then
    cp "$PROJECT_DIR/shft_logo_green.png" "$RESOURCES_DIR/shft_logo_green.png"
    echo "Green logo included."
else
    echo "WARNING: shft_logo_green.png not found - green square effect will be skipped."
fi

echo ""
echo "=== Build successful! ==="
echo "Screen saver bundle: $SAVER_BUNDLE"
echo ""
echo "To install:"
echo "  Double-click the .saver file, or run:"
echo "  cp -R \"$SAVER_BUNDLE\" ~/Library/Screen\\ Savers/"
echo ""
echo "Then go to System Settings > Screen Saver and select 'SHFT Screen Saver'"
