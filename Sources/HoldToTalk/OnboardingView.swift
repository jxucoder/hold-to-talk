import SwiftUI
import AppKit
import AVFoundation

struct OnboardingView: View {
    @ObservedObject var engine: DictationEngine
    @ObservedObject var modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss
    private let systemCompatibility: SystemCompatibility

    @AppStorage(onboardingStepDefaultsKey) private var step = 0
    @State private var hasMicrophone = false
    @State private var hasPostEvent = false
    @State private var hasInputMonitoring = false
    @AppStorage(postEventPromptedDefaultsKey) private var hasShownPostEventPrompt = false
    @AppStorage(inputMonitoringPromptedDefaultsKey) private var hasShownInputMonitoringPrompt = false
    @State private var isRequestingPermissions = false
    @State private var isInstallingToApplications = false
    @State private var installErrorMessage: String?
    @State private var onboardingWindow: NSWindow?
    @StateObject private var hotkeyTester = HotkeyTester()

    init(engine: DictationEngine, modelManager: ModelManager) {
        self.engine = engine
        self.modelManager = modelManager
        self.systemCompatibility = .current()
        #if DEBUG
        if let override = DebugFlags.onboardingStep {
            let clamped = max(0, min(override, 3))
            UserDefaults.standard.set(clamped, forKey: onboardingStepDefaultsKey)
            print("[debug] Starting onboarding at step \(clamped).")
        }
        #endif
    }

    private enum PermissionRequirement: Int, CaseIterable, Identifiable {
        case microphone
        case keyboardAccess
        case inputMonitoring

        var id: Self { self }

        var icon: String {
            switch self {
            case .microphone: "mic.fill"
            case .keyboardAccess: "keyboard.badge.ellipsis"
            case .inputMonitoring: "keyboard.fill"
            }
        }

        var title: String {
            switch self {
            case .microphone: "Microphone"
            case .keyboardAccess: "Keyboard Access"
            case .inputMonitoring: "Input Monitoring"
            }
        }

        var subtitle: String {
            switch self {
            case .microphone: "Record your voice for transcription."
            case .keyboardAccess: "Type dictated text into any application."
            case .inputMonitoring: "Listen for your hold-to-talk hotkey globally."
            }
        }
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
        .frame(width: 480, height: onboardingWindowHeight)
        .animation(.easeInOut(duration: 0.3), value: step)
        .background(OnboardingWindowReader(window: $onboardingWindow))
    }

    private var onboardingWindowHeight: CGFloat {
        switch step {
        case 0:
            return 620
        case 1:
            return 576
        default:
            return 520
        }
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

                Text("Free, open-source voice dictation for your Mac.\nHold a key, speak, release — text appears wherever your cursor is, and your audio stays local and safe.")
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
                featureRow("chevron.left.forwardslash.chevron.right", "Free and open-source")
                featureRow("lock.fill", "Audio and transcripts stay on-device")
                featureRow("bolt.fill", "Fast Apple Silicon speech models")
            }
            .frame(maxWidth: 360, alignment: .leading)

            systemRequirementsCard

