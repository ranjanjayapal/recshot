import AppKit
import AVFoundation
import UniformTypeIdentifiers

enum CaptureKind: Equatable {
    case screenshot
    case recording
}

struct ScreenshotItem: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
    let createdAt: Date
    let modifiedAt: Date
    let thumbnail: NSImage
    let kind: CaptureKind
    let duration: TimeInterval

    var isVideo: Bool { kind == .recording }

    static func == (lhs: ScreenshotItem, rhs: ScreenshotItem) -> Bool {
        lhs.url == rhs.url && lhs.modifiedAt == rhs.modifiedAt
    }
}

final class ScreenshotStore {
    static let overlayThumbnailLimit = 10

    var capturesDirectory: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Pictures", isDirectory: true)
        return pictures.appendingPathComponent("RecShot", isDirectory: true)
    }

    func load() -> [ScreenshotItem] {
        ensureDirectory()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: capturesDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let captures = urls
            .filter(isCaptureURL)
            .sorted { a, b in
                createdAt(a) > createdAt(b)
            }

        return captures.enumerated().compactMap { index, url in
            makeItem(url: url, includeThumbnail: index < Self.overlayThumbnailLimit)
        }
    }

    func save(_ image: CGImage) throws -> URL {
        ensureDirectory()
        let url = uniqueURL(fileExtension: "png")

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

    func recordingURL() -> URL {
        ensureDirectory()
        return uniqueURL(fileExtension: "mp4")
    }

    func makeItem(url: URL, includeThumbnail: Bool = true) -> ScreenshotItem? {
        let kind: CaptureKind
        let thumbnail: NSImage
        let duration: TimeInterval

        switch url.pathExtension.lowercased() {
        case "png":
            guard let image = Self.image(from: url) else { return nil }
            kind = .screenshot
            thumbnail = Self.thumbnail(from: image)
            duration = 0
        case "mov", "mp4":
            kind = .recording
            thumbnail = includeThumbnail
                ? Self.videoThumbnail(from: url)
                : Self.videoPlaceholder
            let seconds = AVPlayerItem(url: url).duration.seconds
            duration = seconds.isFinite ? max(0, seconds) : 0
        default:
            return nil
        }

        return ScreenshotItem(
            url: url,
            createdAt: createdAt(url),
            modifiedAt: modifiedAt(url),
            thumbnail: thumbnail,
            kind: kind,
            duration: duration
        )
    }

    func copyToClipboard(_ item: ScreenshotItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if item.isVideo {
            pasteboard.writeObjects([item.url as NSURL])
        } else if let image = Self.image(from: item.url) {
            pasteboard.writeObjects([image, item.url as NSURL])
        }
    }

    func delete(_ item: ScreenshotItem) {
        try? FileManager.default.removeItem(at: item.url)
    }

    func clearAll() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: capturesDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in urls where isCaptureURL(url) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)

        let legacyDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("RecShot/captures", isDirectory: true)
        guard let legacyDirectory, legacyDirectory != capturesDirectory else { return }
        let legacyURLs = (try? FileManager.default.contentsOfDirectory(
            at: legacyDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        for source in legacyURLs where isCaptureURL(source) {
            let destination = capturesDirectory.appendingPathComponent(source.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try? FileManager.default.moveItem(at: source, to: destination)
        }
    }

    private func uniqueURL(fileExtension: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let baseName = "RecShot-\(formatter.string(from: Date()))"
        var url = capturesDirectory.appendingPathComponent("\(baseName).\(fileExtension)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = capturesDirectory.appendingPathComponent("\(baseName)-\(suffix).\(fileExtension)")
            suffix += 1
        }
        return url
    }

    private func isCaptureURL(_ url: URL) -> Bool {
        ["png", "mov", "mp4"].contains(url.pathExtension.lowercased())
    }

    private func createdAt(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    private func modifiedAt(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? createdAt(url)
    }

    private static func image(from url: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return NSImage(data: data)
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

    private static func videoThumbnail(from url: URL) -> NSImage {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let candidateTimes = [
            CMTime.zero,
            CMTime(value: 1, timescale: 30),
            CMTime(value: 1, timescale: 10)
        ]
        for time in candidateTimes {
            if let image = try? generator.copyCGImage(at: time, actualTime: nil) {
                return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }
        return videoPlaceholder
    }

    private static var videoPlaceholder: NSImage {
        NSImage(systemSymbolName: "video.fill", accessibilityDescription: "Recording")
            ?? NSImage(size: NSSize(width: 400, height: 225))
    }
}
