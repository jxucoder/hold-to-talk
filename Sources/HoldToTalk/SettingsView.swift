import SwiftUI
import ServiceManagement
import AVFoundation

struct SettingsView: View {
    @ObservedObject var engine: DictationEngine
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var cleanupModelManager: CleanupModelManager
    var updater: (any AppUpdateDriver)? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var showCleanupPrompt = false
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var isRunningEnvironmentFix = false
    @State private var pendingFixInputMonitoring = false
    @State private var diagnosticsMessage: String?
    @AppStorage(diagnosticLoggingEnabledDefaultsKey) private var diagnosticLoggingEnabled = false

    private let hotkeys = HotkeyManager.Hotkey.selectableCases
    private var activeTranscriptionProfile: TranscriptionProfile {
        TranscriptionProfile(rawValue: engine.transcriptionProfile) ?? .balanced
    }
    private var allChecksHealthy: Bool {
        engine.hasMicrophone && engine.hasPostEvent && engine.hasInputMonitoring && modelManager.isDownloaded
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
                    Text("Free and open-source. Audio stays on your Mac. Fast on-device speech models, with optional on-device Gemma cleanup.")
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
                    ok: modelManager.isDownloaded,
                    details: modelManager.isDownloaded
                        ? "\(SpeechModelInfo.displayName) ready"
                        : (modelManager.isDownloading
                            ? "Downloading \(SpeechModelInfo.displayName)..."
                            : "\(SpeechModelInfo.displayName) not downloaded")
                )
                statusRow(
                    title: "Cleanup model",
                    ok: cleanupModelManager.isDownloaded,
                    details: cleanupModelManager.isDownloaded
                        ? "\(CleanupModelInfo.displayName) ready"
                        : (cleanupModelManager.isDownloading
                            ? "Downloading \(CleanupModelInfo.displayName)..."
                            : "\(CleanupModelInfo.displayName) not downloaded")
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
                Picker("Profile", selection: $engine.transcriptionProfile) {
                    ForEach(TranscriptionProfile.allCases) { profile in
                        Text(profile.displayName)
                            .tag(profile.rawValue)
                    }
                }
                Text(activeTranscriptionProfile.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Speech Model") {
                modelStatusView
                ModelTrustView()
            }

            Section("Cleanup") {
                Toggle("Enable cleanup", isOn: $engine.cleanupEnabled)

                cleanupModelStatusView

                CleanupModelTrustView()

                DisclosureGroup(isExpanded: $showCleanupPrompt) {
                    TextEditor(text: $engine.cleanupPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.background)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(.quaternary)
                                )
                        )

                    if engine.cleanupPrompt != TextProcessor.defaultPrompt {
                        Button("Reset to default") {
                            engine.cleanupPrompt = TextProcessor.defaultPrompt
                        }
                        .controlSize(.small)
                    }
                } label: {
                    Text("Cleanup prompt")
                }
                .contentShape(Rectangle())
                .onTapGesture { showCleanupPrompt.toggle() }
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
        .frame(width: 420, height: 580)
        .padding()
        .onAppear {
            modelManager.refreshDownloadStatus()
            cleanupModelManager.refreshDownloadStatus()
            refreshPermissionSnapshot()
            if TranscriptionProfile(rawValue: engine.transcriptionProfile) == nil {
                engine.transcriptionProfile = TranscriptionProfile.balanced.rawValue
            }
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

    // MARK: - Cleanup Model Status

    @ViewBuilder
    private var cleanupModelStatusView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(CleanupModelInfo.displayName)
                        .fontWeight(.semibold)
                    Text(cleanupModelManager.isDownloaded
                         ? (cleanupModelManager.diskSize() ?? CleanupModelInfo.sizeLabel)
                         : CleanupModelInfo.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if cleanupModelManager.isDownloaded {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button(role: .destructive) {
                            cleanupModelManager.deleteModel()
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                } else if cleanupModelManager.isDownloading {
                    Button("Cancel") {
                        cleanupModelManager.cancelDownload()
                    }
                    .controlSize(.small)
                } else {
                    Button("Download") {
                        cleanupModelManager.download()
                    }
                    .controlSize(.small)
                }
            }

            if cleanupModelManager.isDownloading {
                ProgressView(value: cleanupModelManager.downloadProgress)
                    .progressViewStyle(.linear)
                Text("\(Int(cleanupModelManager.downloadProgress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = cleanupModelManager.downloadError {
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
}
