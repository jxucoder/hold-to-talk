import SwiftUI
import ServiceManagement
import AVFoundation

struct SettingsView: View {
    @ObservedObject var engine: DictationEngine
    @ObservedObject var modelManager: ModelManager
    var updater: (any AppUpdateDriver)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var launchAtLogin: Bool = UserDefaults.standard.bool(forKey: launchAtLoginDefaultsKey)
    @State private var isRunningEnvironmentFix = false
    @State private var pendingFixInputMonitoring = false
    @State private var diagnosticsMessage: String?
    @AppStorage(diagnosticLoggingEnabledDefaultsKey) private var diagnosticLoggingEnabled = false

    @State private var openaiAPIKey: String = ""
    @State private var anthropicAPIKey: String = ""

    private let hotkeys = HotkeyManager.Hotkey.selectableCases
    private var activeTranscriptionProfile: TranscriptionProfile {
        TranscriptionProfile(rawValue: engine.transcriptionProfile) ?? .balanced
    }
    private var allChecksHealthy: Bool {
        let modelOK = modelManager.isDownloaded || engine.resolvedTranscriptionProvider != .local
        return engine.hasMicrophone && engine.hasPostEvent && engine.hasInputMonitoring && modelOK
    }

    var body: some View {
        Form {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    Group {
                        if let icon = HoldToTalkApp.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                        } else {
                            Image(systemName: "mic")
                                .resizable()
                                .scaledToFit()
                        }
                    }
                    .frame(width: 64, height: 64)
                    Text("Hold to Talk")
                        .font(.title2.bold())
                    Text("Free and open-source. Audio stays on your Mac. Fast on-device speech recognition.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Link(destination: URL(string: "https://github.com/jxucoder/hold-to-talk")!) {
                            Image(systemName: "star")
                                .font(.caption)
                        }
                        Link(destination: URL(string: "https://buymeacoffee.com/jerryxu")!) {
                            Image(systemName: "cup.and.saucer.fill")
                                .font(.caption)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)

            Section("General") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                            UserDefaults.standard.set(enabled, forKey: launchAtLoginDefaultsKey)
                        } catch {
                            launchAtLogin = !enabled
                        }
                    }

                if let updater {
                    Button("Check for Updates…") {
                        updater.checkForUpdates()
                    }
                }
            }

            Section("Diagnostics") {
                statusRow(
                    title: "Microphone",
                    ok: engine.hasMicrophone,
                    details: engine.hasMicrophone ? "Granted" : "Not granted"
                )
                statusRow(
                    title: "Keyboard Access",
                    ok: engine.hasPostEvent,
                    details: engine.hasPostEvent ? "Granted" : "Not granted"
                )
                statusRow(
                    title: "Input Monitoring",
                    ok: engine.hasInputMonitoring,
                    details: engine.hasInputMonitoring ? "Granted" : "Not granted"
                )
                statusRow(
                    title: "Speech model",
                    ok: modelManager.isDownloaded || engine.resolvedTranscriptionProvider != .local,
                    details: modelManager.isDownloaded
                        ? "\(SpeechModelInfo.displayName) ready"
                        : (modelManager.isDownloading
                            ? "Downloading \(SpeechModelInfo.displayName)..."
                            : (engine.resolvedTranscriptionProvider != .local
                                ? "Using cloud transcription"
                                : "\(SpeechModelInfo.displayName) not downloaded"))
                )
                Toggle("Store diagnostic logs", isOn: $diagnosticLoggingEnabled)
                    .onChange(of: diagnosticLoggingEnabled) { _, enabled in
                        if enabled {
                            debugLog("[holdtotalk] Diagnostic logging enabled.")
                        } else {
                            clearDebugLog()
                        }
                    }

                Text(diagnosticLoggingEnabled
                     ? "Local diagnostic logging is enabled. Logs stay on your Mac and transcript text is redacted."
                     : "Diagnostic logging is off by default. Turn it on only when troubleshooting; transcript text stays redacted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let diagnosticsMessage {
                    Text(diagnosticsMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(allChecksHealthy ? "Environment Healthy" : "Fix Environment") {
                    runGuidedEnvironmentFix()
                }
                .disabled(isRunningEnvironmentFix || allChecksHealthy)

                if isRunningEnvironmentFix {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Section("Transcription") {
                Picker("Provider", selection: $engine.transcriptionProvider) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider.rawValue)
                    }
                }

                if engine.resolvedTranscriptionProvider == .openAI {
                    SecureField("OpenAI API Key", text: $openaiAPIKey)
                        .onChange(of: openaiAPIKey) {
                            KeychainHelper.save(account: "openai", key: openaiAPIKey)
                        }
                    TextField("Model", text: $engine.openaiTranscriptionModel,
                              prompt: Text("gpt-4o-mini-transcribe"))
                        .font(.system(.body, design: .monospaced))
                    TextField("Base URL", text: $engine.openaiBaseURL,
                              prompt: Text("https://api.openai.com/v1"))
                        .font(.system(.body, design: .monospaced))
                    Text("Uses the OpenAI-compatible transcription API. Your API key is stored in the macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if engine.resolvedTranscriptionProvider == .local {
                    Picker("Profile", selection: $engine.transcriptionProfile) {
                        ForEach(TranscriptionProfile.allCases) { profile in
                            Text(profile.displayName)
                                .tag(profile.rawValue)
                        }
                    }
                    Text(activeTranscriptionProfile.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DisclosureGroup("Hotwords") {
                        TextEditor(text: $engine.hotwords)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 60, maxHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(.separator)
                            )

                        Text("Boost recognition of specific words or phrases. One per line. Uses modified beam search (slightly slower).")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            Spacer()
                            if !engine.hotwords.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Button("Clear") {
                                    engine.hotwords = ""
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .onChange(of: engine.hotwords) {
                        engine.reloadTranscriber()
                    }
                }
            }

            Section("Text Cleanup") {
                Toggle("Clean up transcribed text", isOn: $engine.textCleanupEnabled)

                if engine.textCleanupEnabled {
                    Picker("Provider", selection: $engine.cleanupProvider) {
                        ForEach(CleanupProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                    }

                    if engine.resolvedCleanupProvider == .appleIntelligence {
                        let availability = TextCleanup.checkAvailability()
                        HStack(spacing: 6) {
                            if availability == .available {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Apple Intelligence is available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(textCleanupUnavailableReason(availability))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("Text is cleaned up on-device to fix punctuation, remove repeated words, and remove filler words.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if engine.resolvedCleanupProvider == .openAI {
                        SecureField("OpenAI API Key", text: $openaiAPIKey)
                            .onChange(of: openaiAPIKey) {
                                KeychainHelper.save(account: "openai", key: openaiAPIKey)
                            }
                        TextField("Model", text: $engine.openaiCleanupModel,
                                  prompt: Text(CleanupProvider.openAI.defaultModel))
                            .font(.system(.body, design: .monospaced))
                        if engine.resolvedTranscriptionProvider != .openAI {
                            TextField("Base URL", text: $engine.openaiBaseURL,
                                      prompt: Text("https://api.openai.com/v1"))
                                .font(.system(.body, design: .monospaced))
                        }
                        Text("Your API key is stored in the macOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if engine.resolvedCleanupProvider == .anthropic {
                        SecureField("Anthropic API Key", text: $anthropicAPIKey)
                            .onChange(of: anthropicAPIKey) {
                                KeychainHelper.save(account: "anthropic", key: anthropicAPIKey)
                            }
                        TextField("Model", text: $engine.anthropicCleanupModel,
                                  prompt: Text(CleanupProvider.anthropic.defaultModel))
                            .font(.system(.body, design: .monospaced))
                        TextField("Base URL", text: $engine.anthropicBaseURL,
                                  prompt: Text("https://api.anthropic.com"))
                            .font(.system(.body, design: .monospaced))
                        Text("Your API key is stored in the macOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    DisclosureGroup("Prompt") {
                        TextEditor(text: $engine.textCleanupPrompt)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 80, maxHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(.separator)
                            )

                        HStack {
                            Spacer()
                            if engine.textCleanupPrompt != TextCleanup.defaultPrompt {
                                Button("Reset to Default") {
                                    engine.textCleanupPrompt = TextCleanup.defaultPrompt
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            Section("Speech Model") {
                modelStatusView
                ModelTrustView()
            }

            Section("Hotkey") {
                Picker("Hold to record", selection: $engine.hotkeyChoice) {
                    ForEach(hotkeys, id: \.rawValue) { key in
                        Text(key.displayName).tag(key.rawValue)
                    }
                }
                .onChange(of: engine.hotkeyChoice) {
                    engine.reloadHotkey()
                }
            }

        }
        .formStyle(.grouped)
        .frame(width: 440, height: 780)
        .padding()
        .onAppear {
            modelManager.refreshDownloadStatus()
            refreshPermissionSnapshot()
            if TranscriptionProfile(rawValue: engine.transcriptionProfile) == nil {
                engine.transcriptionProfile = TranscriptionProfile.balanced.rawValue
            }
            openaiAPIKey = KeychainHelper.load(account: "openai") ?? ""
            anthropicAPIKey = KeychainHelper.load(account: "anthropic") ?? ""
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionSnapshot()
            continueGuidedFixIfNeeded()
        }
    }

    // MARK: - Model Status

    @ViewBuilder
    private var modelStatusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(SpeechModelInfo.displayName)
                        .fontWeight(.semibold)
                    Text(modelManager.isDownloaded
                         ? (modelManager.diskSize() ?? SpeechModelInfo.sizeLabel)
                         : SpeechModelInfo.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if modelManager.isDownloaded {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button(role: .destructive) {
                            modelManager.deleteModel()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                } else if modelManager.isDownloading {
                    Button("Cancel") {
                        modelManager.cancelDownload()
                    }
                    .controlSize(.small)
                } else {
                    Button("Download") {
                        modelManager.download()
                    }
                    .controlSize(.small)
                }
            }

            if modelManager.isDownloading {
                ProgressView(value: modelManager.downloadProgress)
                    .progressViewStyle(.linear)
                Text("\(Int(modelManager.downloadProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = modelManager.downloadError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Diagnostics

    private func statusRow(title: String, ok: Bool, details: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func refreshPermissionSnapshot() {
        engine.refreshPermissionSnapshot()
    }

    private func runGuidedEnvironmentFix() {
        isRunningEnvironmentFix = true
        pendingFixInputMonitoring = false
        diagnosticsMessage = nil

        refreshPermissionSnapshot()

        requestMicrophonePermission(openSettings: true) {
            Task { @MainActor in
                refreshPermissionSnapshot()
                continueAfterMicrophoneFix()
            }
        }
    }

    private func continueAfterMicrophoneFix() {
        guard engine.hasMicrophone else {
            diagnosticsMessage = "Enable Microphone access in System Settings, then return here."
            isRunningEnvironmentFix = false
            return
        }

        _ = requestPostEventPermission()
        refreshPermissionSnapshot()
        if !engine.hasPostEvent {
            pendingFixInputMonitoring = true
            diagnosticsMessage = "Enable Keyboard Access, then return to Hold to Talk."
            isRunningEnvironmentFix = false
            return
        }

        finishGuidedEnvironmentFix()
    }

    private func continueGuidedFixIfNeeded() {
        guard pendingFixInputMonitoring else { return }
        guard engine.hasPostEvent else { return }

        pendingFixInputMonitoring = false
        finishGuidedEnvironmentFix()
    }

    private func finishGuidedEnvironmentFix() {
        _ = requestInputMonitoringPermission()
        refreshPermissionSnapshot()

        if !engine.hasInputMonitoring {
            diagnosticsMessage = "Enable Input Monitoring, then return to Hold to Talk."
            isRunningEnvironmentFix = false
            return
        }

        if !modelManager.isDownloaded && !modelManager.isDownloading {
            modelManager.download()
            diagnosticsMessage = "Downloading \(SpeechModelInfo.displayName)…"
        } else if modelManager.isDownloading {
            diagnosticsMessage = "Downloading \(SpeechModelInfo.displayName)…"
        } else {
            diagnosticsMessage = "Environment is healthy."
        }

        isRunningEnvironmentFix = false
    }

    private func requestMicrophonePermission(openSettings: Bool, completion: @escaping () -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                Task { @MainActor in
                    completion()
                }
            }
        case .denied, .restricted:
            if openSettings {
                openSystemSettings("Privacy_Microphone")
            }
            completion()
        @unknown default:
            completion()
        }
    }

    @discardableResult
    private func requestPostEventPermission() -> PermissionRequestResult {
        requestPostEventAccess()
    }

    @discardableResult
    private func requestInputMonitoringPermission() -> PermissionRequestResult {
        requestInputMonitoringAccess()
    }

    private func textCleanupUnavailableReason(_ availability: TextCleanupAvailability) -> String {
        switch availability {
        case .available:
            return "Apple Intelligence is available"
        case .unavailableOSVersion:
            return "Requires macOS 26 or later"
        case .unavailableNotEnabled:
            return "Enable Apple Intelligence in System Settings"
        case .unavailableDeviceNotEligible:
            return "This Mac does not support Apple Intelligence"
        case .unavailableModelNotReady:
            return "Apple Intelligence model is downloading"
        }
    }
}
