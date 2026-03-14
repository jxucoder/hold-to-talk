import SwiftUI
import AVFoundation
#if canImport(Sparkle)
import Sparkle
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    var openOnboardingHandler: (() -> Void)?
    private var pendingInitialOnboardingOpen = false
    private var hasOpenedInitialOnboarding = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isDiagnosticLoggingEnabled() {
            truncateDebugLogIfNeeded()
        } else {
            clearDebugLog()
        }

        if shouldOpenInitialOnboarding {
            pendingInitialOnboardingOpen = true
            flushPendingInitialOnboardingOpen()
        }

        if !isInstalledInApplicationsFolder() && !UserDefaults.standard.bool(forKey: dismissedInstallPromptDefaultsKey) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Task { @MainActor in
                    self.showInstallPrompt()
                }
            }
        }
    }

    @MainActor
    private func showInstallPrompt() {
        NSApp.activate(ignoringOtherApps: true)
        let compatibility = SystemCompatibility.current()
        let alert = makeInstallAlert(icon: HoldToTalkApp.appIcon, compatibility: compatibility)
        alert.showsSuppressionButton = compatibility.isSupported
        alert.suppressionButton?.title = "Don't ask again"

        let response = alert.runModal()

        if compatibility.isSupported, alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: dismissedInstallPromptDefaultsKey)
        }

        guard compatibility.isSupported else { return }

        if response == .alertFirstButtonReturn {
            switch installToApplicationsAndRelaunch() {
            case .success:
                break
            case .failure(let message):
                let errorAlert = NSAlert()
                errorAlert.messageText = "Could Not Move App"
                errorAlert.informativeText = message
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
            }
        }
    }

    func setOpenOnboardingHandler(_ handler: @escaping () -> Void) {
        openOnboardingHandler = handler
        flushPendingInitialOnboardingOpen()
    }

    private var shouldOpenInitialOnboarding: Bool {
        #if DEBUG
        if DebugFlags.forceOnboarding { return true }
        #endif
        return !UserDefaults.standard.bool(forKey: onboardingCompleteDefaultsKey)
    }

    private func flushPendingInitialOnboardingOpen() {
        guard pendingInitialOnboardingOpen,
              !hasOpenedInitialOnboarding,
              let openOnboardingHandler else { return }
        pendingInitialOnboardingOpen = false
        hasOpenedInitialOnboarding = true
        DispatchQueue.main.async {
            openOnboardingHandler()
        }
    }
}

