#!/bin/bash
# build-zip.sh - Create a ZIP distribution for macOS

set -e

BUILD_DIR="${1:-build}"
APP_NAME="${2:-CanvasWM}"
VERSION="${3:-1.0.0}"

ZIP_NAME="${APP_NAME}-${VERSION}.zip"
DIST_DIR="dist"

echo "Creating ZIP: ${ZIP_NAME}"

# Create distribution directory
mkdir -p "${DIST_DIR}"

# Create temporary directory for zip contents
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy the app to temp directory
cp -R "${BUILD_DIR}/${APP_NAME}.app" "${TEMP_DIR}/"

# Create README for ZIP
cat > "${TEMP_DIR}/README.txt" << 'EOF'
CanvasWM - macOS Window Manager
================================

CanvasWM turns macOS into an infinite canvas for managing windows.

INSTALLATION:
1. Unzip the archive
2. Drag CanvasWM.app to your Applications folder
3. Launch CanvasWM from Applications
4. Grant Accessibility permissions when prompted

USAGE:
- Hold Ctrl+Cmd while dragging a window to move all windows together
- Hold Ctrl+Cmd+Scroll to zoom in/out on the canvas
- Hold Ctrl+Cmd+Option while moving cursor to pan (no clicking required)

CONFIGURATION:
- Click the CanvasWM icon in the menu bar to access settings
- Customize hotkey modifiers, pan speed, and behavior

REQUIREMENTS:
- macOS 11.0 or later
- Accessibility permissions (required for window management)

For more information, visit: https://github.com/yourusername/canvaswm
EOF

# Create the ZIP with compression level 9
cd "${TEMP_DIR}"
zip -r -9 "${OLDPWD}/${DIST_DIR}/${ZIP_NAME}" "${APP_NAME}.app" README.txt
cd "${OLDPWD}"

# Remove quarantine attribute from the ZIP (optional)
xattr -d com.apple.quarantine "${DIST_DIR}/${ZIP_NAME}" 2>/dev/null || true

echo "ZIP created: ${DIST_DIR}/${ZIP_NAME}"
ls -lh "${DIST_DIR}/${ZIP_NAME}"
