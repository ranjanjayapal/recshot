import AppKit

enum AnnotationTool: Equatable {
    case pen
    case arrow
    case rectangle
    case ellipse
    case highlight
    case text
}

struct Annotation {
    var tool: AnnotationTool
    var color: NSColor
    var lineWidth: CGFloat
    var points: [CGPoint] = []
    var start: CGPoint = .zero
    var end: CGPoint = .zero
    var text: String = ""
    var fontSize: CGFloat = 24
}

final class AnnotationCanvas: NSView, NSTextFieldDelegate {
    var image = NSImage() {
        didSet { needsDisplay = true }
    }
    var tool: AnnotationTool = .pen {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var color: NSColor = .systemRed
    var isEditing = false {
        didSet {
            if !isEditing { commitTextIfNeeded() }
            window?.invalidateCursorRects(for: self)
        }
    }
    var onChange: (() -> Void)?

    private var annotations: [Annotation] = []
    private var inProgress: Annotation?
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero

    var hasChanges: Bool { !annotations.isEmpty }
    var canUndo: Bool { !annotations.isEmpty || inProgress != nil }

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func resetCursorRects() {
        guard isEditing else {
            addCursorRect(bounds, cursor: .arrow)
            return
        }
        addCursorRect(bounds, cursor: tool == .text ? .iBeam : .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = fittedImageRect
        guard rect.width > 0, rect.height > 0 else { return }

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: rect, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1)
        NSColor.white.withAlphaComponent(0.22).setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()

        let scale = rect.width / max(image.size.width, 1)
        for annotation in annotations {
            draw(annotation, scale: scale)
        }
        if let inProgress {
            draw(inProgress, scale: scale)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditing else { return }
        window?.makeFirstResponder(self)
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard fittedImageRect.contains(viewPoint) else {
            commitTextIfNeeded()
            return
        }
        let imagePoint = imagePoint(from: viewPoint)

        if tool == .text {
            commitTextIfNeeded()
            beginText(at: imagePoint, viewPoint: viewPoint)
            return
        }

        commitTextIfNeeded()
        var annotation = Annotation(tool: tool, color: color, lineWidth: strokeWidth)
        annotation.points = [imagePoint]
        annotation.start = imagePoint
        annotation.end = imagePoint
        inProgress = annotation
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing, var current = inProgress else { return }
        var imagePoint = imagePoint(from: convert(event.locationInWindow, from: nil))
        imagePoint = constrain(imagePoint, from: current.start, event: event)
        if current.tool == .pen {
            current.points.append(imagePoint)
        }
        current.end = imagePoint
        inProgress = current
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command),
           !flags.contains(.shift),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            undo()
            return
        }
        super.keyDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEditing, let current = inProgress else { return }
        inProgress = nil
        let distance = hypot(current.end.x - current.start.x, current.end.y - current.start.y)
        let trivial = current.tool == .pen
            ? (distance < 2 && current.points.count < 3)
            : distance < 2
        if !trivial {
            annotations.append(current)
            onChange?()
        }
        needsDisplay = true
    }

    func undo() {
        commitTextIfNeeded()
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        onChange?()
        needsDisplay = true
    }

    func commitTextIfNeeded() {
        guard let textField else { return }
        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        textField.removeFromSuperview()
        self.textField = nil
        if !value.isEmpty {
            var annotation = Annotation(tool: .text, color: color, lineWidth: strokeWidth)
            annotation.start = textOrigin
            annotation.text = value
            annotation.fontSize = fontSize
            annotations.append(annotation)
            onChange?()
        }
        needsDisplay = true
    }

    func flattenedCGImage() -> CGImage? {
        commitTextIfNeeded()
        guard let source = cgImage(from: image) else { return nil }

        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: source.width,
            pixelsHigh: source.height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )
        guard let rep else { return nil }
        rep.size = image.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: image.size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        for annotation in annotations {
            draw(annotation, scale: 1, inImageSpace: true)
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
    }

    private var strokeWidth: CGFloat {
        max(3, min(image.size.width, image.size.height) * 0.007)
    }

    private var fontSize: CGFloat {
        max(16, min(image.size.width, image.size.height) * 0.038)
    }

