import AppKit
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case permissionDenied
    case noDisplay
    case failedToSave
    case tooSmall

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required. Enable it in System Settings › Privacy & Security › Screen Recording."
        case .noDisplay:
            return "Couldn’t find the display to capture."
        case .failedToSave:
            return "Couldn’t save the screenshot file."
        case .tooSmall:
            return "The selected region was too small."
        }
    }
}

final class CaptureManager {
    func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        CGRequestScreenCaptureAccess()
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "RecShot needs Screen Recording access to take screenshots. Enable RecShot in System Settings › Privacy & Security › Screen Recording, then capture again."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            let urls = [
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension"
            ]
            for string in urls {
                if let url = URL(string: string), NSWorkspace.shared.open(url) {
                    break
                }
            }
        }
        return false
    }

    func captureFullDisplay(_ screen: NSScreen) async throws -> URL {
        let rect = CGRect(origin: .zero, size: screen.frame.size)
        return try await capture(rectInScreen: rect, screen: screen)
    }

    /// `rectInScreen` is in that screen's local Cocoa coordinates (origin at bottom-left of the screen).
    func capture(rectInScreen: CGRect, screen: NSScreen) async throws -> URL {
        guard rectInScreen.width >= 8, rectInScreen.height >= 8 else {
            throw CaptureError.tooSmall
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID })
                ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let scale = screen.backingScaleFactor
        let sourceRect = CGRect(
            x: rectInScreen.origin.x,
            y: screen.frame.height - rectInScreen.maxY,
            width: rectInScreen.width,
            height: rectInScreen.height
        )

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = evenPixel(sourceRect.width * scale)
        config.height = evenPixel(sourceRect.height * scale)
        config.showsCursor = false
        config.scalesToFit = false
        if #available(macOS 15.0, *) {
            config.captureResolution = .best
        }

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return try ScreenshotStore().save(image)
    }

    private func evenPixel(_ value: CGFloat) -> Int {
        max(2, Int(value.rounded()) & ~1)
    }
}
