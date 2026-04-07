// canvaswm — hold Ctrl+Cmd while dragging a window to move all windows together
// Build: make

import Cocoa
import ApplicationServices
import os.log

// MARK: - Logging
let logger = Logger(subsystem: "co.nibras.canvaswm", category: "canvaswm")

// MARK: - Configuration
struct Config {
    private static let defaults = UserDefaults.standard
    private static let enabledKey = "isEnabled"
    private static let twoFingerPanKey = "useTwoFingerPan"
    private static let windowClippingKey = "useWindowClipping"
    private static let panSpeedKey = "panSpeed"
    private static let useAccelerationKey = "useAcceleration"
    private static let requireCmdKey = "requireCmdModifier"
    private static let requireCtrlKey = "requireCtrlModifier"
    private static let requireOptKey = "requireOptModifier"
    private static let zoomGestureKey = "useZoomGesture"
    
    static var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { 
            defaults.set(newValue, forKey: enabledKey)
            logger.info("Config saved: isEnabled = \(newValue)")
        }
    }
    
    static var useTwoFingerPan: Bool {
        get { defaults.bool(forKey: twoFingerPanKey) }
        set { 
            defaults.set(newValue, forKey: twoFingerPanKey)
            logger.info("Config saved: useTwoFingerPan = \(newValue)")
        }
    }
    
    static var useWindowClipping: Bool {
        get { defaults.bool(forKey: windowClippingKey) }
        set { 
            defaults.set(newValue, forKey: windowClippingKey)
            logger.info("Config saved: useWindowClipping = \(newValue)")
        }
    }
    
    static var panSpeed: Double {
        get { defaults.double(forKey: panSpeedKey) }
        set {
            defaults.set(newValue, forKey: panSpeedKey)
            logger.info("Config saved: panSpeed = \(newValue)")
        }
    }
    
    static var useAcceleration: Bool {
        get { defaults.bool(forKey: useAccelerationKey) }
        set {
            defaults.set(newValue, forKey: useAccelerationKey)
            logger.info("Config saved: useAcceleration = \(newValue)")
        }
    }
    
    static var requireCmd: Bool {
        get { defaults.bool(forKey: requireCmdKey) }
        set {
            defaults.set(newValue, forKey: requireCmdKey)
            logger.info("Config saved: requireCmd = \(newValue)")
        }
    }
    
    static var requireCtrl: Bool {
        get { defaults.bool(forKey: requireCtrlKey) }
        set {
            defaults.set(newValue, forKey: requireCtrlKey)
            logger.info("Config saved: requireCtrl = \(newValue)")
        }
    }
    
    static var requireOpt: Bool {
        get { defaults.bool(forKey: requireOptKey) }
        set {
            defaults.set(newValue, forKey: requireOptKey)
            logger.info("Config saved: requireOpt = \(newValue)")
        }
    }
    
    static var useZoomGesture: Bool {
        get { defaults.bool(forKey: zoomGestureKey) }
        set {
            defaults.set(newValue, forKey: zoomGestureKey)
            logger.info("Config saved: useZoomGesture = \(newValue)")
        }
    }
    
    static func load() {
        // Set defaults on first launch
        if defaults.object(forKey: enabledKey) == nil {
            defaults.set(true, forKey: enabledKey)
        }
        if defaults.object(forKey: twoFingerPanKey) == nil {
            defaults.set(false, forKey: twoFingerPanKey)
        }
        if defaults.object(forKey: windowClippingKey) == nil {
            defaults.set(false, forKey: windowClippingKey)
        }
        if defaults.object(forKey: panSpeedKey) == nil {
            defaults.set(8.0, forKey: panSpeedKey)
        }
        if defaults.object(forKey: useAccelerationKey) == nil {
            defaults.set(true, forKey: useAccelerationKey)
        }
        if defaults.object(forKey: requireCmdKey) == nil {
            defaults.set(true, forKey: requireCmdKey)
        }
        if defaults.object(forKey: requireCtrlKey) == nil {
            defaults.set(true, forKey: requireCtrlKey)
        }
        if defaults.object(forKey: requireOptKey) == nil {
            defaults.set(false, forKey: requireOptKey)
        }
        if defaults.object(forKey: zoomGestureKey) == nil {
            defaults.set(false, forKey: zoomGestureKey)
        }
        logger.info("Config loaded successfully")
    }
}

