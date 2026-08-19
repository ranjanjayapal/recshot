import SwiftUI

struct WelcomeView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.recCoral)
                Text("RecShot")
                    .font(.system(size: 26, weight: .bold))
            }

            Text("Screenshots stack in the bottom-left corner. Click the toggle to fan them out, then drag any thumbnail into another app.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                Label("⌥⌘S captures a region", systemImage: "viewfinder")
                Label("⌥⌘R records an app or full display", systemImage: "record.circle")
                Label("Click the corner toggle to show the stack", systemImage: "square.stack")
                Label("Drag a thumbnail into Slack, Notes, Figma…", systemImage: "hand.draw")
            }
            .font(.system(size: 13, weight: .medium))

            Text("macOS will ask for Screen & System Audio Recording permission on the first capture. Quit and reopen RecShot after enabling it.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Got it") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

extension Color {
    static let recCoral = Color(red: 1.0, green: 0.42, blue: 0.28)
}
