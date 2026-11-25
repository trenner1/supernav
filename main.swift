import AppKit
import ApplicationServices
import Carbon.HIToolbox
import os

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

let log = Logger(subsystem: "local.supernav", category: "nav")

enum Direction: CaseIterable {
    case left, right, up, down

    var keyCode: Int64 {
        switch self {
        case .left: return Int64(kVK_LeftArrow)
        case .right: return Int64(kVK_RightArrow)
        case .down: return Int64(kVK_DownArrow)
        case .up: return Int64(kVK_UpArrow)
        }
    }
}

struct Window {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
}

struct MonitorVisit {
    let displayID: CGDirectDisplayID
    let focusedWindow: Window?

    func canReturn(from currentDisplay: CGDirectDisplayID, active: [CGDirectDisplayID]) -> Bool {
        displayID != currentDisplay && active.contains(displayID)
    }

    func preferredWindow(in windows: [Window]) -> Window? {
        guard let focusedWindow else { return nil }
        return windows.first { $0.id == focusedWindow.id && $0.pid == focusedWindow.pid }
    }
}

func visibleWindows() -> [Window] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return entries.compactMap { entry in
        guard entry[kCGWindowLayer as String] as? Int == 0,
              (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let id = entry[kCGWindowNumber as String] as? CGWindowID,
              let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
              let bounds = entry[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds),
              frame.width > 50, frame.height > 50
        else { return nil }
        return Window(id: id, pid: pid, frame: frame)
    }
}

func axWindows(of pid: pid_t) -> [AXUIElement] {
    var value: CFTypeRef?
    let app = AXUIElementCreateApplication(pid)
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
    return value as? [AXUIElement] ?? []
}

func windowID(of element: AXUIElement) -> CGWindowID? {
    var id: CGWindowID = 0
    return _AXUIElementGetWindow(element, &id) == .success ? id : nil
}

func display(containing point: CGPoint) -> CGDirectDisplayID? {
    var id: CGDirectDisplayID = 0
    var count: UInt32 = 0
    guard CGGetDisplaysWithPoint(point, 1, &id, &count) == .success, count > 0 else { return nil }
    return id
}

func distance(from origin: CGPoint, to target: CGPoint, going direction: Direction) -> CGFloat? {
    let dx = target.x - origin.x
    let dy = target.y - origin.y
    let (along, across): (CGFloat, CGFloat)
    switch direction {
    case .left: (along, across) = (-dx, dy)
    case .right: (along, across) = (dx, dy)
    case .up: (along, across) = (-dy, dx)
    case .down: (along, across) = (dy, dx)
    }
    guard along > 1 else { return nil }
    return along + 2 * abs(across)
}

// Returns whether the AX window was found and a focus request was issued.
func requestFocus(_ window: Window) -> Bool {
    guard let element = axWindows(of: window.pid).first(where: { windowID(of: $0) == window.id }) else {
        log.error("no accessibility window for \(window.id, privacy: .public) in pid \(window.pid, privacy: .public)")
        return false
    }
    let app = AXUIElementCreateApplication(window.pid)
    let frontmost = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    let main = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
    let raise = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    log.notice("focus \(window.id, privacy: .public): frontmost \(frontmost.rawValue, privacy: .public) main \(main.rawValue, privacy: .public) raise \(raise.rawValue, privacy: .public)")
    // AX operations can partially succeed. Do not raise a different window
    // after targeting the remembered one.
    return true
}

func activeDisplays() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return [] }
    return Array(ids.prefix(Int(count)))
}

func center(of display: CGDirectDisplayID) -> CGPoint {
    let bounds = CGDisplayBounds(display)
    return CGPoint(x: bounds.midX, y: bounds.midY)
}

func arrangedCenter(of display: CGDirectDisplayID) -> CGPoint {
    let bounds = ScreenLayout.arrangedBounds(of: display)
    return CGPoint(x: bounds.midX, y: bounds.midY)
}

