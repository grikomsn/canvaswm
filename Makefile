.PHONY: all build clean run app icon dmg zip

# App configuration
APP_NAME := CanvasWM
BUNDLE_ID := co.nibras.canvaswm
VERSION := 1.0.0
SRC := main.swift

# Build directories
BUILD_DIR := build
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources

# Code signing (set via environment or make variable)
# Usage: make sign IDENTITY="Developer ID Application: Your Name"
SIGN_IDENTITY ?= -

all: app

# Generate app icon assets
icon:
	@echo "Generating app icon..."
	cd scripts && swift generate-icon.swift

# Build the binary
build:
	@mkdir -p $(MACOS_DIR)
	swiftc -framework Cocoa -framework ApplicationServices \
		-O -whole-module-optimization \
		-o $(MACOS_DIR)/$(APP_NAME) $(SRC)

# Create the app bundle
app: build icon
	@echo "Creating $(APP_NAME).app bundle..."
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	
	# Copy Info.plist
	cp Info.plist $(CONTENTS_DIR)/Info.plist
	
	# Copy icon files
	@if [ -f AppIcon.icns ]; then \
	    cp AppIcon.icns $(RESOURCES_DIR)/; \
	    echo "Copied AppIcon.icns"; \
	fi
	@if [ -d Assets.xcassets ]; then \
	    cp -R Assets.xcassets $(RESOURCES_DIR)/; \
	    echo "Copied icon assets"; \
	fi
	
	# Compile icon assets if actool is available
	@if command -v actool >/dev/null 2>&1; then \
		actool --output-format human-readable-text \
			--notices \
			--warnings \
			--platform macosx \
			--target-device mac \
			--minimum-deployment-target 11.0 \
			--output-partial-info-plist $(BUILD_DIR)/Assets.plist \
			--compile $(RESOURCES_DIR) \
			Assets.xcassets 2>/dev/null || true; \
		echo "Compiled asset catalog"; \
	fi
	
	# Set executable permissions
	chmod +x $(MACOS_DIR)/$(APP_NAME)
	
	# Code sign the app (ad-hoc by default, use IDENTITY= for proper signing)
	codesign --force --deep --sign "$(SIGN_IDENTITY)" \
		--entitlements entitlements.plist \
		$(APP_DIR) 2>/dev/null || \
	codesign --force --deep --sign - $(APP_DIR)
	
	@echo "$(APP_NAME).app created in $(BUILD_DIR)/"
	@echo "Bundle Identifier: $(BUNDLE_ID)"
	@echo "Version: $(VERSION)"

# Build DMG installer
dmg: app
	@echo "Creating DMG installer..."
	./scripts/build-dmg.sh "$(BUILD_DIR)" "$(APP_NAME)" "$(VERSION)"

# Build ZIP distribution
zip: app
	@echo "Creating ZIP distribution..."
	./scripts/build-zip.sh "$(BUILD_DIR)" "$(APP_NAME)" "$(VERSION)"

# Release build (DMG + ZIP)
release: clean app dmg zip
	@echo "Release build complete!"
	@ls -lh dist/

# Sign with proper Developer ID (usage: make sign IDENTITY="Developer ID Application: Name")
sign:
	@if [ "$(SIGN_IDENTITY)" = "-" ]; then \
		echo "Error: Please provide SIGN_IDENTITY='Developer ID Application: Your Name'"; \
		exit 1; \
	fi
	codesign --force --deep --sign "$(SIGN_IDENTITY)" \
		--entitlements entitlements.plist \
		--timestamp \
		--options runtime \
		$(APP_DIR)
	codesign --verify --verbose $(APP_DIR)
	@echo "Code signing complete with: $(SIGN_IDENTITY)"

# Run the app
run: app
	$(MACOS_DIR)/$(APP_NAME)

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)
	rm -rf dist
	rm -f canvaswm

# Install locally to /Applications (requires sudo)
install: app
	@echo "Installing to /Applications..."
	sudo rm -rf /Applications/$(APP_NAME).app
	sudo cp -R $(APP_DIR) /Applications/
	@echo "Installed to /Applications/$(APP_NAME).app"

# Uninstall from /Applications
uninstall:
	@echo "Uninstalling from /Applications..."
	sudo rm -rf /Applications/$(APP_NAME).app
	@echo "Uninstalled"
