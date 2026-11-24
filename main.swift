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

func focus(_ window: Window) {
    guard let element = axWindows(of: window.pid).first(where: { windowID(of: $0) == window.id }) else {
        log.error("no accessibility window for \(window.id, privacy: .public) in pid \(window.pid, privacy: .public)")
        return
    }
    let app = AXUIElementCreateApplication(window.pid)
    let frontmost = AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    let main = AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
    let raise = AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    log.notice("focus \(window.id, privacy: .public): frontmost \(frontmost.rawValue, privacy: .public) main \(main.rawValue, privacy: .public) raise \(raise.rawValue, privacy: .public)")
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

func focusMonitor(_ direction: Direction) {
    guard let cursor = CGEvent(source: nil)?.location, let currentDisplay = display(containing: cursor) else { return }
    let origin = arrangedCenter(of: currentDisplay)
    let targetDisplay = activeDisplays()
        .filter { $0 != currentDisplay }
        .compactMap { candidate in distance(from: origin, to: arrangedCenter(of: candidate), going: direction).map { (candidate, $0) } }
        .min { $0.1 < $1.1 }?.0
    guard let targetDisplay else {
        log.notice("no monitor going \(String(describing: direction), privacy: .public)")
        return
    }
    CGWarpMouseCursorPosition(center(of: targetDisplay))
    CGAssociateMouseAndMouseCursorPosition(1)
    if let window = visibleWindows().first(where: { display(containing: $0.center) == targetDisplay }) {
        focus(window)
    }
}

var tap: CFMachPort?

func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    let pass = Unmanaged.passUnretained(event)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return pass
    }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    let modifiers = event.flags.intersection([.maskAlternate, .maskControl, .maskCommand, .maskShift])
    let leftControlHeld = event.flags.rawValue & UInt64(NX_DEVICELCTLKEYMASK) != 0
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
