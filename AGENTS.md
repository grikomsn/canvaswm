# AGENTS.md

macOS window manager in a single Swift file.

## Build & Run

```bash
make            # compile .app bundle
make run        # compile and run
make clean      # remove build artifacts
make dmg        # create DMG installer
make zip        # create ZIP distribution
make release    # build both DMG and ZIP
make install    # install to /Applications
```

### Swift Package Manager

The project is also configured for SPM:

```bash
swift build      # build binary
swift run        # build and run
swift package generate-xcodeproj  # generate Xcode project
```

## GitHub Actions

Automated builds and releases are configured via GitHub Actions.

### Workflows

- **Build** (`.github/workflows/build.yml`): Runs on every PR and push to main
  - Verifies the app builds successfully
  - Checks code signing
  - Uploads app bundle as artifact

- **Release** (`.github/workflows/release.yml`): Runs on version tags (`v*`)
  - Builds signed app bundle
  - Creates DMG and ZIP distributions
  - Uploads to GitHub Releases
  - Supports both Developer ID and ad-hoc signing

### Release Triggers

```bash
git tag v1.0.0
git push origin v1.0.0
```

Or manually trigger from GitHub Actions tab with version override.

### Developer ID Setup (Optional but Recommended)

For properly signed releases that don't show "unidentified developer" warnings:

1. **Export your Developer ID certificate** from Keychain Access:
   - Find "Developer ID Application: Your Name" 
   - Right-click → Export → Save as `.p12` format
   - Set a password for the export

2. **Encode the certificate**:
   ```bash
   base64 -i ~/DeveloperID.p12 | pbcopy
   ```

3. **Add GitHub secrets** (via web or gh CLI):
   ```bash
   gh secret set DEVELOPER_ID_CERTIFICATE_P12 --repo grikomsn/canvaswm
   # Paste the base64-encoded certificate
   
   gh secret set DEVELOPER_ID_CERTIFICATE_PASSWORD --repo grikomsn/canvaswm
   # Enter the export password
   
   gh secret set DEVELOPER_ID_NAME --repo grikomsn/canvaswm
   # Enter: Developer ID Application: Your Name
   ```

4. **Optional: Notarization secrets** (for stapled releases):
   - `APPLE_ID` - Your Apple ID email
   - `APPLE_ID_PASSWORD` - App-specific password
   - `APPLE_TEAM_ID` - Your Apple Developer Team ID

Without Developer ID, releases will use ad-hoc signing (users must right-click → Open).

## Distribution

The project supports creating both **DMG** and **ZIP** distributions for end users:

### Quick Release Build
```bash
make release    # Creates dist/CanvasWM-1.0.0.dmg and dist/CanvasWM-1.0.0.zip
```

### Individual Builds
```bash
make dmg        # Creates dist/CanvasWM-1.0.0.dmg
make zip        # Creates dist/CanvasWM-1.0.0.zip
```

### Code Signing
To sign with your Developer ID (for distribution):
```bash
make app SIGN_IDENTITY="Developer ID Application: Your Name"
make sign SIGN_IDENTITY="Developer ID Application: Your Name"
```

For notarization, sign the DMG after creation:
```bash
codesign --sign "Developer ID Application: Your Name" --timestamp dist/CanvasWM-1.0.0.dmg
```

### Installation
Users can install CanvasWM by:
1. Downloading either the DMG or ZIP
2. Opening DMG: Drag CanvasWM.app to Applications folder
3. Opening ZIP: Extract and drag CanvasWM.app to Applications folder
4. Launching from Applications
5. Granting Accessibility permissions when prompted

## Project Structure

- `main.swift` — Single-file app source (~1000 lines)
- `Package.swift` — Swift Package Manager configuration
- `Info.plist` — App bundle configuration
- `entitlements.plist` — Security entitlements for Accessibility
- `Assets.xcassets/` — App icon assets (SF Symbol-based, generated)
- `AppIcon.icns` — Compiled app icon (generated, git-ignored)
- `scripts/` — Build helper scripts
  - `generate-icon.swift` — Generates PNG icons + AppIcon.icns from SF Symbols
  - `build-dmg.sh` — DMG creation script
  - `build-zip.sh` — ZIP creation script
