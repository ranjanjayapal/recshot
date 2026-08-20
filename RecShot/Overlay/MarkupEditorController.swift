import AppKit
import SwiftUI

@MainActor
final class MarkupEditorController: NSObject, NSWindowDelegate {
    static let shared = MarkupEditorController()

    private var panel: NSPanel?
    private var session: MarkupSession?

    func present(_ item: ScreenshotItem) {
        close()

        guard let image = NSImage(contentsOf: item.url), image.size.width > 0, image.size.height > 0 else {
            NSWorkspace.shared.open(item.url)
            return
        }

        let session = MarkupSession(item: item, image: image) { [weak self] in
            self?.close()
        }
        self.session = session

        let screen = NSScreen.screenUnderMouse()
        let visible = screen.visibleFrame
        let toolbar: CGFloat = 54
        let padding: CGFloat = 18
        let maxSize = CGSize(
            width: max(360, visible.width * 0.78),
            height: max(240, visible.height * 0.78 - toolbar)
        )
        let scale = min(1, maxSize.width / image.size.width, maxSize.height / image.size.height)
        let imageSize = NSSize(
            width: max(280, image.size.width * scale),
            height: max(160, image.size.height * scale)
        )
        let windowSize = NSSize(
            width: max(540, imageSize.width + padding * 2),
            height: max(280, imageSize.height + padding * 2 + toolbar)
        )

        let panel = MarkupPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Screenshot"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 540, height: 280)
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let hosting = NSHostingView(rootView: MarkupEditorView(session: session))
        hosting.frame = NSRect(origin: .zero, size: windowSize)
        panel.contentView = hosting
        panel.setContentSize(windowSize)
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func windowWillClose(_ notification: Notification) {
        session?.canvas.commitTextIfNeeded()
        session = nil
        panel = nil
    }

    private func close() {
        panel?.delegate = nil
        panel?.close()
        panel = nil
        session = nil
    }
}

final class MarkupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

@MainActor
final class MarkupSession: ObservableObject {
    let item: ScreenshotItem
    let image: NSImage
    let canvas = AnnotationCanvas()
    let onClose: () -> Void

    @Published var isEditing = false {
        didSet { canvas.isEditing = isEditing }
    }
    @Published var tool: AnnotationTool = .pen {
        didSet { canvas.tool = tool }
    }
    @Published var colorIndex = 0 {
        didSet { canvas.color = Self.palette[colorIndex] }
    }
    @Published var canUndo = false

    static let palette: [NSColor] = [
        .systemRed,
        NSColor(calibratedRed: 1, green: 0.42, blue: 0.28, alpha: 1),
        .systemOrange,
        .systemYellow,
        .systemGreen,
        .systemBlue,
        .white,
        .black
    ]

    init(item: ScreenshotItem, image: NSImage, onClose: @escaping () -> Void) {
        self.item = item
        self.image = image
        self.onClose = onClose
        canvas.image = image
        canvas.tool = tool
        canvas.color = Self.palette[colorIndex]
        canvas.isEditing = false
        canvas.onChange = { [weak self] in
            self?.canUndo = self?.canvas.canUndo ?? false
        }
    }

    func undo() {
        canvas.undo()
        canUndo = canvas.canUndo
    }

    func done() {
        canvas.commitTextIfNeeded()
        if canvas.hasChanges {
            guard let image = canvas.flattenedCGImage() else {
                AppState.shared.presentSaveError()
                return
            }
            guard AppState.shared.saveEdits(image, replacing: item) else { return }
        }
        onClose()
    }
}

struct MarkupEditorView: View {
    @ObservedObject var session: MarkupSession

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.top, 34)
                .padding(.bottom, 8)

            AnnotationCanvasHost(canvas: session.canvas)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ultraThinMaterial)
        .onAppear {
            session.canvas.window?.makeFirstResponder(session.canvas)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if session.isEditing {
                toolGroup
                colorGroup
                Button(action: session.undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .disabled(!session.canUndo)
                .help("Undo")
            } else {
                Button(action: { session.isEditing = true }) {
                    Label("Edit", systemImage: "pencil.tip.crop.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.recCoral.opacity(0.16), in: Capsule())
                        .foregroundStyle(Color.recCoral)
                }
                .buttonStyle(.plain)
                .help("Markup this screenshot")
            }

            Spacer()

            Button("Done", action: session.done)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.recCoral, in: Capsule())
                .buttonStyle(.plain)
                .help("Save and close")
        }
    }

    private var toolGroup: some View {
        HStack(spacing: 2) {
            toolButton(.pen, "pencil.tip", "Draw")
            toolButton(.arrow, "arrow.up.right", "Arrow")
            toolButton(.rectangle, "rectangle", "Rectangle")
            toolButton(.ellipse, "oval", "Ellipse")
            toolButton(.highlight, "highlighter", "Highlight")
            toolButton(.text, "textformat", "Text")
        }
        .padding(3)
        .background(.black.opacity(0.18), in: Capsule())
    }

    private var colorGroup: some View {
        HStack(spacing: 6) {
            ForEach(MarkupSession.palette.indices, id: \.self) { index in
                Circle()
                    .fill(Color(nsColor: MarkupSession.palette[index]))
                    .frame(width: 13, height: 13)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(session.colorIndex == index ? 0.95 : 0.35), lineWidth: session.colorIndex == index ? 2 : 0.6)
                    )
                    .onTapGesture { session.colorIndex = index }
            }
        }
        .padding(.horizontal, 6)
    }

    private func toolButton(_ tool: AnnotationTool, _ systemImage: String, _ help: String) -> some View {
        let selected = session.tool == tool
        return Button {
            session.tool = tool
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.recCoral : .primary)
                .frame(width: 26, height: 26)
                .background(selected ? Color.recCoral.opacity(0.18) : .clear, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private final class CanvasContainer: NSView {
    override func layout() {
        super.layout()
        subviews.first?.frame = bounds
    }
}

private struct AnnotationCanvasHost: NSViewRepresentable {
    let canvas: AnnotationCanvas

    func makeNSView(context: Context) -> NSView {
        let container = CanvasContainer()
        canvas.autoresizingMask = [.width, .height]
        container.addSubview(canvas)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if canvas.superview !== nsView {
            canvas.removeFromSuperview()
            nsView.addSubview(canvas)
        }
        canvas.frame = nsView.bounds
    }
}
