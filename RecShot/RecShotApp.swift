import SwiftUI

@main
struct RecShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("RecShot", systemImage: "camera.viewfinder") {
            MenuBarView()
                .environmentObject(AppState.shared)
        }
    }
}
