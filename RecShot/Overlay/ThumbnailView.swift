import AppKit
import SwiftUI

struct ThumbnailCard: View {
    let item: ScreenshotItem
    @EnvironmentObject private var state: AppState
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: item.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 132, height: 88)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(hovering ? 0.55 : 0.22), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: hovering ? 10 : 6, y: 3)

            DragSourceRepresentable(
                url: item.url,
                preview: item.thumbnail,
                isVideo: item.isVideo,
                onClick: { state.copy(item) },
                onCopy: { state.copy(item) },
                onReveal: { state.reveal(item) },
                onDelete: { state.delete(item) }
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if item.isVideo {
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .bold))
                        if item.duration > 0 {
                            Text(durationText(item.duration))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.62), in: Capsule())
                    .padding(6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(false)
            }

            if state.copiedID == item.id {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(0.48))
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Copied")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                    )
                    .allowsHitTesting(false)
            }

            if hovering && state.copiedID != item.id {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.55))
                    .font(.system(size: 16))
                    .padding(4)
                    .onTapGesture { state.delete(item) }
                    .help("Delete")
            }
        }
        .frame(width: 132, height: 88)
        .scaleEffect(hovering ? 1.03 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .help("Drag into any app · Click to copy")
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

struct DragSourceRepresentable: NSViewRepresentable {
    let url: URL
    let preview: NSImage
    let isVideo: Bool
    let onClick: () -> Void
    let onCopy: () -> Void
    let onReveal: () -> Void
    let onDelete: () -> Void

    func makeNSView(context: Context) -> FileDragView {
        let view = FileDragView()
        view.url = url
        view.preview = preview
        view.isVideo = isVideo
        view.onClick = onClick
        view.onCopy = onCopy
        view.onReveal = onReveal
        view.onDelete = onDelete
        return view
    }

    func updateNSView(_ view: FileDragView, context: Context) {
        view.url = url
        view.preview = preview
        view.isVideo = isVideo
        view.onClick = onClick
        view.onCopy = onCopy
        view.onReveal = onReveal
        view.onDelete = onDelete
    }
}

final class FileDragView: NSView, NSDraggingSource {
    var url: URL?
    var preview: NSImage?
    var isVideo = false
    var onClick: (() -> Void)?
    var onCopy: (() -> Void)?
    var onReveal: (() -> Void)?
    var onDelete: (() -> Void)?

    private var dragStarted = false
    private var mouseDownPoint: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        dragStarted = false
        mouseDownPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let mouseDownPoint, !dragStarted else { return }
        let delta = hypot(
            event.locationInWindow.x - mouseDownPoint.x,
            event.locationInWindow.y - mouseDownPoint.y
        )
        if delta > 5 {
            dragStarted = true
            beginDrag(event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !dragStarted {
            onClick?()
        }
        dragStarted = false
        mouseDownPoint = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copyItem), keyEquivalent: "")
        menu.addItem(withTitle: "Show in Finder", action: #selector(revealItem), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Delete", action: #selector(deleteItem), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func beginDrag(_ event: NSEvent) {
        guard let url else { return }
        let writer = ScreenshotPasteboardWriter(url: url, isVideo: isVideo)
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(bounds, contents: preview)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    @objc private func copyItem() { onCopy?() }
    @objc private func revealItem() { onReveal?() }
    @objc private func deleteItem() { onDelete?() }
}

final class ScreenshotPasteboardWriter: NSObject, NSPasteboardWriting {
    let url: URL
    let isVideo: Bool

    init(url: URL, isVideo: Bool) {
        self.url = url
        self.isVideo = isVideo
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        isVideo ? [.fileURL] : [.fileURL, .png]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .fileURL:
            return (url as NSURL).pasteboardPropertyList(forType: .fileURL)
        case .png:
            return try? Data(contentsOf: url)
        default:
            return nil
        }
    }
}