func currentMonitor() -> CGDirectDisplayID? {
    guard let cursor = CGEvent(source: nil)?.location else { return nil }
    return display(containing: cursor)
}

func focusedWindow(on monitor: CGDirectDisplayID, in windows: [Window]) -> Window? {
    guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
    var value: CFTypeRef?
    let app = AXUIElementCreateApplication(pid)
    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    let element = value as! AXUIElement
    guard let id = windowID(of: element) else { return nil }
    return windows.first {
        $0.id == id && $0.pid == pid && display(containing: $0.center) == monitor
    }
}

var previousVisit: MonitorVisit?

func jump(from source: CGDirectDisplayID, to destination: MonitorVisit) {
    let windows = visibleWindows()
    let origin = MonitorVisit(displayID: source, focusedWindow: focusedWindow(on: source, in: windows))
    guard CGWarpMouseCursorPosition(center(of: destination.displayID)) == .success else { return }
    CGAssociateMouseAndMouseCursorPosition(1)
    previousVisit = origin

    let candidates = windows.filter { display(containing: $0.center) == destination.displayID }
    if let preferred = destination.preferredWindow(in: candidates) {
        if requestFocus(preferred) { return }
        if let fallback = candidates.first(where: { $0.id != preferred.id }) {
            _ = requestFocus(fallback)
        }
    } else if let frontmost = candidates.first {
        _ = requestFocus(frontmost)
    }
}

func jumpBack() {
    guard let current = currentMonitor(), let previousVisit,
          previousVisit.canReturn(from: current, active: activeDisplays())
    else { return }
    jump(from: current, to: previousVisit)
}

func focusMonitor(_ direction: Direction) {
    guard let currentDisplay = currentMonitor() else { return }
    let origin = arrangedCenter(of: currentDisplay)
    let targetDisplay = activeDisplays()
        .filter { $0 != currentDisplay }
        .compactMap { candidate in distance(from: origin, to: arrangedCenter(of: candidate), going: direction).map { (candidate, $0) } }
        .min { $0.1 < $1.1 }?.0
    guard let targetDisplay else {
        log.notice("no monitor going \(String(describing: direction), privacy: .public)")
        return
    }
    jump(from: currentDisplay, to: MonitorVisit(displayID: targetDisplay, focusedWindow: nil))
}

var tap: CFMachPort?
var jumpBackKeyIsDown = false

func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    let pass = Unmanaged.passUnretained(event)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        jumpBackKeyIsDown = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return pass
    }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    let modifiers = event.flags.intersection([.maskAlternate, .maskControl, .maskCommand, .maskShift])
    let leftControlHeld = event.flags.rawValue & UInt64(NX_DEVICELCTLKEYMASK) != 0
    if code == Int64(kVK_Space) {
        if type == .keyUp, jumpBackKeyIsDown {
            jumpBackKeyIsDown = false
            return nil
        }
        if type == .keyDown {
            if jumpBackKeyIsDown { return nil }
            if leftControlHeld, modifiers == [.maskControl, .maskShift],
               event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                jumpBackKeyIsDown = true
                DispatchQueue.main.async { jumpBack() }
                return nil
            }
        }
    }
    let monitorKeys: [Direction]
    switch modifiers {
    case .maskControl: monitorKeys = [.up, .down]
    case [.maskControl, .maskShift]: monitorKeys = [.left, .right]
    default: monitorKeys = []
    }
    guard leftControlHeld, let direction = monitorKeys.first(where: { $0.keyCode == code }) else { return pass }
    if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
        DispatchQueue.main.async { focusMonitor(direction) }
    }
    return nil
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let menuController = MenuController()
let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
if !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) {
    log.error("missing Accessibility access")
}

func installTap() {
    let keyEvents = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
    tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                            eventsOfInterest: keyEvents,
                            callback: { _, type, event, _ in handle(type, event) }, userInfo: nil)
    guard let tap else {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { installTap() }
        return
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    log.notice("event tap installed")
}

installTap()
app.run()