- `Makefile` — Build automation
- Binary is git-ignored; use `make` instead of invoking `swiftc` directly
- App requires Accessibility permission; checked at startup via `AXIsProcessTrustedWithOptions`
- Menubar-only app (no Dock icon) — controlled via status bar menu
- **Settings Window** (⌘,) — configure hotkeys, pan speed, and behavior
- Settings persist across launches via `UserDefaults`
- View logs in Console.app by filtering for "co.nibras.canvaswm"

## Architecture

Single-file project: `main.swift` (~1000 lines). No packages, no Xcode project.

**Key components:**

- `Config` — UserDefaults wrapper for persistent settings
  - `isEnabled` — global enable/disable toggle
  - `useTwoFingerPan` — two-finger pan vs zoom mode
  - `useWindowClipping` — clip windows at screen edges (default: disabled)
  - `panSpeed` — base panning speed (1-20, default: 8.0)
  - `useAcceleration` — enable panning acceleration (default: true)
  - `requireCmd`, `requireCtrl`, `requireOpt` — configurable hotkey modifiers
- `SettingsWindowController` — preferences window for hotkey/behavior configuration
- `logger` — `os.log` for structured logging
- `virtualPositions: [CFHashCode: CGPoint]` — window hash → canvas coordinate
- `parkedWindows: Set<CFHashCode>` — windows hidden off-screen at (100000, 100000)
- `snapshots: [(AXUIElement, CGPoint, CGSize)]` — window states captured at drag-start
- `originalSizes: [CFHashCode: CGSize]` — pre-zoom sizes for restoration
- `dragActive`, `dragStartMouse` — drag gesture state
- `modifierPanActive` — Ctrl+Opt+Cmd cursor panning state
- `lastPanTime`, `panVelocity` — pan acceleration tracking
- `eventTap: CFMachPort?` — stored reference for enable/disable control
- `statusItem: NSStatusItem?` — menubar icon/menu

**Interaction model:**
- **Configured Modifiers+drag** — pan all visible windows together (mouse drag, configurable via Settings)
- **Configured Modifiers+Option+cursor** — pan all visible windows together (no clicking, just move cursor)
- **Configured Modifiers+scroll** — zoom in/out OR pan canvas with acceleration (depending on "Two Finger Pan" setting)
- Off-screen windows are "parked"; virtual positions preserved in memory
- **Menubar menu** — Enable toggle, Two Finger Pan toggle, Window Clipping toggle, Settings (⌘,), Quit (⌘Q)

**Configurable Hotkeys:**
Access Settings (⌘,) from the menubar to customize:
- **Modifiers**: Command (⌘), Control (⌃), Option (⌥)
- **Pan Speed**: Slider from 1-20 (default: 8.0)
- **Panning Acceleration**: Toggle on/off (default: on)
- Reset to defaults button available

**Panning Acceleration:**
When enabled and two-finger panning is active, the pan speed accelerates based on gesture velocity:
- Slow swipes: base speed (configurable, default 8.0)
- Fast/continuous swipes: speed increases up to 3x via `panVelocity` multiplier
- Velocity decays when pausing or slowing down
- Creates natural, responsive feel similar to native scrolling

**Core flow:**
1. `Config.load()` reads persisted settings on launch
2. `setupEventTap()` registers `CGEvent` tap for global mouse/scroll interception
3. `setupMenuBar()` creates `NSStatusItem` with SF Symbols icons
4. On scroll: either zoom (scale) or pan (translate) based on `useTwoFingerPan`
5. On drag: translate non-parked windows by mouse delta
6. After each movement: `isOnScreen()` decides park/unpark
7. Menu toggles call `CGEvent.tapEnable()` and save to `Config`
8. Settings window allows customization of hotkeys and behavior

**APIs:**
- `AXUIElement` / `AXUIElementCopyAttributeValue` — read/write window geometry
- `CGEvent` tap — global input interception
- `NSWorkspace.shared.runningApplications` — enumerate windows
- `NSStatusBar` / `NSStatusItem` — menubar icon and menu
- `NSWindow` / `NSStackView` — settings window UI
- `AppDelegate` — handles menu actions (@objc selectors)
- `UserDefaults` — configuration persistence
- `os.log` / `Logger` — structured logging
