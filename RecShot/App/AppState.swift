import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    static let onboardingKey = "hasSeenOnboarding"
    static let expandedKey = "stackExpanded"

    @Published var items: [ScreenshotItem] = []
    @Published var isStackExpanded: Bool {
        didSet { UserDefaults.standard.set(isStackExpanded, forKey: Self.expandedKey) }
    }
    @Published var isCapturing = false
    @Published var copiedID: String?
    @Published var showOnboarding = false

    let store = ScreenshotStore()
    private let capture = CaptureManager()
    private var captureTask: Task<Void, Never>?
    private var copiedResetTask: Task<Void, Never>?

    private init() {
        isStackExpanded = UserDefaults.standard.bool(forKey: Self.expandedKey)
    }

    func start() {
        items = store.load()
        showOnboarding = !UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }

    func captureRegion() {
        guard captureTask == nil else { return }
        captureTask = Task { [weak self] in
            defer { self?.captureTask = nil }
            await self?.runRegionCapture()
        }
    }

    func captureFullDisplay() {
        guard captureTask == nil else { return }
        captureTask = Task { [weak self] in
            defer { self?.captureTask = nil }
            await self?.runFullDisplayCapture()
        }
    }

    func toggleStack() {
        isStackExpanded.toggle()
    }

    func copy(_ item: ScreenshotItem) {
        store.copyToClipboard(item)
        copiedID = item.id
        copiedResetTask?.cancel()
        copiedResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if self?.copiedID == item.id {
                self?.copiedID = nil
            }
        }
    }

    func reveal(_ item: ScreenshotItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func delete(_ item: ScreenshotItem) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            items.removeAll { $0.id == item.id }
        }
        store.delete(item)
    }

    func clearAll() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            items.removeAll()
        }
        store.clearAll()
    }

    private func runRegionCapture() async {
        guard capture.ensurePermission() else { return }

        let previousApp = NSWorkspace.shared.frontmostApplication
        isCapturing = true

        let selection = await RegionSelectionController.shared.select()
        guard let selection else {
            isCapturing = false
            previousApp?.activate()
            return
        }

        try? await Task.sleep(nanoseconds: 120_000_000)

        do {
            let url = try await capture.capture(rectInScreen: selection.rect, screen: selection.screen)
            addCapture(url)
        } catch {
            presentError(error)
        }

        isCapturing = false
        previousApp?.activate()
    }

    private func runFullDisplayCapture() async {
        guard capture.ensurePermission() else { return }

        isCapturing = true
        try? await Task.sleep(nanoseconds: 120_000_000)

        let screen = NSScreen.screenUnderMouse()
        do {
            let url = try await capture.captureFullDisplay(screen)
            addCapture(url)
        } catch {
            presentError(error)
        }

        isCapturing = false
    }

    private func addCapture(_ url: URL) {
        guard let item = store.makeItem(url: url) else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            items.insert(item, at: 0)
            isStackExpanded = true
        }
        store.trim(&items)
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn’t capture screenshot"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    static func screenUnderMouse() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
