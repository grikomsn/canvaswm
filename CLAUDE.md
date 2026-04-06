# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
./build.sh      # compile (wraps: swiftc -framework Cocoa -framework ApplicationServices -o canvaswm main.swift)
./canvaswm      # run (requires macOS Accessibility permissions)
```

The binary is git-ignored. Always use `./build.sh` rather than invoking `swiftc` directly.

## What This Is

**canvaswm** is a macOS window manager that turns the desktop into an infinite canvas. It intercepts system-wide input events and moves/resizes windows via the Accessibility API.

- **Ctrl+Cmd+drag** — pan all visible windows together
- **Ctrl+Cmd+scroll** — zoom in/out, scaling all windows uniformly from the scroll point
- Windows that drift off-screen are "parked" at (100000, 100000); their virtual canvas positions are preserved in memory

## Architecture

Everything lives in `main.swift` (~250 lines). No packages, no Xcode project.

**Key globals:**
- `virtualPositions` — maps window hash → canvas coordinate (decoupled from real screen position)
- `parkedWindows` — set of windows currently hidden off-screen
- `snapshots` — window frames captured at drag-start, used for batch movement
- `dragActive`, `dragStartMouse` — drag gesture state

**Core flow:**
1. `setupEventTap()` registers a `CGEvent` tap that intercepts mouse/scroll events before they reach other apps
2. On Ctrl+Cmd+scroll: recalculate scale, reposition all windows proportionally
3. On Ctrl+Cmd+drag: translate all non-parked windows by the mouse delta
4. After each reposition: call `isOnScreen()` on every window and park/unpark as needed

**APIs used:**
- `AXUIElement` / `AXUIElementCopyAttributeValue` — read/write window position and size
- `CGEvent` tap — intercept keyboard+mouse events globally
- `NSWorkspace.shared.runningApplications` — enumerate open windows

Accessibility permission is checked at startup via `AXIsProcessTrustedWithOptions`.