    private var fittedImageRect: CGRect {
        let available = bounds
        let size = image.size
        guard size.width > 0, size.height > 0, available.width > 0, available.height > 0 else { return .zero }
        let scale = min(available.width / size.width, available.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: available.midX - fitted.width / 2,
            y: available.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    private func imagePoint(from viewPoint: CGPoint) -> CGPoint {
        let rect = fittedImageRect
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(
            x: (viewPoint.x - rect.minX) / rect.width * image.size.width,
            y: (viewPoint.y - rect.minY) / rect.height * image.size.height
        )
    }

    private func viewPoint(from imagePoint: CGPoint) -> CGPoint {
        let rect = fittedImageRect
        return CGPoint(
            x: rect.minX + imagePoint.x / max(image.size.width, 1) * rect.width,
            y: rect.minY + imagePoint.y / max(image.size.height, 1) * rect.height
        )
    }

    private func constrain(_ point: CGPoint, from start: CGPoint, event: NSEvent) -> CGPoint {
        guard event.modifierFlags.contains(.shift) else { return point }
        if tool == .arrow || tool == .pen {
            let dx = point.x - start.x
            let dy = point.y - start.y
            let angle = atan2(dy, dx)
            let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + length * cos(snapped), y: start.y + length * sin(snapped))
        }
        let dx = point.x - start.x
        let dy = point.y - start.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(
            x: start.x + side * (dx < 0 ? -1 : 1),
            y: start.y + side * (dy < 0 ? -1 : 1)
        )
    }

    private func beginText(at imagePoint: CGPoint, viewPoint: CGPoint) {
        textOrigin = imagePoint
        let scale = fittedImageRect.width / max(image.size.width, 1)
        let field = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y - fontSize * scale, width: 240, height: fontSize * scale + 8))
        field.font = .systemFont(ofSize: max(12, fontSize * scale), weight: .bold)
        field.textColor = color
        field.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        field.drawsBackground = true
        field.isBezeled = false
        field.isBordered = false
        field.focusRingType = .none
        field.delegate = self
        field.placeholderString = "Type"
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:))
            || commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            commitTextIfNeeded()
            return true
        }
        return false
    }

    private func draw(_ annotation: Annotation, scale: CGFloat, inImageSpace: Bool = false) {
        let mapped: (CGPoint) -> CGPoint = { point in
            inImageSpace ? point : self.viewPoint(from: point)
        }
        let width = annotation.lineWidth * scale
        annotation.color.set()

        switch annotation.tool {
        case .pen:
            let path = NSBezierPath()
            path.lineWidth = width
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let points = annotation.points.map(mapped)
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.line(to: point)
            }
            path.stroke()

        case .arrow:
            drawArrow(from: mapped(annotation.start), to: mapped(annotation.end), width: width)

        case .rectangle, .ellipse, .highlight:
            let a = mapped(annotation.start)
            let b = mapped(annotation.end)
            let rect = CGRect(
                x: min(a.x, b.x),
                y: min(a.y, b.y),
                width: max(abs(b.x - a.x), 1),
                height: max(abs(b.y - a.y), 1)
            )
            let path = annotation.tool == .ellipse
                ? NSBezierPath(ovalIn: rect)
                : NSBezierPath(rect: rect)
            if annotation.tool == .highlight {
                annotation.color.withAlphaComponent(0.32).setFill()
                path.fill()
            } else {
                path.lineWidth = width
                path.lineJoinStyle = .round
                path.stroke()
            }

        case .text:
            let origin = mapped(annotation.start)
            let font = NSFont.systemFont(ofSize: annotation.fontSize * scale, weight: .bold)
            let halo: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black.withAlphaComponent(0.55)
            ]
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: annotation.color
            ]
            let string = annotation.text as NSString
            for dx in [-1.0, 0.0, 1.0] {
                for dy in [-1.0, 0.0, 1.0] where dx != 0 || dy != 0 {
                    string.draw(at: CGPoint(x: origin.x + dx, y: origin.y + dy), withAttributes: halo)
                }
            }
            string.draw(at: origin, withAttributes: attrs)
        }
    }

    private func drawArrow(from: CGPoint, to: CGPoint, width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: from)
        path.line(to: to)
        path.lineWidth = width
        path.lineCapStyle = .round
        path.stroke()

        let angle = atan2(to.y - from.y, to.x - from.x)
        let head = max(11, width * 3.6)
        let headAngle: CGFloat = .pi / 7
        let headPath = NSBezierPath()
        headPath.move(to: to)
        headPath.line(to: CGPoint(
            x: to.x - head * cos(angle - headAngle),
            y: to.y - head * sin(angle - headAngle)
        ))
        headPath.line(to: CGPoint(
            x: to.x - head * cos(angle + headAngle),
            y: to.y - head * sin(angle + headAngle)
        ))
        headPath.close()
        headPath.fill()
    }

    private func cgImage(from image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        if let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return cg
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.cgImage
    }
}
