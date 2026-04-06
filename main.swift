// canvaswm — hold Ctrl+Cmd while dragging a window to move all windows together
// Build: swiftc -framework Cocoa -framework ApplicationServices -o tilewm main.swift

import Cocoa
import ApplicationServices

// Drag state
var dragActive = false
var dragStartMouse = CGPoint.zero
var draggedElement: AXUIElement? = nil
// Snapshots of non-dragged windows: (element, virtual position at drag start, size)
var snapshots: [(AXUIElement, CGPoint, CGSize)] = []

// Virtual canvas state — persists across drag gestures
var virtualPositions: [CFHashCode: CGPoint] = [:]
var parkedWindows: Set<CFHashCode> = []
let parkingSpot = CGPoint(x: 100_000, y: 100_000)

func windowsWithPositions() -> [(AXUIElement, CGPoint)] {
    var result: [(AXUIElement, CGPoint)] = []
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

    for app in apps {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
            let windows = ref as? [AXUIElement]
        else { continue }

        for win in windows {
            // Skip minimized
            var minRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef) == .success,
               (minRef as? Bool) == true { continue }

            var posRef: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
                let posVal = posRef
            else { continue }
            var pos = CGPoint.zero
            AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
            result.append((win, pos))
        }
    }
    return result
}

func focusedElement() -> AXUIElement? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var ref: CFTypeRef?
    guard
        AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &ref) == .success
    else { return nil }
    return (ref as! AXUIElement)
}

func setPosition(_ element: AXUIElement, to point: CGPoint) {
    var p = point
    let val = AXValueCreate(.cgPoint, &p)!
    AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, val)
}

func getSize(_ element: AXUIElement) -> CGSize {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &ref) == .success,
          let val = ref else { return .zero }
    var size = CGSize.zero
    AXValueGetValue(val as! AXValue, .cgSize, &size)
    return size
}

func setSize(_ element: AXUIElement, to size: CGSize) {
    var s = size
    let val = AXValueCreate(.cgSize, &s)!
    AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, val)
}

let titleBarHeight: CGFloat = 28

func isOnScreen(_ pos: CGPoint, size: CGSize) -> Bool {
    let mainH = NSScreen.main!.frame.height
    for screen in NSScreen.screens {
        let vf = screen.visibleFrame
        let axTop    = mainH - (vf.origin.y + vf.height)
        let axBottom = mainH - vf.origin.y
        let axLeft   = vf.origin.x
        let axRight  = vf.origin.x + vf.width
        let vertOK  = pos.y >= axTop && pos.y < axBottom
        let horizOK = pos.x < axRight && (pos.x + size.width) > axLeft
        if vertOK && horizOK { return true }
    }
    return false
}

func windowsWithFrames() -> [(AXUIElement, CGPoint, CGSize)] {
    var result: [(AXUIElement, CGPoint, CGSize)] = []
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }

    for app in apps {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref) == .success,
            let windows = ref as? [AXUIElement]
        else { continue }

        for win in windows {
            var minRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(win, kAXMinimizedAttribute as CFString, &minRef) == .success,
               (minRef as? Bool) == true { continue }

            var posRef: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &posRef) == .success,
                let posVal = posRef
            else { continue }
            var pos = CGPoint.zero
            AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)

            let size = getSize(win)
            result.append((win, pos, size))
        }
    }
    return result
}

func setupEventTap() {
    let mask: CGEventMask =
        (1 << CGEventType.leftMouseDown.rawValue)
        | (1 << CGEventType.leftMouseDragged.rawValue)
        | (1 << CGEventType.leftMouseUp.rawValue)
        | (1 << CGEventType.scrollWheel.rawValue)

    guard
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ -> Unmanaged<CGEvent>? in
                let cmdOpt: CGEventFlags = [.maskCommand, .maskControl]
                let held = event.flags.intersection(cmdOpt) == cmdOpt

                switch type {
                case .leftMouseDown:
                    if held {
                        dragActive = true
                        dragStartMouse = event.location
                        draggedElement = focusedElement()
                        let currentFrames = windowsWithFrames()
                        snapshots = currentFrames.map { (win, actualPos, size) in
                            let key = CFHash(win)
                            if parkedWindows.contains(key) {
                                return (win, virtualPositions[key] ?? actualPos, size)
                            } else {
                                virtualPositions[key] = actualPos
                                return (win, actualPos, size)
                            }
                        }
                        return nil
                    }

                case .leftMouseDragged:
                    if dragActive && held {
                        let loc = event.location
                        let dx = loc.x - dragStartMouse.x
                        let dy = loc.y - dragStartMouse.y
                        let current = snapshots
                        DispatchQueue.main.async {
                            for (win, virtualOrigin, size) in current {
                                let key = CFHash(win)
                                let newVirtual = CGPoint(x: virtualOrigin.x + dx, y: virtualOrigin.y + dy)
                                virtualPositions[key] = newVirtual
                                if isOnScreen(newVirtual, size: size) {
                                    parkedWindows.remove(key)
                                    setPosition(win, to: newVirtual)
                                } else if !parkedWindows.contains(key) {
                                    parkedWindows.insert(key)
                                    setPosition(win, to: parkingSpot)
                                }
                            }
                        }
                        return nil 
                    } else if !held {
                        dragActive = false
                    }

                case .leftMouseUp:
                    if dragActive {
                        dragActive = false
                        snapshots = []
                        draggedElement = nil
                        return nil
                    }
                    dragActive = false
                    snapshots = []
                    draggedElement = nil

                case .scrollWheel:
                    if held {
                        let delta = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
                        guard delta != 0 else { break }
                        let scale = 1.0 + delta * 0.05
                        let center = event.location
                        let frames = windowsWithFrames()
                        DispatchQueue.main.async {
                            for (win, pos, size) in frames {
                                if parkedWindows.contains(CFHash(win)) { continue }
                                let newW = max(100, size.width * scale)
                                let newH = max(60, size.height * scale)
                                let newX = center.x + (pos.x - center.x) * scale
                                let newY = center.y + (pos.y - center.y) * scale
                                setSize(win, to: CGSize(width: newW, height: newH))
                                setPosition(win, to: CGPoint(x: newX, y: newY))
                            }
                        }
                        return nil  // swallow so OS doesn't scroll anything
                    }

                default:
                    break
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        )
    else {
        print("Failed to create event tap — check Accessibility permissions.")
        exit(1)
    }

    let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
}

// Check / prompt for Accessibility permission
let trusted = AXIsProcessTrustedWithOptions(
    [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
if !trusted {
    print("Grant Accessibility access in System Settings → Privacy & Security → Accessibility, then relaunch.")
    exit(1)
}

setupEventTap()
print("Running — hold Ctrl+Cmd while dragging a window to move all windows together.")
NSApplication.shared.run()
