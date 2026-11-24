import AppKit

enum ScreenLayout {
    private static let key = "screenLayout"

    static func uuid(of display: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func savedOrigins() -> [String: CGPoint] {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: [Double]] else { return [:] }
        return raw.compactMapValues { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }

    static func save(_ origins: [String: CGPoint]) {
        UserDefaults.standard.set(origins.mapValues { [Double($0.x), Double($0.y)] }, forKey: key)
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func arrangedBounds(of display: CGDirectDisplayID) -> CGRect {
        let real = CGDisplayBounds(display)
        guard let uuid = uuid(of: display), let origin = savedOrigins()[uuid] else { return real }
        return CGRect(origin: origin, size: real.size)
    }
}

final class ArrangeView: NSView {
    struct Tile {
        let uuid: String
        let name: String
        var frame: CGRect
    }

    private var tiles: [Tile] = []
    private var canvas = CGRect.zero
    private var dragged: Int?
    private var grabOffset = CGPoint.zero
    private let margin: CGFloat = 16
    private let hintHeight: CGFloat = 28

    override var isFlipped: Bool { true }

    func reload() {
        tiles = activeDisplays().compactMap { display in
            guard let uuid = ScreenLayout.uuid(of: display) else { return nil }
            return Tile(uuid: uuid, name: screenName(display), frame: ScreenLayout.arrangedBounds(of: display))
        }
        let union = tiles.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let room = tiles.map { max($0.frame.width, $0.frame.height) }.max() ?? 0
        canvas = union.insetBy(dx: -room, dy: -room)
        needsDisplay = true
    }

    private func screenName(_ display: CGDirectDisplayID) -> String {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display
        }
        return screen?.localizedName ?? "Display \(display)"
    }

    private var scale: CGFloat {
        guard canvas.width > 0, canvas.height > 0 else { return 1 }
        let area = bounds.insetBy(dx: margin, dy: margin)
        return min(area.width / canvas.width, (area.height - hintHeight) / canvas.height)
    }

    private func toView(_ rect: CGRect) -> CGRect {
        CGRect(x: margin + (rect.minX - canvas.minX) * scale,
               y: margin + hintHeight + (rect.minY - canvas.minY) * scale,
               width: rect.width * scale,
               height: rect.height * scale)
    }

    private func toLayout(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - margin) / scale + canvas.minX,
                y: (point.y - margin - hintHeight) / scale + canvas.minY)
    }

    private var hint: String {
        guard tiles.count > 1 else { return "Only one screen is connected." }
        var sideBySide = false
        var stacked = false
        for (index, first) in tiles.enumerated() {
            for second in tiles[(index + 1)...] {
                let dx = abs(first.frame.midX - second.frame.midX)
                let dy = abs(first.frame.midY - second.frame.midY)
                if dx > dy { sideBySide = true } else { stacked = true }
            }
        }
        let shortcuts = [
            stacked ? "⌃↑ / ⌃↓ moves between stacked screens" : nil,
            sideBySide ? "⌃⇧← / ⌃⇧→ moves between side-by-side screens" : nil,
        ].compactMap { $0 }
        return "Drag to match your desk. " + shortcuts.joined(separator: ", ") + "."
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        hint.draw(at: CGPoint(x: margin, y: margin),
                  withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])

        for (index, tile) in tiles.enumerated() {
            let rect = toView(tile.frame).insetBy(dx: 2, dy: 2)
            let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
            NSColor.controlAccentColor.withAlphaComponent(index == dragged ? 0.45 : 0.25).setFill()
            path.fill()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.stroke()

            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
            let size = tile.name.size(withAttributes: attributes)
            tile.name.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = tiles.indices.last(where: { toView(tiles[$0].frame).contains(point) }) else { return }
        let grabbed = toLayout(point)
        dragged = index
        grabOffset = CGPoint(x: grabbed.x - tiles[index].frame.minX, y: grabbed.y - tiles[index].frame.minY)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragged else { return }
        let point = toLayout(convert(event.locationInWindow, from: nil))
        tiles[dragged].frame.origin = CGPoint(x: point.x - grabOffset.x, y: point.y - grabOffset.y)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragged = nil
        needsDisplay = true
    }

    func save() {
        ScreenLayout.save(Dictionary(uniqueKeysWithValues: tiles.map { ($0.uuid, $0.frame.origin) }))
    }
}

final class MenuController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let arrangeView = ArrangeView()
    private lazy var window: NSWindow = {
        let size = CGSize(width: 560, height: 380)
        let buttonBar: CGFloat = 52
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Arrange Screens"
        window.isReleasedWhenClosed = false

        let content = NSView(frame: CGRect(origin: .zero, size: size))
        arrangeView.frame = CGRect(x: 0, y: buttonBar, width: size.width, height: size.height - buttonBar)
        arrangeView.autoresizingMask = [.width, .height]
        content.addSubview(arrangeView)

        let done = NSButton(title: "Done", target: self, action: #selector(acceptArrange))
        done.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelArrange))
        cancel.keyEquivalent = "\u{1b}"
        for (offset, button) in [done, cancel].enumerated() {
            button.bezelStyle = .push
            button.frame = CGRect(x: size.width - 16 - CGFloat(offset + 1) * 96, y: 12, width: 88, height: 32)
            button.autoresizingMask = [.minXMargin, .maxYMargin]
            content.addSubview(button)
        }

        window.contentView = content
        window.center()
        return window
    }()

    override init() {
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.split.2x1", accessibilityDescription: "SuperNav")
        let menu = NSMenu()
        menu.addItem(item("Arrange Screens…", #selector(showArrange)))
        menu.addItem(item("Use macOS Arrangement", #selector(resetLayout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit SuperNav", #selector(quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func showArrange() {
        arrangeView.reload()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func acceptArrange() {
        arrangeView.save()
        window.close()
    }

    @objc private func cancelArrange() {
        window.close()
    }

    @objc private func resetLayout() {
        ScreenLayout.reset()
        arrangeView.reload()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
