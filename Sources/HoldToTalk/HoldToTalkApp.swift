import SwiftUI
import ApplicationServices
import AVFoundation
import Sparkle

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

        if !isInstalledInApplicationsFolder() && !UserDefaults.standard.bool(forKey: "dismissedInstallPrompt") {
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
        let alert = NSAlert()
        alert.messageText = "Move to Applications?"
        alert.informativeText = "Hold to Talk works best when installed in /Applications. Permissions and Launch at Login require it.\n\nWould you like to move it now?"
        alert.alertStyle = .informational
        if let icon = HoldToTalkApp.appIcon {
            alert.icon = icon
        }
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        let response = alert.runModal()

        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: "dismissedInstallPrompt")
        }

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
}

@main
struct HoldToTalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = DictationEngine()
    @Environment(\.openWindow) private var openWindow
    private let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    private var shouldShowOnboarding: Bool {
        #if DEBUG
        if DebugFlags.forceOnboarding { return true }
        #endif
        return !engine.onboardingComplete
    }

    var body: some Scene {
        MenuBarExtra {
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

                if !engine.hasMicrophone || !engine.hasAccessibility || !engine.hasInputMonitoring {
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

                        if !engine.hasAccessibility {
                            permissionWarningRow("Accessibility not granted")
                            Button("Grant Accessibility…") {
                                let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                                _ = AXIsProcessTrustedWithOptions(opts)
                                openSystemSettings("Privacy_Accessibility")
                            }
                            .font(.caption)
                        }

                        if !engine.hasInputMonitoring {
                            permissionWarningRow("Input Monitoring not granted")
                            Button("Grant Input Monitoring…") {
                                _ = CGRequestListenEventAccess()
                                openSystemSettings("Privacy_ListenEvent")
                            }
                            .font(.caption)
                        }

                        Button("Open Onboarding…") {
                            openWindow(id: "onboarding")
                            NSApp.activate(ignoringOtherApps: true)
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
        } label: {
            Label("Hold to Talk", systemImage: engine.state.icon)
        }

        Window("Welcome to Hold to Talk", id: "onboarding") {
            OnboardingView(engine: engine, modelManager: engine.modelManager)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(shouldShowOnboarding ? .presented : .suppressed)

        Window("Hold to Talk Settings", id: "settings") {
            SettingsView(engine: engine, modelManager: engine.modelManager, updater: updaterController.updater)
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
        let alert = NSAlert()
        alert.messageText = "Move to Applications?"
        alert.informativeText = "Hold to Talk works best when installed in /Applications. Permissions and Launch at Login require it.\n\nWould you like to move it now?"
        alert.alertStyle = .informational
        if let icon = Self.appIcon {
            alert.icon = icon
        }
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")

        let response = alert.runModal()
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
