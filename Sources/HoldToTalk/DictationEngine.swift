import SwiftUI
import AppKit
import Combine
import AVFoundation

/// Orchestrates the record -> transcribe -> insert pipeline.
@MainActor
final class DictationEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case transcribing

        var label: String {
            switch self {
            case .idle:         "Ready"
            case .recording:    "Recording..."
            case .transcribing: "Transcribing..."
            }
        }

        var icon: String {
            switch self {
            case .idle:         "mic"
            case .recording:    "mic.fill"
            case .transcribing: "bubble.left"
            }
        }

        var color: Color {
            switch self {
            case .idle:         .secondary
            case .recording:    .red
            case .transcribing: .accentColor
            }
        }
    }

    @Published var state: State = .idle
    private var hudBinding: AnyCancellable?
    @Published var lastRawText: String = ""
    @Published var lastCleanText: String = ""
    @Published var lastInsertDebug: String = ""
    @Published var recordingLevel: Float = 0
    /// Brief user-visible error message; cleared on next successful dictation.
    @Published var lastError: String?
    @Published var hasMicrophone: Bool = {
        #if DEBUG
        if DebugFlags.skipPermissions { return true }
        #endif
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }()
    @Published var hasPostEvent: Bool = {
        #if DEBUG
        if DebugFlags.skipPermissions { return true }
        #endif
        return checkPostEventAccess()
    }()
    @Published var hasInputMonitoring: Bool = {
        #if DEBUG
        if DebugFlags.skipPermissions { return true }
        #endif
        return CGPreflightListenEventAccess()
    }()

    @AppStorage(onboardingCompleteDefaultsKey) var onboardingComplete = false
    @AppStorage(transcriptionProfileDefaultsKey) var transcriptionProfile = TranscriptionProfile.balanced.rawValue
    @AppStorage(hotkeyChoiceDefaultsKey) var hotkeyChoice = HotkeyManager.Hotkey.ctrl.rawValue
    @AppStorage(inputMonitoringPromptedDefaultsKey) private var hasPromptedInputMonitoring = false
    @AppStorage(textCleanupEnabledDefaultsKey) var textCleanupEnabled = TextCleanup.checkAvailability() == .available
    @AppStorage(textCleanupPromptDefaultsKey) var textCleanupPrompt = TextCleanup.defaultPrompt
    @AppStorage(hotwordsDefaultsKey) var hotwords: String = ""

    private let recorder = AudioRecorder()
    private var transcriber: Transcriber?
    private let hotkeyManager = HotkeyManager()
    let modelManager = ModelManager()
    private var didStart = false
    private var recordingTargetAppPID: pid_t?
    private var recordingTargetBundleID: String?
    private var axPollTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var transcriberWarmupTask: Task<Void, Never>?
    private var completedWarmup = false

    init() {
        recorder.levelHandler = { [weak self] level in
            DispatchQueue.main.async {
                self?.recordingLevel = level
            }
        }

        if TranscriptionProfile(rawValue: transcriptionProfile) == nil {
            transcriptionProfile = TranscriptionProfile.balanced.rawValue
        }
        let preferredHotkey = HotkeyManager.Hotkey.preferredSelection(from: hotkeyChoice)
        if preferredHotkey.rawValue != hotkeyChoice {
            hotkeyChoice = preferredHotkey.rawValue
        }

        // One-time migration: clean up legacy WhisperKit models and defaults
        migrateLegacyWhisperKit()

        Task { @MainActor [weak self] in
            guard let self, self.onboardingComplete else { return }
            self.start()
        }
    }

    /// Called by OnboardingView when the user finishes the wizard.
    func completeOnboarding() {
        rememberCompletedOnboardingForCurrentInstall()
        onboardingComplete = true
        start()
    }

    func prewarmTranscriber() {
        guard !completedWarmup else { return }
        guard transcriberWarmupTask == nil else { return }

        let activeTranscriber = ensureActiveTranscriber()
        let profile = resolvedTranscriptionProfile

        let currentHotwords = hotwords
        transcriberWarmupTask = Task { [weak self] in
            do {
                try await activeTranscriber.prepareForFirstTranscription(profile: profile, hotwords: currentHotwords)
            } catch {
                debugLog("[holdtotalk] Model pre-warm failed: \(error)")
                guard let self else { return }
                self.transcriberWarmupTask = nil
                return
            }

            guard let self else { return }
            self.completedWarmup = true
            self.transcriberWarmupTask = nil
            debugLog("[holdtotalk] Model pre-warm complete")
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        refreshPermissionSnapshot()
        if !hasPostEvent { pollPostEventPermission() }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshPermissionSnapshot()
            }
        }

        if !hasInputMonitoring {
            debugLog("[holdtotalk] Input Monitoring missing -- prompt deferred to onboarding/settings.")
        }
        if !hasPostEvent {
            debugLog("[holdtotalk] PostEvent (keyboard access) missing -- prompt deferred to onboarding/settings.")
        }

        recorder.prepare()

        debugLog("[holdtotalk] Permissions Mic=\(hasMicrophone), PostEvent=\(hasPostEvent), InputMon=\(hasInputMonitoring)")

        hotkeyManager.onPress = { [weak self] in
            DispatchQueue.main.async { self?.beginRecording() }
        }
        hotkeyManager.onRelease = { [weak self] in
            DispatchQueue.main.async {
                Task { await self?.endRecording() }
            }
        }
        hotkeyManager.update(hotkey: resolvedHotkey)
        hotkeyManager.start()

        hudBinding = Publishers.CombineLatest(
            $state.removeDuplicates(),
            $recordingLevel
        )
        .sink { state, level in
            RecordingHUD.shared.update(state, level: state == .recording ? CGFloat(level) : 0)
        }

        prewarmTranscriber()

        debugLog("[holdtotalk] Ready -- hold [\(hotkeyChoice)] to dictate.")
    }

    func stop() {
        hotkeyManager.stop()
        didStart = false
        axPollTask?.cancel()
        axPollTask = nil
        transcriberWarmupTask?.cancel()
        transcriberWarmupTask = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
        hudBinding?.cancel()
        hudBinding = nil
        recordingLevel = 0
    }

    func resetForFreshOnboarding() {
        stop()
        resetPersistedAppStateForFreshOnboarding()

        state = .idle
        lastRawText = ""
        lastCleanText = ""
        lastInsertDebug = ""
        lastError = nil
        recordingTargetAppPID = nil
        recordingTargetBundleID = nil
        transcriber = nil
        completedWarmup = false

        onboardingComplete = false
        UserDefaults.standard.set(0, forKey: onboardingStepDefaultsKey)
        transcriptionProfile = TranscriptionProfile.balanced.rawValue
        hotkeyChoice = HotkeyManager.Hotkey.ctrl.rawValue
        hasPromptedInputMonitoring = false
        textCleanupEnabled = TextCleanup.checkAvailability() == .available
        textCleanupPrompt = TextCleanup.defaultPrompt
        hotwords = ""

        modelManager.handleFreshOnboardingReset()
        refreshPermissionSnapshot()
    }

    func reloadHotkey() {
        hotkeyManager.update(hotkey: resolvedHotkey)
    }

    /// Invalidates the current transcriber so the next dictation recreates it with updated hotwords.
    func reloadTranscriber() {
        transcriber = nil
        completedWarmup = false
    }

    // MARK: - Pipeline

    private func beginRecording() {
        debugLog("[holdtotalk] beginRecording called, state=\(state)")
        guard state == .idle else { return }

        refreshPermissionSnapshot()
        if !hasPostEvent {
            debugLog("[holdtotalk] PostEvent (keyboard access) not granted -- text insertion will be blocked by macOS.")
        }
        if !hasInputMonitoring {
            debugLog("[holdtotalk] Input Monitoring not granted -- global hotkey may not trigger in other apps.")
        }

        recordingTargetAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        recordingTargetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        debugLog("[holdtotalk] Recording target: \(recordingTargetBundleID ?? "nil")")
        state = .recording
        recordingLevel = 0
        prewarmTranscriber()

        do {
            try recorder.start()
            debugLog("[holdtotalk] Microphone started")
        } catch {
            debugLog("[holdtotalk] Microphone failed to start: \(error)")
            lastError = error.localizedDescription
            state = .idle
            recordingLevel = 0
            recordingTargetAppPID = nil
            recordingTargetBundleID = nil
            return
        }
    }

    private func endRecording() async {
        guard state == .recording else { return }
        let audio = recorder.stop()
        recordingLevel = 0
        guard !audio.isEmpty else {
            state = .idle
            lastError = nil
            recordingTargetAppPID = nil
            recordingTargetBundleID = nil
            return
        }

        let duration = Double(audio.count) / 16000.0
        debugLog("[holdtotalk] Captured \(String(format: "%.1f", duration))s of audio")

        state = .transcribing
        let activeTranscriber = ensureActiveTranscriber()
        do {
            let transcribeStart = Date()
            let profile = resolvedTranscriptionProfile
            let currentHotwords = hotwords
            let raw = try await activeTranscriber.transcribe(audio, profile: profile, hotwords: currentHotwords)
            let transcribeTime = Date().timeIntervalSince(transcribeStart)
            debugLog("[holdtotalk] Transcribed \(String(format: "%.1f", duration))s audio in \(String(format: "%.2f", transcribeTime))s [\(profile.rawValue)]")
            guard !raw.isEmpty else {
                debugLog("[holdtotalk] (no speech detected)")
                state = .idle
                recordingTargetAppPID = nil
                recordingTargetBundleID = nil
                return
            }
            lastError = nil
            lastRawText = raw
            debugLogSensitive("[holdtotalk] Raw", text: raw)

            let finalText: String
            if textCleanupEnabled {
                let cleanupStart = Date()
                let cleaned = await TextCleanup.cleanup(raw, prompt: textCleanupPrompt)
                let cleanupTime = Date().timeIntervalSince(cleanupStart)
                let changed = cleaned != raw
                debugLog("[holdtotalk] Text cleanup \(changed ? "modified" : "unchanged") in \(String(format: "%.2f", cleanupTime))s")
                finalText = cleaned
            } else {
                finalText = raw
            }
            lastCleanText = finalText

            reactivateRecordingTargetAppIfNeeded()
            try? await Task.sleep(nanoseconds: 80_000_000)
            let insertText = finalText + " "
            let insertBundleID = recordingTargetBundleID
            let report = await Task.detached(priority: .userInitiated) {
                TextInserter.insert(
                    insertText,
                    targetBundleID: insertBundleID
                )
            }.value
            if report.success {
                lastInsertDebug = report.summary
                debugLog("[holdtotalk] Inserted via \(report.method ?? "unknown").")
            } else {
                lastInsertDebug = report.summary
                if let userFacingError = report.userFacingError {
                    lastError = userFacingError
                }
                debugLog("[holdtotalk] Insert unconfirmed. \(report.attempts.joined(separator: " | "))")
            }
        } catch {
            lastError = error.localizedDescription
            debugLog("[holdtotalk] Error: \(error)")
        }

        state = .idle
        recordingLevel = 0
        recordingTargetAppPID = nil
        recordingTargetBundleID = nil
    }

    private var resolvedHotkey: HotkeyManager.Hotkey {
        HotkeyManager.Hotkey.preferredSelection(from: hotkeyChoice)
    }

    private func ensureActiveTranscriber() -> Transcriber {
        if transcriber == nil {
            transcriber = Transcriber()
        }
        return transcriber!
    }

    private var resolvedTranscriptionProfile: TranscriptionProfile {
        TranscriptionProfile(rawValue: transcriptionProfile) ?? .balanced
    }

    /// Polls until PostEvent (keyboard access) is granted so the UI updates live.
    private func pollPostEventPermission() {
        axPollTask = Task { @MainActor in
            do {
                while !checkPostEventAccess() {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            } catch {
                return
            }
            hasPostEvent = true
            print("[holdtotalk] PostEvent (keyboard access) permission granted.")
        }
    }

    private func reactivateRecordingTargetAppIfNeeded() {
        guard let pid = recordingTargetAppPID else { return }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        app.activate()
    }

    /// Reads current macOS permission state into the engine's published properties.
    func refreshPermissionSnapshot() {
        #if DEBUG
        if DebugFlags.skipPermissions {
                hasMicrophone = true
            hasPostEvent = true
            hasInputMonitoring = true
            return
        }
        #endif
        hasMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        hasPostEvent = checkPostEventAccess()
        hasInputMonitoring = CGPreflightListenEventAccess()
    }

    // MARK: - Legacy Migration

    private func migrateLegacyWhisperKit() {
        let defaults = UserDefaults.standard
        // Clear legacy whisperModel key
        if defaults.string(forKey: whisperModelDefaultsKey) != nil {
            defaults.removeObject(forKey: whisperModelDefaultsKey)
        }
        // Clean up old WhisperKit model files
        modelManager.cleanupLegacyWhisperKitModels()
    }
}