            if !installed {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Install to /Applications", systemImage: "arrow.down.app.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Hold to Talk works best when installed in /Applications. Requires \(systemCompatibility.requirements.summaryText).")
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

            Button(welcomeActionTitle(installed: installed)) {
                step = 1
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!installed || !systemCompatibility.isSupported)
            .padding(.top, 4)

            if !systemCompatibility.isSupported {
                Text(systemCompatibility.statusDetailText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .padding(32)
    }

    private func welcomeActionTitle(installed: Bool) -> String {
        if !systemCompatibility.isSupported {
            return "This Mac Is Not Supported"
        }
        return installed ? "Get Started" : "Install to /Applications First"
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

    private var systemRequirementsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("System requirements", systemImage: "desktopcomputer")
                .font(.headline)

            requirementRow(
                title: "Requires",
                value: systemCompatibility.requirements.summaryText
            )
            requirementRow(
                title: "This Mac",
                value: "macOS \(systemCompatibility.currentMacOSDisplayName)"
            )

            HStack(spacing: 8) {
                Image(systemName: systemCompatibility.isSupported ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(systemCompatibility.statusText)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(systemCompatibility.isSupported ? .green : .red)
        }
        .frame(maxWidth: 360, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill((systemCompatibility.isSupported ? Color.green : Color.red).opacity(0.08))
        )
    }

    private func requirementRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 2: Permissions

    private var hasAllPermissions: Bool {
        hasMicrophone && hasPostEvent && hasInputMonitoring
    }

    private var permissionsGrantedCount: Int {
        [hasMicrophone, hasPostEvent, hasInputMonitoring].filter { $0 }.count
    }

    private var completedPermissions: [PermissionRequirement] {
        PermissionRequirement.allCases.filter(isGranted(_:))
    }

    private var currentPermission: PermissionRequirement? {
        PermissionRequirement.allCases.first(where: { !isGranted($0) })
    }

    private var microphoneActionTitle: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: return "Grant"
        case .authorized: return "Granted"
        case .denied, .restricted: return "Open Settings"
        @unknown default: return "Grant"
        }
    }

    private var keyboardAccessActionTitle: String {
        hasShownPostEventPrompt ? "Open Settings" : "Grant"
    }

    private var inputMonitoringActionTitle: String {
        if hasInputMonitoring { return "Granted" }
        return hasShownInputMonitoringPrompt ? "Open Settings" : "Grant"
    }

    private var permissionsStep: some View {
        VStack(spacing: 20) {
            Text("Permissions")
                .font(.title2.bold())

            Text("Grant the required permissions one at a time. This keeps the macOS prompts clear and predictable.")
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

            if !completedPermissions.isEmpty {
                VStack(spacing: 10) {
                    ForEach(completedPermissions) { permission in
                        completedPermissionRow(permission)
                    }
                }
                .frame(maxWidth: 380)
            }

            if let currentPermission {
                currentPermissionCard(currentPermission)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.green)
                    Text("All permissions granted")
                        .font(.headline)
                    Text("You can continue to model setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: 380)
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.green.opacity(0.08))
                )
            }

            if isRequestingPermissions {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for macOS permission dialog…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if currentPermission == .inputMonitoring && hasShownInputMonitoringPrompt && !hasInputMonitoring {
                Text("Input Monitoring will turn green automatically once macOS confirms it. This can take a moment after approval.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }

            Button("Continue") {
                step = 2
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!hasAllPermissions)
            .padding(.top, 8)

            if !hasAllPermissions, let currentPermission {
                Text("Finish \(currentPermission.title) before continuing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("All required permissions are ready.")
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
                    hasPostEvent = true
                    hasInputMonitoring = true
                    engine.hasPostEvent = true
                    engine.hasMicrophone = true
                    engine.hasInputMonitoring = true
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
            refreshPermissions()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                refreshPermissions()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isRequestingPermissions = false
            refreshPermissions()
            refocusOnboardingWindow()
        }
    }

    private func currentPermissionCard(_ permission: PermissionRequirement) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: permission.icon)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(permission.title)
                        .font(.headline)
                    Text(permission.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button(permissionActionTitle(for: permission)) {
                requestPermission(permission)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isRequestingPermissions)
        }
        .frame(maxWidth: 380, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func completedPermissionRow(_ permission: PermissionRequirement) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(.headline)
                Text("Granted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.green.opacity(0.06))
        )
    }

    // MARK: - Step 3: Model Download

    private var modelStep: some View {
        let selectableModels = engine.availableWhisperModels.isEmpty ? WhisperModelInfo.all : engine.availableWhisperModels
        let recommendedModelName = modelDisplayName(engine.recommendedWhisperModelID)
        let selectedModel = selectableModels.first(where: { $0.id == engine.whisperModel })
            ?? WhisperModelInfo.all.first(where: { $0.id == engine.whisperModel })

        return VStack(spacing: 20) {
            Text("Download Model")
                .font(.title2.bold())

            Text("Hold to Talk needs an on-device speech model.\nPick one to download. Nothing starts until you approve it, you can inspect exactly where it comes from below, and you can change this later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)

            Text("Recommended for this Mac: \(recommendedModelName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Model", selection: $engine.whisperModel) {
                ForEach(selectableModels) { model in
                    Text("\(model.displayName)  (\(model.sizeLabel))")
                        .tag(model.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 280)

            if let selectedModel {
                ModelTrustView(model: selectedModel)
                    .frame(maxWidth: 460)
            }

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
                Button(modelId == engine.recommendedWhisperModelID
                    ? "Download Recommended Model"
                    : "Download \(modelDisplayName(modelId))") {
                    modelManager.download(modelId)
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
            warmUpSelectedModelIfReady()
        }
        .onChange(of: engine.whisperModel) {
            modelManager.refreshDownloadStatus()
            ensureSupportedModelSelection()
            // Do NOT auto-download on model selection change — the user should explicitly
            // press "Download" for the new selection. Auto-downloading on every picker
            // change wastes bandwidth if the user is browsing options on a metered connection.
            warmUpSelectedModelIfReady()
        }
        .onChange(of: modelManager.downloaded) {
            warmUpSelectedModelIfReady()
        }
    }

    // MARK: - Step 4: Ready

    private var resolvedHotkey: HotkeyManager.Hotkey {
        HotkeyManager.Hotkey.preferredSelection(from: engine.hotkeyChoice)
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
                        ForEach(HotkeyManager.Hotkey.selectableCases, id: \.rawValue) { key in
                            Text(key.displayName).tag(key.rawValue)
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
                        Text("Press and hold [\(resolvedHotkey.displayName)] to test")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .holding:
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                            .symbolEffect(.pulse)
                        Text("Holding [\(resolvedHotkey.displayName)]... release to finish")
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
                completeOnboardingAndCloseWindow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(32)
        .onAppear {
            engine.prewarmTranscriber()
            hotkeyTester.install(for: resolvedHotkey)
        }
        .onDisappear {
            hotkeyTester.remove()
            if engine.onboardingComplete {
                step = 0
            }
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

    private func warmUpSelectedModelIfReady() {
        guard modelManager.downloaded.contains(engine.whisperModel) else { return }
        engine.prewarmTranscriber()
    }

    private func isModelUnavailableError(_ error: String) -> Bool {
        error.localizedCaseInsensitiveContains("No models found matching")
            || error.localizedCaseInsensitiveContains("models unavailable")
            || error.localizedCaseInsensitiveContains("Model variant unavailable")
    }

    private func isGranted(_ permission: PermissionRequirement) -> Bool {
        switch permission {
        case .microphone:
            hasMicrophone
        case .keyboardAccess:
            hasPostEvent
        case .inputMonitoring:
            hasInputMonitoring
        }
    }

    private func permissionActionTitle(for permission: PermissionRequirement) -> String {
        switch permission {
        case .microphone:
            microphoneActionTitle
        case .keyboardAccess:
            keyboardAccessActionTitle
        case .inputMonitoring:
            inputMonitoringActionTitle
        }
    }

    private func requestPermission(_ permission: PermissionRequirement) {
        guard !isRequestingPermissions else { return }
        isRequestingPermissions = true

        switch permission {
        case .microphone:
            requestMicrophonePermission {
                refreshPermissions()
                isRequestingPermissions = false
            }
        case .keyboardAccess:
            requestPostEventPermission()
            refreshPermissions()
            finishPermissionRequestAfterDelay()
        case .inputMonitoring:
            requestInputMonitoringPermission()
            refreshPermissions()
            finishPermissionRequestAfterDelay()
        }
    }

    private func finishPermissionRequestAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isRequestingPermissions = false
        }
    }

    private func requestMicrophonePermission(openSettings: Bool = true, completion: (() -> Void)? = nil) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            hasMicrophone = true
            refocusOnboardingWindow()
            completion?()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    hasMicrophone = granted
                    if !granted && openSettings {
                        openSystemSettings("Privacy_Microphone")
                    }
                    self.refocusOnboardingWindow()
                    completion?()
                }
            }
        case .denied, .restricted:
            hasMicrophone = false
            if openSettings {
                openSystemSettings("Privacy_Microphone")
            }
            refocusOnboardingWindow()
            completion?()
        @unknown default:
            hasMicrophone = false
            refocusOnboardingWindow()
            completion?()
        }
    }

    private func requestPostEventPermission() {
        _ = requestPostEventAccess()
        hasShownPostEventPrompt = true
        refreshPermissions()
    }

    private func requestInputMonitoringPermission() {
        _ = requestInputMonitoringAccess()
        hasShownInputMonitoringPrompt = true
        refreshPermissions()
    }

    private func refreshPermissions() {
        engine.refreshPermissionSnapshot()
        hasMicrophone = engine.hasMicrophone
        hasPostEvent = engine.hasPostEvent
        hasInputMonitoring = engine.hasInputMonitoring
    }

    private func refocusOnboardingWindow() {
        guard step == 1, !engine.onboardingComplete, let onboardingWindow else { return }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            onboardingWindow.makeKeyAndOrderFront(nil)
            onboardingWindow.orderFrontRegardless()
        }
    }

    private func completeOnboardingAndCloseWindow() {
        hotkeyTester.remove()
        engine.completeOnboarding()
        if let onboardingWindow {
            onboardingWindow.close()
        } else {
            dismiss()
        }
    }

    // openSystemSettings is now a shared top-level function in SystemSettingsHelper.swift
}

private struct OnboardingWindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> OnboardingWindowProbeView {
        let view = OnboardingWindowProbeView()
        view.onResolve = { resolvedWindow in
            self.window = resolvedWindow
        }
        return view
    }

    func updateNSView(_ nsView: OnboardingWindowProbeView, context: Context) {
        nsView.onResolve = { resolvedWindow in
            self.window = resolvedWindow
        }
        if window !== nsView.window {
            window = nsView.window
        }
    }
}

private final class OnboardingWindowProbeView: NSView {
    var onResolve: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onResolve?(window)
    }
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
