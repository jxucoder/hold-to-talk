import SwiftUI
import ServiceManagement
import AVFoundation
import ApplicationServices
import Sparkle

struct SettingsView: View {
    @ObservedObject var engine: DictationEngine
    @ObservedObject var modelManager: ModelManager
    var updater: SPUUpdater? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var showManageModels = false
    @State private var showCleanupPrompt = false
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var isRunningEnvironmentFix = false
    @State private var pendingFixInputMonitoring = false
    @State private var diagnosticsMessage: String?

    private let hotkeys = HotkeyManager.Hotkey.allCases
    private var activeTranscriptionProfile: TranscriptionProfile {
        TranscriptionProfile(rawValue: engine.transcriptionProfile) ?? .balanced
    }
    private var activeModelID: String { engine.whisperModel }
    private var isActiveModelDownloaded: Bool { modelManager.downloaded.contains(activeModelID) }
    private var isActiveModelDownloading: Bool { modelManager.downloading.contains(activeModelID) }
    private var allChecksHealthy: Bool {
        engine.hasMicrophone && engine.hasAccessibility && engine.hasInputMonitoring && isActiveModelDownloaded
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
                    Text("Free, open-source, and fully private — nothing leaves your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 12) {
                        Link(destination: URL(string: "https://github.com/jxucoder/holdtotalk")!) {
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
                    title: "Accessibility",
                    ok: engine.hasAccessibility,
                    details: engine.hasAccessibility ? "Granted" : "Not granted"
                )
                statusRow(
                    title: "Input Monitoring",
                    ok: engine.hasInputMonitoring,
                    details: engine.hasInputMonitoring ? "Granted" : "Not granted"
                )
                statusRow(
                    title: "Active model",
                    ok: isActiveModelDownloaded,
                    details: isActiveModelDownloaded
                        ? "\(modelDisplayName(activeModelID)) ready"
                        : (isActiveModelDownloading
                            ? "Downloading \(modelDisplayName(activeModelID))..."
                            : "\(modelDisplayName(activeModelID)) not downloaded")
                )

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

            Section("Whisper Model") {
                Picker("Active model", selection: $engine.whisperModel) {
                    ForEach(sortedModels) { model in
                        HStack {
                            Text(model.displayName)
                            if !modelManager.downloaded.contains(model.id) {
                                Text("(not downloaded)")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        .tag(model.id)
                    }
                }

                DisclosureGroup(isExpanded: $showManageModels) {
                    modelListView
                } label: {
                    Text("Manage Models")
                }
                .contentShape(Rectangle())
                .onTapGesture { showManageModels.toggle() }
            }

            Section("Cleanup") {
                Toggle("Enable cleanup", isOn: $engine.cleanupEnabled)

                if TextProcessor.isAvailable {
                    Label("Apple Intelligence (on-device)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Requires macOS 26+ with Apple Intelligence", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

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
                        Text(key.rawValue).tag(key.rawValue)
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
            refreshPermissionSnapshot()
            let available = engine.availableWhisperModels.isEmpty ? WhisperModelInfo.all : engine.availableWhisperModels
            if !available.contains(where: { $0.id == engine.whisperModel }) {
                engine.whisperModel = engine.recommendedWhisperModelID
            }
            if TranscriptionProfile(rawValue: engine.transcriptionProfile) == nil {
                engine.transcriptionProfile = TranscriptionProfile.balanced.rawValue
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissionSnapshot()
            continueGuidedFixIfNeeded()
        }
        .onChange(of: engine.whisperModel) {
            modelManager.refreshDownloadStatus()
            if diagnosticsMessage != nil {
                diagnosticsMessage = nil
            }
        }
    }

    // MARK: - Model list

    private var sortedModels: [WhisperModelInfo] {
        let models = engine.availableWhisperModels.isEmpty ? WhisperModelInfo.all : engine.availableWhisperModels
        // Fix #16: stable sort — downloaded first, then alphabetical by id
        return models.sorted { a, b in
            let aDown = modelManager.downloaded.contains(a.id)
            let bDown = modelManager.downloaded.contains(b.id)
            if aDown != bDown { return aDown }
            return a.id < b.id
        }
    }

    private var modelListView: some View {
        let models = engine.availableWhisperModels.isEmpty ? WhisperModelInfo.all : engine.availableWhisperModels
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(models) { model in
                modelRow(model)
            }
        }
    }

    private func modelRow(_ model: WhisperModelInfo) -> some View {
        let isDownloaded = modelManager.downloaded.contains(model.id)
        let isDownloading = modelManager.downloading.contains(model.id)
        let isActive = engine.whisperModel == model.id

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(model.displayName)
                            .fontWeight(isActive ? .semibold : .regular)
                        if isActive {
                            Text("ACTIVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.blue, in: Capsule())
                        }
                    }
                    Text(isDownloaded
                         ? (modelManager.diskSize(for: model.id) ?? model.sizeLabel)
                         : model.sizeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isDownloaded {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if !isActive {
                            Button(role: .destructive) {
                                modelManager.delete(model.id)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } else if isDownloading {
                    Button("Cancel") {
                        modelManager.cancelDownload(model.id)
                    }
                    .controlSize(.small)
                } else {
                    Button("Download") {
                        modelManager.download(model.id)
                    }
                    .controlSize(.small)
                }
            }

            if isDownloading, let progress = modelManager.downloadProgress[model.id] {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("\(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let error = modelManager.downloadErrors[model.id] {
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
        // Delegate to the engine — single source of truth for permission state.
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

        requestAccessibilityPermission(openSettings: false)
        refreshPermissionSnapshot()
        if !engine.hasAccessibility {
            pendingFixInputMonitoring = true
            diagnosticsMessage = "Enable Accessibility, then return to Hold to Talk."
            openSystemSettings("Privacy_Accessibility")
            isRunningEnvironmentFix = false
            return
        }

        finishGuidedEnvironmentFix()
    }

    private func continueGuidedFixIfNeeded() {
        guard pendingFixInputMonitoring else { return }
        guard engine.hasAccessibility else { return }

        pendingFixInputMonitoring = false
        finishGuidedEnvironmentFix()
    }

    private func finishGuidedEnvironmentFix() {
        requestInputMonitoringPermission(openSettings: false)
        refreshPermissionSnapshot()

        if !engine.hasInputMonitoring {
            diagnosticsMessage = "Enable Input Monitoring, then return to Hold to Talk."
            openSystemSettings("Privacy_ListenEvent")
            isRunningEnvironmentFix = false
            return
        }

        if !isActiveModelDownloaded && !isActiveModelDownloading {
            modelManager.download(activeModelID)
            diagnosticsMessage = "Downloading \(modelDisplayName(activeModelID))…"
        } else if isActiveModelDownloading {
            diagnosticsMessage = "Downloading \(modelDisplayName(activeModelID))…"
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

    private func requestAccessibilityPermission(openSettings: Bool) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if !AXIsProcessTrusted() && openSettings {
            openSystemSettings("Privacy_Accessibility")
        }
    }

    private func requestInputMonitoringPermission(openSettings: Bool) {
        _ = CGRequestListenEventAccess()
        UserDefaults.standard.set(true, forKey: "hasPromptedInputMonitoring")
        if !CGPreflightListenEventAccess() && openSettings {
            openSystemSettings("Privacy_ListenEvent")
        }
    }

    private func modelDisplayName(_ id: String) -> String {
        let models = engine.availableWhisperModels.isEmpty ? WhisperModelInfo.all : engine.availableWhisperModels
        return models.first { $0.id == id }?.displayName
            ?? WhisperModelInfo.all.first { $0.id == id }?.displayName
            ?? id
    }

}
