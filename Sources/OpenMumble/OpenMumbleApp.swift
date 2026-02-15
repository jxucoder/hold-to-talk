import SwiftUI

@main
struct OpenMumbleApp: App {
    @StateObject private var engine = DictationEngine()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 4) {
                label
                Divider()

                if !engine.lastCleanText.isEmpty {
                    Text(engine.lastCleanText)
                        .lineLimit(3)
                        .font(.callout)
                        .padding(.vertical, 2)
                    Divider()
                }

                Button("Settings…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",")

                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(8)
            .frame(width: 260)
            .onAppear { engine.start() }
        } label: {
            Image(systemName: icon)
        }

        Window("OpenMumble Settings", id: "settings") {
            SettingsView(engine: engine)
        }
        .windowResizability(.contentSize)
    }

    private var label: some View {
        HStack {
            Circle()
                .fill(stateColor)
                .frame(width: 8, height: 8)
            Text(stateText)
                .font(.headline)
        }
    }

    private var stateText: String {
        switch engine.state {
        case .idle:         "Ready — hold [\(engine.hotkeyChoice)]"
        case .recording:    "Recording…"
        case .transcribing: "Transcribing…"
        case .cleaning:     "Cleaning up…"
        }
    }

    private var stateColor: Color {
        switch engine.state {
        case .idle:         .green
        case .recording:    .red
        case .transcribing: .orange
        case .cleaning:     .blue
        }
    }

    private var icon: String {
        engine.state == .recording ? "mic.fill" : "mic"
    }
}
