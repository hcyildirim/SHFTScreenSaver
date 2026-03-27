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
mkdir -p "$BUILD_DIR"

# Step 1: Generate video
echo "Generating animation video (30s @ 30fps)..."
clang \
    -framework Foundation \
    -framework AVFoundation \
    -framework CoreGraphics \
    -framework CoreVideo \
    -framework CoreMedia \
    -fobjc-arc \
    -o "$BUILD_DIR/generate_video" \
    "$PROJECT_DIR/generate_video.m"

cd "$PROJECT_DIR"
"$BUILD_DIR/generate_video"

if [ ! -f "$BUILD_DIR/shft_screensaver.mov" ]; then
    echo "ERROR: Video generation failed"
    exit 1
fi
echo "Video generated."

# Step 2: Create bundle structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Step 3: Compile screen saver (AVPlayer-based)
echo "Compiling screen saver..."
clang \
    -bundle \
    -framework ScreenSaver \
    -framework AppKit \
    -framework AVFoundation \
    -framework CoreMedia \
    -fobjc-arc \
    -o "$MACOS_DIR/SHFTScreenSaver" \
    "$PROJECT_DIR/SHFTScreenSaverView.m"

# Step 4: Copy resources
cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BUILD_DIR/shft_screensaver.mov" "$RESOURCES_DIR/shft_screensaver.mov"

echo ""
echo "=== Build successful! ==="
echo "Screen saver bundle: $SAVER_BUNDLE"
echo ""
echo "To install:"
echo "  cp -R \"$SAVER_BUNDLE\" ~/Library/Screen\\ Savers/"
