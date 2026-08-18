import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlay = OverlayPanelController.shared
    private var welcomePanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppState.shared.start()
        overlay.show()

        HotkeyManager.shared.onHotkey = {
            AppState.shared.captureRegion()
        }
        HotkeyManager.shared.register()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if AppState.shared.showOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showWelcome()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlay.show()
        return false
    }

    @objc private func screensChanged() {
        overlay.reposition()
    }

    private func showWelcome() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "RecShot"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let view = WelcomeView { [weak self] in
            UserDefaults.standard.set(true, forKey: AppState.onboardingKey)
            AppState.shared.showOnboarding = false
            self?.welcomePanel?.close()
            self?.welcomePanel = nil
        }
        let hosting = NSHostingView(rootView: view)
        if #available(macOS 13.0, *) {
            hosting.sizingOptions = [.intrinsicContentSize]
        }
        panel.contentView = hosting
        let size = hosting.fittingSize
        if size.width > 0, size.height > 0 {
            panel.setContentSize(size)
        }
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomePanel = panel
    }
}
