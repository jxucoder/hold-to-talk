import SwiftUI
import AVFoundation
import ApplicationServices

struct OnboardingView: View {
    @ObservedObject var engine: DictationEngine
    @ObservedObject var modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("onboardingStep") private var step = 0
    @State private var hasMicrophone = false
    @State private var hasAccessibility = false
    @State private var hasInputMonitoring = false
    @State private var downloadStarted = false
    @State private var hasShownAccessibilityPrompt = false
    @State private var hasShownInputMonitoringPrompt = UserDefaults.standard.bool(forKey: "hasPromptedInputMonitoring")
    @State private var pendingGrantAllInputMonitoring = false
    @State private var isRequestingPermissions = false
    @State private var isInstallingToApplications = false
    @State private var installErrorMessage: String?
    @StateObject private var hotkeyTester = HotkeyTester()

    init(engine: DictationEngine, modelManager: ModelManager) {
        self.engine = engine
        self.modelManager = modelManager
        #if DEBUG
        if let override = DebugFlags.onboardingStep {
            let clamped = max(0, min(override, 3))
            UserDefaults.standard.set(clamped, forKey: "onboardingStep")
            print("[debug] Starting onboarding at step \(clamped).")
        }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
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
        let installed = isInstalledInApplicationsFolder()

        return VStack(spacing: 16) {
            VStack(spacing: 14) {
                appIcon
                    .frame(width: 80, height: 80)

                Text("Welcome to Hold to Talk")
                    .font(.title.bold())

                Text("Private voice dictation on your Mac.\nHold a key, speak, release — text appears wherever your cursor is.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentColor.opacity(0.08))
            )

            VStack(alignment: .leading, spacing: 8) {
                featureRow("lock.fill", "Fully local: audio never leaves your Mac")
                featureRow("keyboard", "Global hold-to-talk hotkey")
                featureRow("bolt.fill", "Optimized for low-latency dictation")
            }
            .frame(maxWidth: 360, alignment: .leading)

            if !installed {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Install to /Applications", systemImage: "arrow.down.app.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Hold to Talk works best when installed in /Applications.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Install to Applications") {
                        installErrorMessage = nil
                        isInstallingToApplications = true
                        switch installToApplicationsAndRelaunch() {
                        case .success:
                            break
                        case .failure(let message):
                            installErrorMessage = message
                            isInstallingToApplications = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    if isInstallingToApplications {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .frame(maxWidth: 360, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.08))
                )

                if let installErrorMessage {
                    Text(installErrorMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }

            Button(installed ? "Get Started" : "Install to /Applications First") {
                step = 1
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!installed)
            .padding(.top, 4)
        }
        .padding(32)
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 2: Permissions

    private var hasCorePermissions: Bool {
        hasMicrophone && hasAccessibility
    }

    private var hasAllPermissions: Bool {
        hasCorePermissions && hasInputMonitoring
    }

    private var permissionsGrantedCount: Int {
        [hasMicrophone, hasAccessibility, hasInputMonitoring].filter { $0 }.count
    }

    private var microphoneActionTitle: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: return "Grant"
        case .authorized: return "Granted"
        case .denied, .restricted: return "Open Settings"
        @unknown default: return "Grant"
        }
    }

    private var accessibilityActionTitle: String {
        hasShownAccessibilityPrompt ? "Open Settings" : "Grant"
    }

    private var inputMonitoringActionTitle: String {
        if hasInputMonitoring { return "Granted" }
        return hasShownInputMonitoringPrompt ? "Open Settings" : "Grant"
    }

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            Text("Permissions")
                .font(.title2.bold())

            Text("Grant access in one click. If macOS requires manual approval, we’ll open the right System Settings page.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Setup Progress")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(permissionsGrantedCount)/3 granted")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(permissionsGrantedCount), total: 3)
                    .progressViewStyle(.linear)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
            )
            .frame(maxWidth: 380)

            Button(hasAllPermissions ? "All Permissions Granted" : "Grant All Permissions") {
                requestAllPermissions()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(hasAllPermissions || isRequestingPermissions)

            VStack(spacing: 12) {
                permissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    subtitle: "Record your voice for transcription",
                    granted: hasMicrophone,
                    actionTitle: microphoneActionTitle
                ) {
                    guard !isRequestingPermissions else { return }
                    isRequestingPermissions = true
                    requestMicrophonePermission { [self] in
                        refreshPermissions()
                        isRequestingPermissions = false
                    }
                }

                permissionRow(
                    icon: "hand.raised.fill",
                    title: "Accessibility",
                    subtitle: "Paste text into the active app",
                    granted: hasAccessibility,
                    actionTitle: accessibilityActionTitle
                ) {
                    guard !isRequestingPermissions else { return }
                    isRequestingPermissions = true
                    requestAccessibilityPermission()
                    refreshPermissions()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isRequestingPermissions = false
                    }
                }

                permissionRow(
                    icon: "keyboard.fill",
                    title: "Input Monitoring",
                    subtitle: "Listen for your hotkey globally",
                    granted: hasInputMonitoring,
                    actionTitle: inputMonitoringActionTitle
                ) {
                    guard !isRequestingPermissions else { return }
                    isRequestingPermissions = true
                    requestInputMonitoringPermission()
                    refreshPermissions()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isRequestingPermissions = false
                    }
                }
            }
            .padding(.horizontal, 16)

            if isRequestingPermissions {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for macOS permission dialog…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if hasShownInputMonitoringPrompt && !hasInputMonitoring {
                Text("Input Monitoring will turn green automatically once macOS confirms it. This can take a moment after approval.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            if !hasAllPermissions {
                Button("Open Missing in System Settings") {
                    openFirstMissingPermissionSettings()
                }
                .buttonStyle(.bordered)
                .disabled(isRequestingPermissions)
            }

            Button("Continue") {
                step = 2
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasCorePermissions)
            .padding(.top, 8)

            if !hasCorePermissions {
                Text("Grant Microphone and Accessibility to continue")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !hasInputMonitoring {
                Text("You can continue now. Input Monitoring will greenify automatically once macOS applies the change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            #if DEBUG
            VStack(spacing: 6) {
                Text("Dev builds can't detect Accessibility grants (unsigned binary).")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Button("Skip Permissions (Debug)") {
                    hasMicrophone = true
                    hasAccessibility = true
                    hasInputMonitoring = true
                    engine.hasAccessibility = true
                    step = 2
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)
            #endif
        }
        .padding(32)
        .task {
            // Structured concurrency replaces Timer — auto-cancels when view disappears
            refreshPermissions()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                refreshPermissions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isRequestingPermissions = false
            refreshPermissions()
            continueGrantAllFlowIfNeeded()
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        granted: Bool,
        actionTitle: String = "Grant",
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
                Button(actionTitle) { action() }
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
        let selectableModels = engine.availableWhisperModels.isEmpty ? WhisperModelInfo.all : engine.availableWhisperModels

        return VStack(spacing: 20) {
            Text("Download Model")
                .font(.title2.bold())

            Text("Hold to Talk needs a speech recognition model.\nPick one to download — you can change this later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            Picker("Model", selection: $engine.whisperModel) {
                ForEach(selectableModels) { model in
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

                if isModelUnavailableError(error), modelId != engine.recommendedWhisperModelID {
                    Button("Use Recommended Model") {
                        engine.whisperModel = engine.recommendedWhisperModelID
                        modelManager.refreshDownloadStatus()
                        startModelDownloadIfNeeded()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
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
            ensureSupportedModelSelection()
            startModelDownloadIfNeeded()
        }
        .onChange(of: engine.whisperModel) {
            modelManager.refreshDownloadStatus()
            ensureSupportedModelSelection()
            // Do NOT auto-download on model selection change — the user should explicitly
            // press "Download" for the new selection. Auto-downloading on every picker
            // change wastes bandwidth if the user is browsing options on a metered connection.
        }
    }

    // MARK: - Step 4: Ready

    private var resolvedHotkey: HotkeyManager.Hotkey {
        HotkeyManager.Hotkey(rawValue: engine.hotkeyChoice) ?? .ctrl
    }

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
                        hotkeyTester.remove()
                        hotkeyTester.install(for: resolvedHotkey)
                    }
                }

                // Interactive hotkey test area
                VStack(spacing: 8) {
                    switch hotkeyTester.phase {
                    case .waiting:
                        Image(systemName: "keyboard")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("Press and hold [\(engine.hotkeyChoice)] to test")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .holding:
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                            .symbolEffect(.pulse)
                        Text("Holding [\(engine.hotkeyChoice)]… release to finish")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.green)
                        Text("Hotkey works! You're ready to go.")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                }
                .frame(height: 80)
                .animation(.easeInOut(duration: 0.2), value: hotkeyTester.phase)

                // Menu bar hint
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up")
                        .font(.caption.bold())
                    Text("Hold to Talk lives in your menu bar")
                        .font(.callout)
                }
                .foregroundStyle(.secondary)
                .padding(.top, 12)
            }

            Button("Start Using Hold to Talk") {
                step = 0
                engine.completeOnboarding()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(32)
        .onAppear {
            hotkeyTester.install(for: resolvedHotkey)
        }
        .onDisappear {
            hotkeyTester.remove()
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private var appIcon: some View {
        if let icon = HoldToTalkApp.appIcon {
            Image(nsImage: icon)
                .resizable()
        } else {
            Image(systemName: "mic.circle.fill")
                .resizable()
                .foregroundStyle(Color.accentColor)
        }
    }

    private func modelDisplayName(_ id: String) -> String {
        let models = engine.availableWhisperModels.isEmpty ? WhisperModelInfo.all : engine.availableWhisperModels
        return models.first { $0.id == id }?.displayName
            ?? WhisperModelInfo.all.first { $0.id == id }?.displayName
            ?? id
    }

    private func ensureSupportedModelSelection() {
        let normalized = WhisperModelInfo.normalizeModelID(engine.whisperModel)
        if normalized != engine.whisperModel {
            engine.whisperModel = normalized
            return
        }

        let supportedIDs = Set((engine.availableWhisperModels.isEmpty ? WhisperModelInfo.all : engine.availableWhisperModels).map(\.id))
        if !supportedIDs.contains(engine.whisperModel) {
            engine.whisperModel = engine.recommendedWhisperModelID
        }
    }

    private func startModelDownloadIfNeeded() {
        let modelId = engine.whisperModel
        guard !modelManager.downloaded.contains(modelId),
              !modelManager.downloading.contains(modelId) else {
            return
        }
        modelManager.download(modelId)
        downloadStarted = true
    }

    private func isModelUnavailableError(_ error: String) -> Bool {
        error.localizedCaseInsensitiveContains("No models found matching")
            || error.localizedCaseInsensitiveContains("models unavailable")
            || error.localizedCaseInsensitiveContains("Model variant unavailable")
    }

    private func requestAllPermissions() {
        guard !isRequestingPermissions else { return }
        isRequestingPermissions = true
        pendingGrantAllInputMonitoring = false
        requestMicrophonePermission(openSettings: false) {
            refreshPermissions()

            guard hasMicrophone else {
                openSystemSettings("Privacy_Microphone")
                isRequestingPermissions = false
                return
            }

            requestAccessibilityPermission(openSettings: false)
            refreshPermissions()

            guard hasAccessibility else {
                // Avoid stacked prompts: continue with Input Monitoring after user returns.
                pendingGrantAllInputMonitoring = true
                openSystemSettings("Privacy_Accessibility")
                isRequestingPermissions = false
                return
            }

            requestInputMonitoringPermission(openSettings: false)
            refreshPermissions()
            if !hasInputMonitoring {
                openSystemSettings("Privacy_ListenEvent")
            }
            isRequestingPermissions = false
        }
    }

    private func continueGrantAllFlowIfNeeded() {
        guard pendingGrantAllInputMonitoring else { return }

        if !hasAccessibility {
            return
        }

        isRequestingPermissions = true
        pendingGrantAllInputMonitoring = false
        requestInputMonitoringPermission(openSettings: false)
        refreshPermissions()
        if !hasInputMonitoring {
            openSystemSettings("Privacy_ListenEvent")
        }
        isRequestingPermissions = false
    }

    private func requestMicrophonePermission(openSettings: Bool = true, completion: (() -> Void)? = nil) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            hasMicrophone = true
            completion?()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    hasMicrophone = granted
                    if !granted && openSettings {
                        openSystemSettings("Privacy_Microphone")
                    }
                    completion?()
                }
            }
        case .denied, .restricted:
            hasMicrophone = false
            if openSettings {
                openSystemSettings("Privacy_Microphone")
            }
            completion?()
        @unknown default:
            hasMicrophone = false
            completion?()
        }
    }

    private func requestAccessibilityPermission(openSettings: Bool = true) {
        // Request so macOS registers the app in Accessibility.
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        hasShownAccessibilityPrompt = true
        hasAccessibility = trusted
        engine.hasAccessibility = trusted
        if !trusted && openSettings {
            openSystemSettings("Privacy_Accessibility")
        }
    }

    private func requestInputMonitoringPermission(openSettings: Bool = true) {
        let requestGranted = CGRequestListenEventAccess()
        hasShownInputMonitoringPrompt = true
        UserDefaults.standard.set(true, forKey: "hasPromptedInputMonitoring")
        hasInputMonitoring = requestGranted || CGPreflightListenEventAccess()
        if !hasInputMonitoring && openSettings {
            openSystemSettings("Privacy_ListenEvent")
        }
    }

    private func openFirstMissingPermissionSettings() {
        if !hasAccessibility {
            openSystemSettings("Privacy_Accessibility")
            return
        }
        if !hasInputMonitoring {
            openSystemSettings("Privacy_ListenEvent")
            return
        }
        if !hasMicrophone {
            openSystemSettings("Privacy_Microphone")
        }
    }

    private func refreshPermissions() {
        // Delegate to the engine — single source of truth for permission state.
        // Mirror the results into local @State vars that drive this view's UI.
        engine.refreshPermissionSnapshot()
        hasMicrophone = engine.hasMicrophone
        hasAccessibility = engine.hasAccessibility
        hasInputMonitoring = engine.hasInputMonitoring
    }

    // openSystemSettings is now a shared top-level function in SystemSettingsHelper.swift
}

// MARK: - HotkeyTester

@MainActor
private final class HotkeyTester: ObservableObject {
    enum Phase {
        case waiting, holding, success
    }

    @Published var phase: Phase = .waiting

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hotkey: HotkeyManager.Hotkey = .ctrl

    func install(for hotkey: HotkeyManager.Hotkey) {
        remove()
        self.hotkey = hotkey
        phase = .waiting

        let handler: (NSEvent) -> Void = { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async {
                self?.handle(event)
            }
            return event
        }
    }

    func remove() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }

    private func handle(_ event: NSEvent) {
        let flagsMatch = event.modifierFlags.contains(hotkey.flag)
        let pressed: Bool
        if let requiredCode = hotkey.keyCode {
            pressed = flagsMatch && event.keyCode == requiredCode
        } else {
            pressed = flagsMatch
        }

        if pressed && phase == .waiting {
            phase = .holding
        } else if !pressed && phase == .holding {
            phase = .success
        }
    }
}
