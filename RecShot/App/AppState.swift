import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    static let onboardingKey = "hasSeenOnboarding"
    static let expandedKey = "stackExpanded"
    static let overlayLimit = 10

    @Published var items: [ScreenshotItem] = []
    @Published var isStackExpanded: Bool {
        didSet { UserDefaults.standard.set(isStackExpanded, forKey: Self.expandedKey) }
    }
    @Published var isCapturing = false
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var copiedID: String?
    @Published var showOnboarding = false

    let store = ScreenshotStore()
    private let capture = CaptureManager()
    private let recorder = ScreenRecorder()
    private var captureTask: Task<Void, Never>?
    private var recordingTask: Task<Void, Never>?
    private var recordingTimerTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private var copiedResetTask: Task<Void, Never>?

    private init() {
        isStackExpanded = UserDefaults.standard.bool(forKey: Self.expandedKey)
    }

    func start() {
        items = store.load()
        showOnboarding = !UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }

    func captureRegion() {
        guard captureTask == nil, recordingTask == nil, !isRecording else { return }
        captureTask = Task { [weak self] in
            defer { self?.captureTask = nil }
            await self?.runRegionCapture()
        }
    }

    func captureFullDisplay() {
        guard captureTask == nil, recordingTask == nil, !isRecording else { return }
        captureTask = Task { [weak self] in
            defer { self?.captureTask = nil }
            await self?.runFullDisplayCapture()
        }
    }

    func recordChoice() {
        if isRecording {
            stopRecording()
            return
        }
        guard captureTask == nil, recordingTask == nil else { return }

        let alert = NSAlert()
        alert.messageText = "Start a screen recording"
        alert.informativeText = "Choose what RecShot should record."
        alert.addButton(withTitle: "Application")
        alert.addButton(withTitle: "Full Display")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            recordApplication()
        case .alertSecondButtonReturn:
            recordFullDisplay()
        default:
            break
        }
    }

    func recordApplication() {
        guard captureTask == nil, recordingTask == nil, !isRecording else { return }
        recordingTask = Task { [weak self] in
            guard let self else { return }
            defer { recordingTask = nil }

            do {
                guard await capture.ensurePermission() else { return }
                let applications = try await recorder.availableApplications()
                guard let bundleIdentifier = chooseApplication(from: applications) else { return }
                try await recorder.startApplication(bundleIdentifier: bundleIdentifier)
                beginRecordingUI()
            } catch {
                presentError(error, title: "Couldn’t start recording")
            }
        }
    }

    func recordFullDisplay() {
        guard captureTask == nil, recordingTask == nil, !isRecording else { return }
        recordingTask = Task { [weak self] in
            guard let self else { return }
            defer { recordingTask = nil }

            do {
                guard await capture.ensurePermission() else { return }
                try await recorder.startFullDisplay()
                beginRecordingUI()
            } catch {
                presentError(error, title: "Couldn’t start recording")
            }
        }
    }

    func stopRecording() {
        guard isRecording, recordingTask == nil else { return }
        recordingTimerTask?.cancel()
        recordingTimerTask = nil
        recordingStartedAt = nil

        recordingTask = Task { [weak self] in
            guard let self else { return }
            defer { recordingTask = nil }

            do {
                let url = try await recorder.stop()
                isRecording = false
                addCapture(url)
            } catch {
                isRecording = false
                presentError(error, title: "Couldn’t finish recording")
            }
        }
    }

    var recordingDurationText: String {
        let totalSeconds = Int(recordingDuration)
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
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
        guard await capture.ensurePermission() else { return }

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
        guard await capture.ensurePermission() else { return }

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
    }

    private func beginRecordingUI() {
        isRecording = true
        recordingDuration = 0
        recordingStartedAt = Date()
        recordingTimerTask?.cancel()
        recordingTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self, let startedAt = self.recordingStartedAt else { return }
                self.recordingDuration = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func chooseApplication(from applications: [RecordingApplication]) -> String? {
        guard !applications.isEmpty else {
            presentError(RecordingError.applicationUnavailable, title: "No applications available")
            return nil
        }

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        popup.addItems(withTitles: applications.map(\.name))

        let alert = NSAlert()
        alert.messageText = "Choose an application to record"
        alert.accessoryView = popup
        alert.addButton(withTitle: "Record")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return applications[popup.indexOfSelectedItem].id
    }

    private func presentError(_ error: Error, title: String = "Couldn’t capture") {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
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