@main
struct HoldToTalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine: DictationEngine
    @State private var hasPreparedFreshOnboardingSession: Bool
    @Environment(\.openWindow) private var openWindow
    #if canImport(Sparkle)
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    #endif

    init() {
        let shouldReset = shouldResetAppStateForFreshOnboarding()
        if shouldReset {
            resetPersistedAppStateForFreshOnboarding()
        }
        _engine = StateObject(wrappedValue: DictationEngine())
        _hasPreparedFreshOnboardingSession = State(initialValue: shouldReset)
    }

    private var shouldShowOnboarding: Bool {
        #if DEBUG
        if DebugFlags.forceOnboarding { return true }
        #endif
        return !engine.onboardingComplete
    }

    private var hotkeyDisplayName: String {
        HotkeyManager.Hotkey.preferredSelection(from: engine.hotkeyChoice).displayName
    }

    private var appUpdater: (any AppUpdateDriver)? {
        #if canImport(Sparkle)
        return SparkleUpdateDriver(updater: updaterController.updater)
        #else
        return nil
        #endif
    }

    var body: some Scene {
        let _ = configureAppDelegate()

        MenuBarExtra {
            if shouldShowOnboarding {
                onboardingMenu
            } else {
                mainMenu
            }
        } label: {
            Label("Hold to Talk", systemImage: engine.state.icon)
        }

        Window("Welcome to Hold to Talk", id: "onboarding") {
            OnboardingView(engine: engine, modelManager: engine.modelManager)
                .background(OnboardingWindowConfigurator(isBlocking: shouldShowOnboarding))
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.suppressed)

        Window("Hold to Talk Settings", id: "settings") {
            SettingsView(engine: engine, modelManager: engine.modelManager, updater: appUpdater)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }

    private var label: some View {
        Label(
            engine.state == .idle
                ? "Ready - hold [\(hotkeyDisplayName)]"
                : engine.state.label,
            systemImage: engine.state.icon
        )
        .font(.headline)
    }

    private var onboardingMenu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hold to Talk")
                .font(.headline)

            Text("Finish onboarding to enable dictation.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Open Onboarding…") {
                openOnboardingWindow()
            }
            .font(.caption)

            Divider()

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(8)
        .frame(width: 220)
    }

    private var mainMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hold to Talk")
                .font(.headline)
                .padding(.bottom, 2)

            label

            if !isInstalledInApplicationsFolder() {
                Button {
                    showInstallAlert()
                } label: {
                    Label("Move to Applications…", systemImage: "arrow.down.app.fill")
                }
                .font(.caption)
                Divider()
            }

            if !engine.hasMicrophone || !engine.hasPostEvent || !engine.hasInputMonitoring {
                VStack(alignment: .leading, spacing: 4) {
                    if !engine.hasMicrophone {
                        permissionWarningRow("Microphone not granted")
                        Button("Grant Microphone…") {
                            AVCaptureDevice.requestAccess(for: .audio) { _ in
                                Task { @MainActor in
                                    openSystemSettings("Privacy_Microphone")
                                }
                            }
                        }
                        .font(.caption)
                    }

                    if !engine.hasPostEvent {
                        permissionWarningRow("Keyboard Access not granted")
                        Button("Grant Keyboard Access…") {
                            _ = requestPostEventAccess()
                        }
                        .font(.caption)
                    }

                    if !engine.hasInputMonitoring {
                        permissionWarningRow("Input Monitoring not granted")
                        Button("Grant Input Monitoring…") {
                            _ = requestInputMonitoringAccess()
                        }
                        .font(.caption)
                    }

                    Button("Open Onboarding…") {
                        openOnboardingWindow()
                    }
                    .font(.caption)
                }
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
        .frame(width: 220)
    }

    private func permissionWarningRow(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(text)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @MainActor
    private func showInstallAlert() {
        let compatibility = SystemCompatibility.current()
        let alert = makeInstallAlert(icon: Self.appIcon, compatibility: compatibility)

        let response = alert.runModal()
        guard compatibility.isSupported else { return }

        if response == .alertFirstButtonReturn {
            switch installToApplicationsAndRelaunch() {
            case .success:
                break
            case .failure(let message):
                let errorAlert = NSAlert()
                errorAlert.messageText = "Could Not Move App"
                errorAlert.informativeText = message
                errorAlert.alertStyle = .warning
                errorAlert.runModal()
            }
        }
    }

    @MainActor
    private func openOnboardingWindow() {
        prepareFreshOnboardingIfNeeded()
        openWindow(id: "onboarding")
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func prepareFreshOnboardingIfNeeded() {
        guard !engine.onboardingComplete, !hasPreparedFreshOnboardingSession else { return }
        engine.resetForFreshOnboarding()
        hasPreparedFreshOnboardingSession = true
    }

    private func configureAppDelegate() {
        appDelegate.setOpenOnboardingHandler {
            openOnboardingWindow()
        }
    }

    /// Loads the app icon from the .app bundle or from the source tree for debug runs.
    static let appIcon: NSImage? = {
        if let bundled = Bundle.main.image(forResource: "HoldToTalk") { return bundled }

        let sourceFile = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFile
            .deletingLastPathComponent()  // Sources/HoldToTalk/
            .deletingLastPathComponent()  // Sources/
            .deletingLastPathComponent()  // project root
        let url = projectRoot.appendingPathComponent("Resources/HoldToTalk.icns")
        if let img = NSImage(contentsOf: url), img.isValid { return img }
        return nil
    }()
}

private func makeInstallAlert(
    icon: NSImage?,
    compatibility: SystemCompatibility
) -> NSAlert {
    let alert = NSAlert()
    alert.messageText = compatibility.isSupported ? "Move to Applications?" : "This Mac is not supported"
    alert.informativeText = compatibility.installPromptText
    alert.alertStyle = compatibility.isSupported ? .informational : .warning
    alert.icon = icon

    if compatibility.isSupported {
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
    } else {
        alert.addButton(withTitle: "OK")
    }

    return alert
}

private struct OnboardingWindowConfigurator: NSViewRepresentable {
    let isBlocking: Bool

    func makeNSView(context: Context) -> WindowProbeView {
        let view = WindowProbeView()
        view.onResolve = { window in
            context.coordinator.configure(window: window, isBlocking: isBlocking)
        }
        return view
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {
        nsView.onResolve = { window in
            context.coordinator.configure(window: window, isBlocking: isBlocking)
        }
        context.coordinator.configure(window: nsView.window, isBlocking: isBlocking)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        func configure(window: NSWindow?, isBlocking: Bool) {
            guard let window else { return }

            var styleMask = window.styleMask
            if isBlocking {
                styleMask.remove([.closable, .miniaturizable])
            } else {
                styleMask.insert([.closable, .miniaturizable])
            }
            window.styleMask = styleMask

            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for button in buttons {
                window.standardWindowButton(button)?.isHidden = isBlocking
                window.standardWindowButton(button)?.isEnabled = !isBlocking
            }
        }
    }
}

private final class WindowProbeView: NSView {
    var onResolve: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onResolve?(window)
    }
}
