import AppKit
import UniformTypeIdentifiers

struct ScreenshotItem: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
    let createdAt: Date
    let thumbnail: NSImage

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.url == rhs.url
    }
}

final class ScreenshotStore {
    static let keepLimit = 50

    var capturesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("RecShot/captures", isDirectory: true)
    }

    func load() -> [ScreenshotItem] {
        ensureDirectory()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: capturesDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let pngs = urls
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { a, b in
                createdAt(a) > createdAt(b)
            }

        var items = pngs.compactMap(makeItem)
        trim(&items)
        return items
    }

    func save(_ image: CGImage) throws -> URL {
        ensureDirectory()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        var name = "RecShot-\(formatter.string(from: Date())).png"
        var url = capturesDirectory.appendingPathComponent(name)
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            name = "RecShot-\(formatter.string(from: Date()))-\(suffix).png"
            url = capturesDirectory.appendingPathComponent(name)
            suffix += 1
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CaptureError.failedToSave
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureError.failedToSave
        }
        return url
    }

    func makeItem(url: URL) -> ScreenshotItem? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return ScreenshotItem(
            url: url,
            createdAt: createdAt(url),
            thumbnail: Self.thumbnail(from: image)
        )
    }

    func copyToClipboard(_ item: ScreenshotItem) {
        guard let image = NSImage(contentsOf: item.url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image, item.url as NSURL])
    }

    func delete(_ item: ScreenshotItem) {
        try? FileManager.default.removeItem(at: item.url)
    }

    func clearAll() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: capturesDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in urls where url.pathExtension.lowercased() == "png" {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func trim(_ items: inout [ScreenshotItem]) {
        guard items.count > Self.keepLimit else { return }
        let extra = items.suffix(from: Self.keepLimit)
        for item in extra {
            try? FileManager.default.removeItem(at: item.url)
        }
        items = Array(items.prefix(Self.keepLimit))
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
    }

    private func createdAt(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    private static func thumbnail(from image: NSImage) -> NSImage {
        let maxDimension: CGFloat = 400
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1)
        let newSize = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let thumb = NSImage(size: newSize)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1
        )
        thumb.unlockFocus()
        return thumb
    }
}