// Menubar state
var statusItem: NSStatusItem?
var eventTap: CFMachPort?
var isEnabled: Bool { Config.isEnabled }
var useTwoFingerPan: Bool { Config.useTwoFingerPan }
var useWindowClipping: Bool { Config.useWindowClipping }
var panSpeed: CGFloat { CGFloat(Config.panSpeed) }
var useAcceleration: Bool { Config.useAcceleration }
var requireCmd: Bool { Config.requireCmd }
var requireCtrl: Bool { Config.requireCtrl }
var requireOpt: Bool { Config.requireOpt }
var useZoomGesture: Bool { Config.useZoomGesture }

// Drag state
var dragActive = false
var modifierPanActive = false
var dragStartMouse = CGPoint.zero
var dragCurrentMouse = CGPoint.zero
var dragPending = false
var draggedElement: AXUIElement? = nil
// Pan acceleration state
var lastPanTime: CFTimeInterval = 0
var panVelocity: CGFloat = 0
let panAccelerationFactor: CGFloat = 1.5
let panMaxSpeedMultiplier: CGFloat = 3.0
// Snapshots of non-dragged windows: (element, virtual position at drag start, size)
var snapshots: [(AXUIElement, CGPoint, CGSize)] = []

// Virtual canvas state — persists across drag gestures
var virtualPositions: [CFHashCode: CGPoint] = [:]
var parkedWindows: Set<CFHashCode> = []
var clippedWindows: Set<CFHashCode> = []
var originalSizes: [CFHashCode: CGSize] = [:]
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
        let vf = screen.frame
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

