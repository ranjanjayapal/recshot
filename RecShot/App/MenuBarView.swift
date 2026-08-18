import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Button("Capture Region") {
            state.captureRegion()
        }
        .keyboardShortcut("s", modifiers: [.command, .option])

        Button("Capture Full Display") {
            state.captureFullDisplay()
        }

        Divider()

        Button(state.isStackExpanded ? "Collapse Stack" : "Expand Stack") {
            state.toggleStack()
        }
        .disabled(state.items.isEmpty)

        Button("Clear All", role: .destructive) {
            state.clearAll()
        }
        .disabled(state.items.isEmpty)

        Divider()

        Button("Quit RecShot") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
