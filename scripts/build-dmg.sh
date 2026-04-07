#!/bin/bash
# build-dmg.sh - Create a DMG installer for macOS

set -e

BUILD_DIR="${1:-build}"
APP_NAME="${2:-CanvasWM}"
VERSION="${3:-1.0.0}"

DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DIST_DIR="dist"
TEMP_DIR=$(mktemp -d)
MOUNT_POINT="/Volumes/${APP_NAME}"

echo "Creating DMG: ${DMG_NAME}"

# Create distribution directory
mkdir -p "${DIST_DIR}"

# Create temporary directory structure
mkdir -p "${TEMP_DIR}/${APP_NAME}"

# Copy the app
cp -R "${BUILD_DIR}/${APP_NAME}.app" "${TEMP_DIR}/${APP_NAME}/"

# Create Applications folder alias
ln -s /Applications "${TEMP_DIR}/${APP_NAME}/Applications"

# Create .DS_Store for custom icon arrangement (optional, requires macOS UI)
# We'll use a simple background image or no background for now

# Calculate size needed (app size + 50MB padding)
APP_SIZE=$(du -sm "${BUILD_DIR}/${APP_NAME}.app" | cut -f1)
DMG_SIZE=$((APP_SIZE + 50))

# Create the DMG
echo "Creating temporary DMG..."
hdiutil create -srcfolder "${TEMP_DIR}/${APP_NAME}" \
    -volname "${APP_NAME}" \
    -fs HFS+ \
    -size "${DMG_SIZE}m" \
    -format UDIF \
    -ov \
    "${DIST_DIR}/${DMG_NAME}.temp"

# Convert to compressed read-only DMG
echo "Converting to compressed DMG..."
hdiutil convert "${DIST_DIR}/${DMG_NAME}.temp.dmg" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "${DIST_DIR}/${DMG_NAME}"

# Remove temporary files
rm -f "${DIST_DIR}/${DMG_NAME}.temp.dmg"
rm -rf "${TEMP_DIR}"

# Set DMG icon (optional - set to the app icon)
if [ -f "Assets.xcassets/AppIcon.appiconset/icon_128x128.png" ]; then
    # Copy icon to temporary location and convert to icns if needed
    echo "Setting DMG icon..."
    # Use the app's icon for the DMG
    Rez -append /System/Library/Frameworks/CoreServices.framework/Frameworks/CarbonCore.framework/Resources/blank.rsrc \
        -o "${DIST_DIR}/${DMG_NAME}" 2>/dev/null || true
fi

# Code sign the DMG (optional, requires Developer ID)
if security find-identity -v -p codesigning | grep -q "Developer ID"; then
    echo "Signing DMG..."
    codesign --sign "Developer ID" "${DIST_DIR}/${DMG_NAME}" 2>/dev/null || true
fi

echo "DMG created: ${DIST_DIR}/${DMG_NAME}"
ls -lh "${DIST_DIR}/${DMG_NAME}"
