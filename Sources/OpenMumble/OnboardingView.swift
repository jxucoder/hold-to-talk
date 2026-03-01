import SwiftUI
import AVFoundation
import ApplicationServices

struct OnboardingView: View {
    @ObservedObject var engine: DictationEngine
    @StateObject private var modelManager = ModelManager()
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var hasMicrophone = false
    @State private var hasAccessibility = false
    @State private var hasInputMonitoring = false
    @State private var permissionTimer: Timer?
    @State private var downloadStarted = false

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<4) { i in
                    Capsule()
                        .fill(i <= step ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 20)

            Spacer()

            Group {
                switch step {
                case 0: welcomeStep
                case 1: permissionsStep
                case 2: modelStep
                default: readyStep
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))

            Spacer()
        }
        .frame(width: 480, height: 520)
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            appIcon
                .frame(width: 80, height: 80)

            Text("Welcome to OpenMumble")
                .font(.title.bold())

            Text("Voice dictation that runs entirely on your Mac.\nHold a key, speak, release — your words appear wherever your cursor is.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            Button("Get Started") {
                step = 1
                startPermissionPolling()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(32)
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            Text("Permissions")
                .font(.title2.bold())

            Text("OpenMumble needs a few permissions to work.")
                .font(.body)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "Record your voice for transcription",
                    granted: hasMicrophone
                ) {
                    AVCaptureDevice.requestAccess(for: .audio) { granted in
                        Task { @MainActor in hasMicrophone = granted }
                    }
                }

                permissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    subtitle: "Paste text into the active app",
                    granted: hasAccessibility
                ) {
                    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    _ = AXIsProcessTrustedWithOptions(opts)
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }

                permissionRow(
                    icon: "keyboard.fill",
                    title: "Input Monitoring",
                    subtitle: "Listen for your hotkey globally",
                    granted: hasInputMonitoring
                ) {
                    _ = CGRequestListenEventAccess()
                }
            }
            .padding(.horizontal, 16)

            Button("Continue") {
                stopPermissionPolling()
                step = 2
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasMicrophone || !hasAccessibility)
            .padding(.top, 8)

            if !hasMicrophone || !hasAccessibility {
                Text("Grant Microphone and Accessibility to continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .onAppear { startPermissionPolling() }
        .onDisappear { stopPermissionPolling() }
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
            } else {
                Button("Grant") { action() }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(granted ? Color.green.opacity(0.06) : Color.secondary.opacity(0.06))
        )
    }

    // MARK: - Step 3: Model Download

    private var modelStep: some View {
        VStack(spacing: 20) {
            Text("Download Model")
                .font(.title2.bold())

            Text("OpenMumble needs a speech recognition model.\nPick one to download — you can change this later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Picker("Model", selection: $engine.whisperModel) {
                ForEach(WhisperModelInfo.all) { model in
                    Text("\(model.displayName)  (\(model.sizeLabel))")
                        .tag(model.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 280)

            let modelId = engine.whisperModel
            let isDownloaded = modelManager.downloaded.contains(modelId)
            let isDownloading = modelManager.downloading.contains(modelId)

            if isDownloaded {
                Label("Ready to use", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else if isDownloading {
                VStack(spacing: 8) {
                    if let progress = modelManager.downloadProgress[modelId] {
                        ProgressView(value: progress)
                            .frame(width: 280)
                        Text("Downloading... \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                        Text("Starting download...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button("Download \(modelDisplayName(modelId))") {
                    modelManager.download(modelId)
                    downloadStarted = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if let error = modelManager.downloadErrors[modelId] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: 320)
            }

            Button("Continue") {
                step = 3
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!isDownloaded)
            .padding(.top, 4)
        }
        .padding(32)
        .onAppear {
            modelManager.refreshDownloadStatus()
            let modelId = engine.whisperModel
            if !modelManager.downloaded.contains(modelId) && !modelManager.downloading.contains(modelId) {
                modelManager.download(modelId)
                downloadStarted = true
            }
        }
        .onChange(of: engine.whisperModel) {
            let modelId = engine.whisperModel
            modelManager.refreshDownloadStatus()
            if !modelManager.downloaded.contains(modelId) && !modelManager.downloading.contains(modelId) {
                modelManager.download(modelId)
            }
        }
    }

    // MARK: - Step 4: Ready

    private var readyStep: some View {
        VStack(spacing: 20) {
            Text("You're All Set")
                .font(.title2.bold())

            VStack(spacing: 16) {
                // Hotkey picker
                VStack(spacing: 8) {
                    Text("Hold this key to record:")
                        .font(.body)

                    Picker("Hotkey", selection: $engine.hotkeyChoice) {
                        ForEach(HotkeyManager.Hotkey.allCases, id: \.rawValue) { key in
                            Text(key.rawValue).tag(key.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 340)
                    .onChange(of: engine.hotkeyChoice) {
                        engine.reloadHotkey()
                    }
                }

                // Usage instructions
                HStack(spacing: 24) {
                    stepBubble(number: "1", label: "Hold", detail: "[\(engine.hotkeyChoice)]")
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    stepBubble(number: "2", label: "Speak", detail: "your words")
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    stepBubble(number: "3", label: "Release", detail: "text appears")
                }
                .padding(.top, 8)

                // Menu bar hint
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                        .font(.caption.bold())
                    Text("OpenMumble lives in your menu bar")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            }

            Button("Start Using OpenMumble") {
                engine.completeOnboarding()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(32)
    }

    private func stepBubble(number: String, label: String, detail: String) -> some View {
        VStack(spacing: 4) {
            Text(number)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(label)
                .font(.headline)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var appIcon: some View {
        if let icon = OpenMumbleApp.appIcon {
            Image(nsImage: icon)
                .resizable()
        } else {
            Image(systemName: "mic.circle.fill")
                .resizable()
                .foregroundStyle(Color.accentColor)
        }
    }

    private func modelDisplayName(_ id: String) -> String {
        WhisperModelInfo.all.first { $0.id == id }?.displayName ?? id
    }

    private func startPermissionPolling() {
        refreshPermissions()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in refreshPermissions() }
        }
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    private func refreshPermissions() {
        hasMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        hasAccessibility = AXIsProcessTrusted()
        hasInputMonitoring = CGPreflightListenEventAccess()
        engine.hasAccessibility = hasAccessibility
    }
}