// Returns the visible (pos, size) of a window clipped to the screen it overlaps most,
// or nil if the window is entirely off-screen.
func clippedFrame(virtualPos: CGPoint, size: CGSize) -> (CGPoint, CGSize)? {
    // If window clipping is disabled, return the window at its virtual position without clipping
    if !useWindowClipping {
        let mainH = NSScreen.main!.frame.height
        for screen in NSScreen.screens {
            let vf = screen.frame
            let sTop    = mainH - (vf.origin.y + vf.height)
            let sBottom = mainH - vf.origin.y
            let sLeft   = vf.origin.x
            let sRight  = vf.origin.x + vf.width
            
            // Title bar must be above screen bottom — once it goes below, park instead
            guard virtualPos.y < sBottom else { continue }
            
            // Just check if window has any overlap with screen
            let horizOverlap = virtualPos.x < sRight && (virtualPos.x + size.width) > sLeft
            let vertOverlap  = virtualPos.y < sBottom && (virtualPos.y + size.height) > sTop
            
            if horizOverlap && vertOverlap {
                // Return unclipped position and size
                return (virtualPos, size)
            }
        }
        return nil
    }
    
    // Original clipping behavior when enabled
    let mainH = NSScreen.main!.frame.height
    var bestArea: CGFloat = 0
    var bestResult: (CGPoint, CGSize)? = nil

    for screen in NSScreen.screens {
        let vf = screen.frame
        let sTop    = mainH - (vf.origin.y + vf.height)
        let sBottom = mainH - vf.origin.y
        let sLeft   = vf.origin.x
        let sRight  = vf.origin.x + vf.width

        // Title bar must be above screen bottom — once it goes below, park instead
        guard virtualPos.y < sBottom else { continue }

        // Horizontal: check overlap but don't clip — macOS handles windows off the sides
        let horizOverlapLeft  = max(virtualPos.x, sLeft)
        let horizOverlapRight = min(virtualPos.x + size.width, sRight)
        guard horizOverlapRight > horizOverlapLeft else { continue }

        // Vertical: clip only the top edge; bottom extends freely
        let clipTop     = max(virtualPos.y, sTop)
        let vertOverlap = min(virtualPos.y + size.height, sBottom) - clipTop
        guard vertOverlap > 0 else { continue }

        let area = (horizOverlapRight - horizOverlapLeft) * vertOverlap
        if area > bestArea {
            bestArea = area
            let retH = (virtualPos.y + size.height) - clipTop
            bestResult = (CGPoint(x: virtualPos.x, y: clipTop), CGSize(width: size.width, height: retH))
        }
    }
    return bestResult
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
        | (1 << CGEventType.mouseMoved.rawValue)

    guard
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ -> Unmanaged<CGEvent>? in
                // Check if disabled
                if !isEnabled { return Unmanaged.passRetained(event) }
                
                // Build dynamic modifier flags based on configuration
                var requiredFlags: CGEventFlags = []
                if requireCmd { requiredFlags.insert(.maskCommand) }
                if requireCtrl { requiredFlags.insert(.maskControl) }
                
                var requiredFlagsWithOpt: CGEventFlags = requiredFlags
                if requireOpt { requiredFlagsWithOpt.insert(.maskAlternate) }
                
                // For basic pan (drag), check if required modifiers are held
                let held = requiredFlags.isEmpty || event.flags.intersection(requiredFlags) == requiredFlags
                
                // For modifier pan (cursor), Option must be held along with base modifiers
                let heldWithOpt = !requiredFlagsWithOpt.isEmpty && event.flags.intersection(requiredFlagsWithOpt) == requiredFlagsWithOpt

                switch type {
                case .leftMouseDown:
                    if held && !modifierPanActive {
                        dragActive = true
                        dragStartMouse = event.location
                        draggedElement = focusedElement()
                        let currentFrames = windowsWithFrames()
                        snapshots = currentFrames.map { (win, actualPos, size) in
                            let key = CFHash(win)
                            let origSize = originalSizes[key] ?? size
                            if parkedWindows.contains(key) {
                                return (win, virtualPositions[key] ?? actualPos, origSize)
                            } else {
                                virtualPositions[key] = actualPos
                                return (win, actualPos, origSize)
                            }
                        }
                        return nil
                    }

                case .leftMouseDragged:
                    if dragActive && held {
                        dragCurrentMouse = event.location
                        if !dragPending {
                            dragPending = true
                            let current = snapshots
                            let start = dragStartMouse
                            DispatchQueue.main.async {
                                dragPending = false
                                let dx = dragCurrentMouse.x - start.x
                                let dy = dragCurrentMouse.y - start.y
                                for (win, virtualOrigin, size) in current {
                                    let key = CFHash(win)
                                    let newVirtual = CGPoint(x: virtualOrigin.x + dx, y: virtualOrigin.y + dy)
                                    virtualPositions[key] = newVirtual

                                    if let (clippedPos, clippedSize) = clippedFrame(virtualPos: newVirtual, size: size) {
                                        parkedWindows.remove(key)
                                        let needsClip = clippedSize.width < size.width - 0.5
                                                     || clippedSize.height < size.height - 0.5
                                        if needsClip {
                                            if originalSizes[key] == nil { originalSizes[key] = size }
                                            clippedWindows.insert(key)
                                            setSize(win, to: clippedSize)
                                            setPosition(win, to: clippedPos)
                                        } else {
                                            if clippedWindows.remove(key) != nil {
                                                originalSizes.removeValue(forKey: key)
                                                setSize(win, to: size)
                                            }
                                            setPosition(win, to: clippedPos)
                                        }
                                    } else if !parkedWindows.contains(key) {
                                        if clippedWindows.remove(key) != nil {
                                            originalSizes.removeValue(forKey: key)
                                            setSize(win, to: size)
                                        }
                                        parkedWindows.insert(key)
                                        setPosition(win, to: parkingSpot)
                                    }
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
                        modifierPanActive = false
                        dragPending = false
                        snapshots = []
                        draggedElement = nil
                        return nil
                    }
                    dragActive = false
                    modifierPanActive = false
                    dragPending = false
                    snapshots = []
                    draggedElement = nil

                case .scrollWheel:
                    if held {
                        let deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
                        let deltaX = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
                        
                        if useTwoFingerPan {
                            // Two-finger pan mode: scroll moves the canvas
                            guard deltaX != 0 || deltaY != 0 else { break }
                            
                            // Capture window positions on first pan
                            if !dragActive {
                                dragActive = true
                                draggedElement = focusedElement()
                                lastPanTime = CACurrentMediaTime()
                                panVelocity = 0
                                let currentFrames = windowsWithFrames()
                                snapshots = currentFrames.map { (win, actualPos, size) in
                                    let key = CFHash(win)
                                    let origSize = originalSizes[key] ?? size
                                    if parkedWindows.contains(key) {
                                        return (win, virtualPositions[key] ?? actualPos, origSize)
                                    } else {
                                        virtualPositions[key] = actualPos
                                        return (win, actualPos, origSize)
                                    }
                                }
                            }
                            
                            // Calculate pan acceleration based on gesture velocity (if enabled)
                            var velocityMultiplier: CGFloat = 1.0
                            if useAcceleration {
                                let currentTime = CACurrentMediaTime()
                                let timeDelta = currentTime - lastPanTime
                                lastPanTime = currentTime
                                
                                // Calculate scroll magnitude (speed of finger movement)
                                let scrollMagnitude = sqrt(deltaX * deltaX + deltaY * deltaY)
                                
                                // Update velocity: if time gap is small, we're panning fast
                                if timeDelta < 0.1 && scrollMagnitude > 0.5 {
                                    // Accelerate: increase velocity multiplier
                                    panVelocity = min(panVelocity + panAccelerationFactor, panMaxSpeedMultiplier)
                                } else {
                                    // Decay velocity when pausing or slowing down
                                    panVelocity = max(panVelocity - panAccelerationFactor * 0.5, 1.0)
                                }
                                velocityMultiplier = panVelocity
                            }
                            
                            // Apply configurable pan speed with velocity acceleration
                            let adjustedSpeed = panSpeed * velocityMultiplier
                            let dx = deltaX * adjustedSpeed
                            let dy = deltaY * adjustedSpeed
                            
                            // Update virtual positions incrementally (like dragging does)
                            let current = snapshots
                            DispatchQueue.main.async {
                                for (win, virtualOrigin, size) in current {
                                    let key = CFHash(win)
                                    // Get current virtual position and add delta
                                    let currentVirtual = virtualPositions[key] ?? virtualOrigin
                                    let newVirtual = CGPoint(x: currentVirtual.x + dx, y: currentVirtual.y + dy)
                                    virtualPositions[key] = newVirtual

                                    if let (clippedPos, clippedSize) = clippedFrame(virtualPos: newVirtual, size: size) {
                                        parkedWindows.remove(key)
                                        let needsClip = clippedSize.width < size.width - 0.5
                                                     || clippedSize.height < size.height - 0.5
                                        if needsClip {
                                            if originalSizes[key] == nil { originalSizes[key] = size }
                                            clippedWindows.insert(key)
                                            setSize(win, to: clippedSize)
                                            setPosition(win, to: clippedPos)
                                        } else {
                                            if clippedWindows.remove(key) != nil {
                                                originalSizes.removeValue(forKey: key)
                                                setSize(win, to: size)
                                            }
                                            setPosition(win, to: clippedPos)
                                        }
                                    } else if !parkedWindows.contains(key) {
                                        if clippedWindows.remove(key) != nil {
                                            originalSizes.removeValue(forKey: key)
                                            setSize(win, to: size)
                                        }
                                        parkedWindows.insert(key)
                                        setPosition(win, to: parkingSpot)
                                    }
                                }
                            }
                            return nil
                        } else {
                            // Zoom mode - only active if zoom gesture is enabled
                            guard useZoomGesture else { break }
                            
                            guard deltaY != 0 else { break }
                            let scale = 1.0 + deltaY * 0.05
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
                    }

                case .mouseMoved:
                    // Ctrl+Opt+Cmd modifier pan (no clicking required)
                    if heldWithOpt {
                        // Capture window positions on first detection
                        if !modifierPanActive {
                            modifierPanActive = true
                            dragStartMouse = event.location
                            draggedElement = focusedElement()
                            let currentFrames = windowsWithFrames()
                            snapshots = currentFrames.map { (win, actualPos, size) in
                                let key = CFHash(win)
                                let origSize = originalSizes[key] ?? size
                                if parkedWindows.contains(key) {
                                    return (win, virtualPositions[key] ?? actualPos, origSize)
                                } else {
                                    virtualPositions[key] = actualPos
                                    return (win, actualPos, origSize)
                                }
                            }
                        }
                        
                        // Update windows as cursor moves
                        dragCurrentMouse = event.location
                        if !dragPending {
                            dragPending = true
                            let current = snapshots
                            let start = dragStartMouse
                            DispatchQueue.main.async {
                                dragPending = false
                                let dx = dragCurrentMouse.x - start.x
                                let dy = dragCurrentMouse.y - start.y
                                for (win, virtualOrigin, size) in current {
                                    let key = CFHash(win)
                                    let newVirtual = CGPoint(x: virtualOrigin.x + dx, y: virtualOrigin.y + dy)
                                    virtualPositions[key] = newVirtual

                                    if let (clippedPos, clippedSize) = clippedFrame(virtualPos: newVirtual, size: size) {
                                        parkedWindows.remove(key)
                                        let needsClip = clippedSize.width < size.width - 0.5
                                                     || clippedSize.height < size.height - 0.5
                                        if needsClip {
                                            if originalSizes[key] == nil { originalSizes[key] = size }
                                            clippedWindows.insert(key)
                                            setSize(win, to: clippedSize)
                                            setPosition(win, to: clippedPos)
                                        } else {
                                            if clippedWindows.remove(key) != nil {
                                                originalSizes.removeValue(forKey: key)
                                                setSize(win, to: size)
                                            }
                                            setPosition(win, to: clippedPos)
                                        }
                                    } else if !parkedWindows.contains(key) {
                                        if clippedWindows.remove(key) != nil {
                                            originalSizes.removeValue(forKey: key)
                                            setSize(win, to: size)
                                        }
                                        parkedWindows.insert(key)
                                        setPosition(win, to: parkingSpot)
                                    }
                                }
                            }
                        }
                        return nil
                    } else if modifierPanActive {
                        // Modifiers released, end the modifier pan
                        modifierPanActive = false
                        dragPending = false
                        snapshots = []
                        draggedElement = nil
                    }

                default:
                    break
                }

                return Unmanaged.passRetained(event)
            },
            userInfo: nil
        )
    else {
        logger.error("Failed to create event tap — check Accessibility permissions.")
        exit(1)
    }

    let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    eventTap = tap  // Store reference for enable/disable
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }
    
    @objc func toggleEnabled() {
        let newValue = !Config.isEnabled
        Config.isEnabled = newValue
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: newValue)
        }
        // Update menu item state
        if let menu = statusItem?.menu,
           let toggleItem = menu.item(at: 1) {
            toggleItem.state = newValue ? .on : .off
        }
        logger.info("Toggled Enabled: \(newValue)")
    }
    
    @objc func toggleTwoFingerPan() {
        let newValue = !Config.useTwoFingerPan
        Config.useTwoFingerPan = newValue
        // Update menu item state
        if let menu = statusItem?.menu,
           let toggleItem = menu.item(at: 2) {
            toggleItem.state = newValue ? .on : .off
        }
        logger.info("Toggled Two Finger Pan: \(newValue)")
    }
    
    @objc func toggleWindowClipping() {
        let newValue = !Config.useWindowClipping
        Config.useWindowClipping = newValue
        // Update menu item state
        if let menu = statusItem?.menu,
           let toggleItem = menu.item(at: 3) {
            toggleItem.state = newValue ? .on : .off
        }
        logger.info("Toggled Window Clipping: \(newValue)")
    }
    
    @objc func toggleZoomGesture() {
        let newValue = !Config.useZoomGesture
        Config.useZoomGesture = newValue
        // Update menu item state
        if let menu = statusItem?.menu,
           let toggleItem = menu.item(at: 4) {
            toggleItem.state = newValue ? .on : .off
        }
        logger.info("Toggled Zoom Gesture: \(newValue)")
    }
    
    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Settings Window

