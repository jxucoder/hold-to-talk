import SwiftUI
import ApplicationServices

@main
struct OpenMumbleApp: App {
    @StateObject private var engine = DictationEngine()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 4) {
                Text("OpenMumble")
                    .font(.headline)
                    .padding(.bottom, 2)

                label

                if !engine.hasAccessibility {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Accessibility not granted")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    // Fix #20: DictationEngine already prompts for AX; just open Settings directly
                    Button("Grant Accessibility…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.caption)
                }
                Divider()

                if !engine.lastCleanText.isEmpty {
                    Text(engine.lastCleanText.prefix(80) + (engine.lastCleanText.count > 80 ? "…" : ""))
                        .lineLimit(2)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        } label: {
            Label("OpenMumble", systemImage: engine.state.icon)
        }

        Window("OpenMumble Settings", id: "settings") {
            SettingsView(engine: engine)
        }
        .windowResizability(.contentSize)
    }

    private var label: some View {
        Label(
            engine.state == .idle
                ? "Ready — hold [\(engine.hotkeyChoice)]"
                : engine.state.label,
            systemImage: engine.state.icon
        )
        .font(.headline)
    }

    /// Loads the app icon from the .app bundle or from the source tree for debug runs.
    static let appIcon: NSImage? = {
        if let bundled = Bundle.main.image(forResource: "OpenMumble") { return bundled }

        let sourceFile = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFile
            .deletingLastPathComponent()  // Sources/OpenMumble/
            .deletingLastPathComponent()  // Sources/
            .deletingLastPathComponent()  // project root
        let url = projectRoot.appendingPathComponent("Resources/OpenMumble.icns")
        if let img = NSImage(contentsOf: url), img.isValid { return img }
        return nil
    }()
}
