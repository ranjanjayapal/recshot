import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayPanelController {
    static let shared = OverlayPanelController()

    private var panel: OverlayPanel?
    private var cancellables = Set<AnyCancellable>()
    private let padding: CGFloat = 16

    func show() {
        if panel == nil {
            install()
        }
        guard !AppState.shared.isCapturing else { return }
        panel?.orderFrontRegardless()
        reposition()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func resize(to size: NSSize) {
        guard let panel else { return }
        let clamped = NSSize(
            width: max(1, ceil(size.width)),
            height: max(1, ceil(size.height))
        )
        let origin = anchoredOrigin(for: clamped)
        panel.setFrame(NSRect(origin: origin, size: clamped), display: true)
    }

    func reposition() {
        guard let panel else { return }
        var frame = panel.frame
        frame.origin = anchoredOrigin(for: frame.size)
        panel.setFrame(frame, display: true)
    }

    private func install() {
        let panel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .utilityWindow

        let view = SizeReportingHostingView(rootView: StackOverlayRoot())
        view.onSizeChange = { [weak self] size in
            Task { @MainActor in
                self?.resize(to: size)
            }
        }
        if #available(macOS 13.0, *) {
            view.sizingOptions = [.intrinsicContentSize]
        }
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentHuggingPriority(.required, for: .vertical)
        panel.contentView = view
        self.panel = panel

        AppState.shared.$isCapturing
            .receive(on: RunLoop.main)
            .sink { [weak self] capturing in
                if capturing {
                    self?.hide()
                } else {
                    self?.show()
                }
            }
            .store(in: &cancellables)
    }

    private func anchoredOrigin(for size: NSSize) -> NSPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSPoint(
            x: visible.minX + padding,
            y: visible.minY + padding
        )
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SizeReportingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: ((NSSize) -> Void)?
    private var lastSize = NSSize.zero

    override func layout() {
        super.layout()
        let size = fittingSize
        guard size.width > 0, size.height > 0, size != lastSize else { return }
        lastSize = size
        onSizeChange?(size)
    }
}

private struct StackOverlayRoot: View {
    var body: some View {
        StackOverlayView()
            .environmentObject(AppState.shared)
    }
}