class SettingsWindowController: NSWindowController {
    
    static let shared = SettingsWindowController()
    
    private var panSpeedSlider: NSSlider?
    private var accelerationCheckbox: NSButton?
    private var cmdCheckbox: NSButton?
    private var ctrlCheckbox: NSButton?
    private var optCheckbox: NSButton?
    
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CanvasWM Settings"
        window.center()
        super.init(window: window)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        
        // Main container with proper padding
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.spacing = 24
        mainStack.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mainStack)
        
        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: contentView.topAnchor),
            mainStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
        ])
        
        // MARK: - Hotkey Section
        let hotkeyStack = createSection(title: "Hotkey Modifiers")
        
        // Checkboxes with proper alignment
        let checkboxStack = NSStackView()
        checkboxStack.orientation = .vertical
        checkboxStack.spacing = 12
        checkboxStack.alignment = .leading
        
        cmdCheckbox = NSButton(checkboxWithTitle: "Command (⌘)", target: self, action: #selector(hotkeyChanged))
        cmdCheckbox?.state = Config.requireCmd ? .on : .off
        checkboxStack.addArrangedSubview(cmdCheckbox!)
        
        ctrlCheckbox = NSButton(checkboxWithTitle: "Control (⌃)", target: self, action: #selector(hotkeyChanged))
        ctrlCheckbox?.state = Config.requireCtrl ? .on : .off
        checkboxStack.addArrangedSubview(ctrlCheckbox!)
        
        optCheckbox = NSButton(checkboxWithTitle: "Option (⌥)", target: self, action: #selector(hotkeyChanged))
        optCheckbox?.state = Config.requireOpt ? .on : .off
        checkboxStack.addArrangedSubview(optCheckbox!)
        
        hotkeyStack.addArrangedSubview(checkboxStack)
        
        // Help text with proper indentation
        let helpContainer = NSStackView()
        helpContainer.orientation = .horizontal
        helpContainer.alignment = .top
        helpContainer.spacing = 4
        
        // Indent to align with checkbox text (checkbox width + spacing)
        let indentView = NSView()
        indentView.translatesAutoresizingMaskIntoConstraints = false
        indentView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        helpContainer.addArrangedSubview(indentView)
        
        let helpText = NSTextField(labelWithString: "Hold selected modifiers while dragging windows or moving cursor")
        helpText.font = NSFont.systemFont(ofSize: 11)
        helpText.textColor = .secondaryLabelColor
        helpText.lineBreakMode = .byWordWrapping
        helpContainer.addArrangedSubview(helpText)
        
        hotkeyStack.addArrangedSubview(helpContainer)
        mainStack.addArrangedSubview(hotkeyStack)
        
        // MARK: - Separator
        let separator = NSBox()
        separator.boxType = .separator
        mainStack.addArrangedSubview(separator)
        
        // MARK: - Panning Section
        let panningStack = createSection(title: "Panning Behavior")
        
        // Speed row with aligned elements - left aligned like checkboxes
        let speedContainer = NSStackView()
        speedContainer.orientation = .vertical
        speedContainer.spacing = 12
        speedContainer.alignment = .leading
        
        let speedRow = NSStackView()
        speedRow.orientation = .horizontal
        speedRow.spacing = 12
        speedRow.alignment = .centerY
        speedRow.distribution = .fill
        
        let speedLabel = NSTextField(labelWithString: "Speed:")
        speedLabel.font = NSFont.systemFont(ofSize: 13)
        speedLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        speedRow.addArrangedSubview(speedLabel)
        
        panSpeedSlider = NSSlider(value: Config.panSpeed, minValue: 1, maxValue: 20, target: self, action: #selector(panSpeedChanged))
        panSpeedSlider?.setContentHuggingPriority(.defaultLow, for: .horizontal)
        speedRow.addArrangedSubview(panSpeedSlider!)
        
        let speedValueLabel = NSTextField(labelWithString: String(format: "%.1f", Config.panSpeed))
        speedValueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        speedValueLabel.textColor = .secondaryLabelColor
        speedValueLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        speedValueLabel.tag = 100
        speedRow.addArrangedSubview(speedValueLabel)
        
        speedContainer.addArrangedSubview(speedRow)
        
        // Acceleration checkbox - aligned left
        accelerationCheckbox = NSButton(checkboxWithTitle: "Use panning acceleration", target: self, action: #selector(accelerationChanged))
        accelerationCheckbox?.state = Config.useAcceleration ? .on : .off
        speedContainer.addArrangedSubview(accelerationCheckbox!)
        
        // Acceleration help text - aligned with checkbox
        let accelHelpContainer = NSStackView()
        accelHelpContainer.orientation = .horizontal
        accelHelpContainer.alignment = .top
        accelHelpContainer.spacing = 4
        
        let accelIndentView = NSView()
        accelIndentView.translatesAutoresizingMaskIntoConstraints = false
        accelIndentView.widthAnchor.constraint(equalToConstant: 20).isActive = true
        accelHelpContainer.addArrangedSubview(accelIndentView)
        
        let accelHelpText = NSTextField(labelWithString: "Increases pan speed during fast gestures")
        accelHelpText.font = NSFont.systemFont(ofSize: 11)
        accelHelpText.textColor = .secondaryLabelColor
        accelHelpContainer.addArrangedSubview(accelHelpText)
        
        speedContainer.addArrangedSubview(accelHelpContainer)
        panningStack.addArrangedSubview(speedContainer)
        mainStack.addArrangedSubview(panningStack)
        
        // MARK: - Separator
        let separator2 = NSBox()
        separator2.boxType = .separator
        mainStack.addArrangedSubview(separator2)
        
        // MARK: - Reset Button (centered, subtle)
        let buttonContainer = NSStackView()
        buttonContainer.orientation = .horizontal
        buttonContainer.alignment = .centerY
        buttonContainer.distribution = .fillEqually
        
        // Add flexible spacers on both sides to center the button
        let leftSpacer = NSView()
        leftSpacer.translatesAutoresizingMaskIntoConstraints = false
        let rightSpacer = NSView()
        rightSpacer.translatesAutoresizingMaskIntoConstraints = false
        
        let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetToDefaults))
        resetButton.bezelStyle = .rounded
        resetButton.font = NSFont.systemFont(ofSize: 12)
        
        buttonContainer.addArrangedSubview(leftSpacer)
        buttonContainer.addArrangedSubview(resetButton)
        buttonContainer.addArrangedSubview(rightSpacer)
        
        mainStack.addArrangedSubview(buttonContainer)
    }
    
    private func createSection(title: String) -> NSStackView {
        let section = NSStackView()
        section.orientation = .vertical
        section.spacing = 16
        section.alignment = .leading
        
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        section.addArrangedSubview(titleLabel)
        
        return section
    }
    
    @objc private func hotkeyChanged() {
        Config.requireCmd = cmdCheckbox?.state == .on
        Config.requireCtrl = ctrlCheckbox?.state == .on
        Config.requireOpt = optCheckbox?.state == .on
        logger.info("Hotkey configuration changed: cmd=\(Config.requireCmd), ctrl=\(Config.requireCtrl), opt=\(Config.requireOpt)")
    }
    
    @objc private func panSpeedChanged() {
        let value = panSpeedSlider?.doubleValue ?? 8.0
        Config.panSpeed = value
        
        // Update label
        if let speedLabel = window?.contentView?.viewWithTag(100) as? NSTextField {
            speedLabel.stringValue = String(format: "%.1f", value)
        }
        
        logger.info("Pan speed changed to: \(value)")
    }
    
    @objc private func accelerationChanged() {
        Config.useAcceleration = accelerationCheckbox?.state == .on
        logger.info("Pan acceleration changed to: \(Config.useAcceleration)")
    }
    
    @objc private func resetToDefaults() {
        Config.requireCmd = true
        Config.requireCtrl = true
        Config.requireOpt = false
        Config.panSpeed = 8.0
        Config.useAcceleration = true
        
        // Update UI
        cmdCheckbox?.state = .on
        ctrlCheckbox?.state = .on
        optCheckbox?.state = .off
        panSpeedSlider?.doubleValue = 8.0
        accelerationCheckbox?.state = .on
        
        if let speedLabel = window?.contentView?.viewWithTag(100) as? NSTextField {
            speedLabel.stringValue = "8.0"
        }
        
        logger.info("Settings reset to defaults")
    }
    
    func show() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Menubar

func setupMenuBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    
    if let button = statusItem?.button {
        button.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "CanvasWM")
    }
    
    let menu = NSMenu()
    
    // Header with app icon
    let headerItem = NSMenuItem(title: "CanvasWM", action: nil, keyEquivalent: "")
    headerItem.isEnabled = false
    headerItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
    menu.addItem(headerItem)
    
    // Enable/Disable toggle with power icon
    let toggleItem = NSMenuItem(title: "Enabled", action: #selector(AppDelegate.toggleEnabled), keyEquivalent: "")
    toggleItem.state = isEnabled ? .on : .off
    toggleItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
    menu.addItem(toggleItem)
    
    // Two-finger pan toggle with hand icon
    let twoFingerItem = NSMenuItem(title: "Two Finger Pan", action: #selector(AppDelegate.toggleTwoFingerPan), keyEquivalent: "")
    twoFingerItem.state = useTwoFingerPan ? .on : .off
    twoFingerItem.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: nil)
    menu.addItem(twoFingerItem)
    
    // Window clipping toggle with scissors icon
    let clippingItem = NSMenuItem(title: "Window Clipping", action: #selector(AppDelegate.toggleWindowClipping), keyEquivalent: "")
    clippingItem.state = useWindowClipping ? .on : .off
    clippingItem.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: nil)
    menu.addItem(clippingItem)
    
    // Zoom gesture toggle with magnifying glass icon
    let zoomItem = NSMenuItem(title: "Zoom Gesture", action: #selector(AppDelegate.toggleZoomGesture), keyEquivalent: "")
    zoomItem.state = useZoomGesture ? .on : .off
    zoomItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
    menu.addItem(zoomItem)
    
    menu.addItem(NSMenuItem.separator())
    
    // Settings with gear icon
    let settingsItem = NSMenuItem(title: "Settings...", action: #selector(AppDelegate.openSettings), keyEquivalent: ",")
    settingsItem.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
    menu.addItem(settingsItem)
    
    // Quit with xmark icon
    let quitItem = NSMenuItem(title: "Quit", action: #selector(AppDelegate.quitApp), keyEquivalent: "q")
    quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
    menu.addItem(quitItem)
    
    statusItem?.menu = menu
}

// MARK: - Permission Handling

func checkAndRequestAccessibilityPermissions() -> Bool {
    // Check current permission status - don't prompt, just check
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
    
    // Double-check before showing dialog
    if AXIsProcessTrustedWithOptions(options) {
        return true
    }
    
    // Show permission dialog
    let alert = NSAlert()
    alert.messageText = "Accessibility Permission Required"
    alert.informativeText = "CanvasWM needs Accessibility permissions to manage windows.\n\nPlease grant permission in System Settings → Privacy & Security → Accessibility, then click Retry."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Open System Settings")
    alert.addButton(withTitle: "Retry")
    alert.addButton(withTitle: "Quit")
    
    while true {
        // Check permissions again right before showing dialog
        if AXIsProcessTrustedWithOptions(options) {
            return true
        }
        
        let response = alert.runModal()
        
        switch response {
        case .alertFirstButtonReturn:
            // Open System Settings to Accessibility
            let prefpaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(prefpaneURL)
            
        case .alertSecondButtonReturn:
            // Retry - check permissions again immediately
            if AXIsProcessTrustedWithOptions(options) {
                return true
            }
            // Still not granted, update message and continue loop
            alert.informativeText = "Accessibility permission not yet granted.\n\nPlease enable CanvasWM in System Settings → Privacy & Security → Accessibility, then click Retry."
            
        case .alertThirdButtonReturn:
            // Quit
            logger.error("User chose to quit without granting Accessibility permissions")
            return false
            
        default:
            return false
        }
    }
}

// MARK: - Launch Flow

// Check / request Accessibility permission with user-friendly dialog
if !checkAndRequestAccessibilityPermissions() {
    exit(1)
}

// Load configuration
Config.load()

// Setup event tap
setupEventTap()
logger.info("CanvasWM started — hold Ctrl+Cmd while dragging a window to move all windows together.")

// Start application
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
