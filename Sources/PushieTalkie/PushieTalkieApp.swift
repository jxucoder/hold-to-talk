import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        truncateDebugLogIfNeeded()
        #if DEBUG
        if DebugFlags.resetOnboarding {
            UserDefaults.standard.set(false, forKey: "onboardingComplete")
            UserDefaults.standard.removeObject(forKey: "onboardingStep")
            UserDefaults.standard.removeObject(forKey: "hasPromptedInputMonitoring")
            print("[debug] Onboarding state reset.")
        }
        #endif
    }
}

@main
struct PushieTalkieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = DictationEngine()
    @Environment(\.openWindow) private var openWindow

    private var shouldShowOnboarding: Bool {
        #if DEBUG
        if DebugFlags.forceOnboarding { return true }
        #endif
        return !engine.onboardingComplete
    }

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 4) {
                Text("PushieTalkie")
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
                    Button("Grant Accessibility…") {
                        openSystemSettings("Privacy_Accessibility")
                    }
                    .font(.caption)
                }
                Divider()

                if let error = engine.lastError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 2)
                    Divider()
                }

                if !engine.lastCleanText.isEmpty {
                    Text(engine.lastCleanText.prefix(80) + (engine.lastCleanText.count > 80 ? "…" : ""))
                        .lineLimit(2)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                    Button("Copy Last Transcription") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(engine.lastCleanText, forType: .string)
                    }
                    .font(.caption)
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
            Label("PushieTalkie", systemImage: engine.state.icon)
        }

        Window("Welcome to PushieTalkie", id: "onboarding") {
            OnboardingView(engine: engine, modelManager: engine.modelManager)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(shouldShowOnboarding ? .presented : .suppressed)

        Window("PushieTalkie Settings", id: "settings") {
            SettingsView(engine: engine, modelManager: engine.modelManager)
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
        if let bundled = Bundle.main.image(forResource: "PushieTalkie") { return bundled }

        let sourceFile = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFile
            .deletingLastPathComponent()  // Sources/PushieTalkie/
            .deletingLastPathComponent()  // Sources/
            .deletingLastPathComponent()  // project root
        let url = projectRoot.appendingPathComponent("Resources/PushieTalkie.icns")
        if let img = NSImage(contentsOf: url), img.isValid { return img }
        return nil
    }()
}
