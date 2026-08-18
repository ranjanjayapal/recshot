import AppKit

@MainActor
final class RegionSelectionController {
    static let shared = RegionSelectionController()

    struct Selection {
        let rect: CGRect
        let screen: NSScreen
    }

    private var windows: [SelectionWindow] = []
    private var keyMonitor: Any?
    private var continuation: CheckedContinuation<Selection?, Never>?
    private var previousApp: NSRunningApplication?

    func select() async -> Selection? {
        if continuation != nil {
            finish(nil)
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            begin()
        }
    }

    private func begin() {
        previousApp = NSWorkspace.shared.frontmostApplication
        windows = NSScreen.screens.map { screen in
            let window = SelectionWindow(screen: screen)
            window.onComplete = { [weak self, weak window] rect in
                guard let self, let window else { return }
                self.finish(Selection(rect: rect, screen: window.screenForCapture))
            }
            window.onCancel = { [weak self] in
                self?.finish(nil)
            }
            return window
        }
        windows.forEach { $0.makeKeyAndOrderFront(nil) }
        windows.first?.makeKey()
        NSApp.activate(ignoringOtherApps: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.finish(nil)
                return nil
            }
            return event
        }
    }

    private func finish(_ selection: Selection?) {
        guard let continuation else { return }
        self.continuation = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        continuation.resume(returning: selection)
    }
}

final class SelectionWindow: NSWindow {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    let screenForCapture: NSScreen

    init(screen: NSScreen) {
        screenForCapture = screen
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: true)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
        hasShadow = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true

        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.onComplete = { [weak self] rect in
            self?.onComplete?(rect)
        }
        view.onCancel = { [weak self] in
            self?.onCancel?()
        }
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SelectionView: NSView {
    var onComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var start: NSPoint?
    private var current: NSPoint?

    private var selectionRect: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        if let selectionRect, selectionRect.width >= 8, selectionRect.height >= 8 {
            onComplete?(selectionRect)
        } else {
            start = nil
            current = nil
            needsDisplay = true
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSColor.black.withAlphaComponent(0.45)
        if let selectionRect, selectionRect.width > 1, selectionRect.height > 1 {
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(rect: selectionRect))
            path.windingRule = .evenOdd
            dim.setFill()
            path.fill()

            NSColor.white.withAlphaComponent(0.92).setStroke()
            let border = NSBezierPath(rect: selectionRect.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1.5
            border.stroke()

            NSColor(red: 1, green: 0.42, blue: 0.28, alpha: 0.95).setStroke()
            let accent = NSBezierPath(rect: selectionRect.insetBy(dx: -1, dy: -1))
            accent.lineWidth = 1
            accent.stroke()

            drawSizeLabel(for: selectionRect)
        } else {
            dim.setFill()
            bounds.fill()
        }

        drawHint()
    }

    private func drawSizeLabel(for rect: CGRect) {
        let text = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attrs)
        var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 14)
        if origin.y < 12 {
            origin.y = rect.minY + 10
        }
        let padding = NSSize(width: 10, height: 6)
        let bubble = NSRect(
            x: origin.x - padding.width,
            y: origin.y - padding.height / 2,
            width: size.width + padding.width * 2,
            height: size.height + padding.height
        )
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 6, yRadius: 6).fill()
        text.draw(at: origin, withAttributes: attrs)
    }

    private func drawHint() {
        let text = "Drag to select  ·  Esc to cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9)
        ]
        let size = text.size(withAttributes: attrs)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: 28)
        let bubble = NSRect(x: origin.x - 12, y: origin.y - 6, width: size.width + 24, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bubble, xRadius: 10, yRadius: 10).fill()
        text.draw(at: origin, withAttributes: attrs)
    }
}
