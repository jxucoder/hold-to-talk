import SwiftUI
import ApplicationServices
import AppKit
import Combine
import AVFoundation

/// Orchestrates the record → transcribe → cleanup → insert pipeline.
@MainActor
final class DictationEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case cleaning

        var label: String {
            switch self {
            case .idle:         "Ready"
            case .recording:    "Recording…"
            case .transcribing: "Transcribing…"
            case .cleaning:     "Cleaning…"
            }
        }

        var icon: String {
            switch self {
            case .idle:         "mic"
            case .recording:    "mic.fill"
            case .transcribing: "bubble.left"
            case .cleaning:     "sparkles"
            }
        }

        var color: Color {
            switch self {
            case .idle:         .green
            case .recording:    .red
            case .transcribing: .orange
            case .cleaning:     .blue
            }
        }
    }

    @Published var state: State = .idle
    private var hudBinding: AnyCancellable?
    @Published var lastRawText: String = ""
    @Published var lastCleanText: String = ""
    @Published var lastInsertDebug: String = ""
    /// Brief user-visible error message; cleared on next successful dictation.
    @Published var lastError: String?
    @Published var hasMicrophone: Bool = {
        #if DEBUG
        if DebugFlags.skipPermissions { return true }
        #endif
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }()
    @Published var hasAccessibility: Bool = {
        #if DEBUG
        if DebugFlags.skipPermissions { return true }
        #endif
        return AXIsProcessTrusted()
    }()
    @Published var hasInputMonitoring: Bool = {
        #if DEBUG
        if DebugFlags.skipPermissions { return true }
        #endif
        return CGPreflightListenEventAccess()
    }()

    @AppStorage("onboardingComplete") var onboardingComplete = false
    @AppStorage("whisperModel") var whisperModel = WhisperModelInfo.defaultModelID
    @AppStorage("transcriptionProfile") var transcriptionProfile = TranscriptionProfile.balanced.rawValue
    @AppStorage("cleanupEnabled") var cleanupEnabled = true
    @AppStorage("cleanupPrompt") var cleanupPrompt = TextProcessor.defaultPrompt
    @AppStorage("hotkeyChoice") var hotkeyChoice = "ctrl"
    @AppStorage("hasPromptedInputMonitoring") private var hasPromptedInputMonitoring = false

    let availableWhisperModels: [WhisperModelInfo]
    let recommendedWhisperModelID: String

    private let recorder = AudioRecorder()
    private var transcriber: Transcriber?
    private let hotkeyManager = HotkeyManager()
    let modelManager = ModelManager()
    private var didStart = false
    private var recordingTargetAppPID: pid_t?
    private var recordingTargetBundleID: String?
    // Fix #14: keep a handle on the AX poll task so stop() can cancel it
    private var axPollTask: Task<Void, Never>?
    private var activationObserver: NSObjectProtocol?
    private var transcriberWarmupTask: Task<Void, Never>?

    init() {
        let profile = WhisperModelInfo.deviceModelProfile()
        availableWhisperModels = profile.available
        recommendedWhisperModelID = profile.recommendedID

        // Migrate legacy IDs and guarantee current selection is device-supported.
        if let stored = UserDefaults.standard.string(forKey: "whisperModel") {
            let normalized = WhisperModelInfo.normalizeModelID(stored)
            whisperModel = availableWhisperModels.contains(where: { $0.id == normalized })
                ? normalized
                : recommendedWhisperModelID
        } else {
            whisperModel = recommendedWhisperModelID
        }
        if TranscriptionProfile(rawValue: transcriptionProfile) == nil {
            transcriptionProfile = TranscriptionProfile.balanced.rawValue
        }
        let preferredHotkey = HotkeyManager.Hotkey.preferredSelection(from: hotkeyChoice)
        if preferredHotkey.rawValue != hotkeyChoice {
            hotkeyChoice = preferredHotkey.rawValue
        }

        Task { @MainActor [weak self] in
            guard let self, self.onboardingComplete else { return }
            self.start()
        }
    }

    /// Called by OnboardingView when the user finishes the wizard.
    func completeOnboarding() {
        onboardingComplete = true
        start()
    }

    func prewarmTranscriber() {
        let activeTranscriber = ensureActiveTranscriber()
        let modelSize = activeTranscriber.modelSize
        let profile = resolvedTranscriptionProfile
        transcriberWarmupTask?.cancel()
        transcriberWarmupTask = Task { [weak self] in
            do {
                try await activeTranscriber.prepareForFirstTranscription(profile: profile)
            } catch {
                print("[holdtotalk] Model pre-warm failed: \(error)")
                guard let self else { return }
                if self.transcriber?.modelSize == modelSize {
                    self.transcriberWarmupTask = nil
                }
                return
            }

            guard let self else { return }
            if self.transcriber?.modelSize == modelSize {
                self.transcriberWarmupTask = nil
            }
        }
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        refreshPermissionSnapshot()
        if !hasAccessibility { pollAccessibilityPermission() }

        // Immediately re-check accessibility when the user switches back to the app
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

        // Do not auto-prompt privacy dialogs on startup.
        // Onboarding/Settings handle explicit prompt sequencing to avoid stacked macOS dialogs.
        if !hasInputMonitoring {
            debugLog("[holdtotalk] Input Monitoring missing — prompt deferred to onboarding/settings.")
        }
        if !hasAccessibility {
            debugLog("[holdtotalk] Accessibility missing — prompt deferred to onboarding/settings.")
        }

        // Pre-warm the audio engine so start() is near-instant on first hotkey press
        recorder.prepare()

        debugLog("[holdtotalk] Permissions Mic=\(hasMicrophone), AX=\(hasAccessibility), InputMon=\(hasInputMonitoring)")

        // Use DispatchQueue.main.async instead of Task { @MainActor in } for lower-latency dispatch
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

        hudBinding = $state
            .removeDuplicates()
            .sink { RecordingHUD.shared.update($0) }

        prewarmTranscriber()

        debugLog("[holdtotalk] Ready — hold [\(hotkeyChoice)] to dictate.")
    }

    func stop() {
        hotkeyManager.stop()
        // Fix #14: cancel accessibility poll when the engine stops
        axPollTask?.cancel()
        axPollTask = nil
        transcriberWarmupTask?.cancel()
        transcriberWarmupTask = nil
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
        // Fix #3: cancel HUD subscription to prevent leaks on re-creation
        hudBinding?.cancel()
        hudBinding = nil
    }

    func reloadHotkey() {
        hotkeyManager.update(hotkey: resolvedHotkey)
    }

    // MARK: - Pipeline

    private func beginRecording() {
        debugLog("[holdtotalk] beginRecording called, state=\(state)")
        guard state == .idle else { return }

        refreshPermissionSnapshot()
        if !hasAccessibility {
            debugLog("[holdtotalk] ⚠ Accessibility not granted — text insertion will be blocked by macOS.")
        }
        if !hasInputMonitoring {
            debugLog("[holdtotalk] ⚠ Input Monitoring not granted — global hotkey may not trigger in other apps.")
        }

        recordingTargetAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        recordingTargetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        debugLog("[holdtotalk] Recording target: \(recordingTargetBundleID ?? "nil")")
        state = .recording

        // Fix #9: report microphone errors to the user instead of swallowing them
        do {
            try recorder.start()
            debugLog("[holdtotalk] Microphone started")
        } catch {
            debugLog("[holdtotalk] ⚠ Microphone failed to start: \(error)")
            lastError = error.localizedDescription
            state = .idle
            recordingTargetAppPID = nil
            recordingTargetBundleID = nil
            return
        }
    }

    private func endRecording() async {
        guard state == .recording else { return }
        let audio = recorder.stop()
        guard !audio.isEmpty else {
            state = .idle
            lastError = nil
            // Fix #10: clear stale target info on early return
            recordingTargetAppPID = nil
            recordingTargetBundleID = nil
            return
        }

        let duration = Double(audio.count) / 16000.0
        debugLog("[holdtotalk] Captured \(String(format: "%.1f", duration))s of audio")

        // Transcribe
        state = .transcribing
        // Rebuild transcriber if model changed
        let activeTranscriber = ensureActiveTranscriber()
        do {
            let transcribeStart = Date()
            let profile = resolvedTranscriptionProfile
            let raw = try await activeTranscriber.transcribe(audio, profile: profile)
            let transcribeTime = Date().timeIntervalSince(transcribeStart)
            debugLog("[holdtotalk] Transcribed \(String(format: "%.1f", duration))s audio in \(String(format: "%.2f", transcribeTime))s [\(profile.rawValue)]")
            guard !raw.isEmpty else {
                debugLog("[holdtotalk] (no speech detected)")
                state = .idle
                // Fix #10: clear stale target info on early return
                recordingTargetAppPID = nil
                recordingTargetBundleID = nil
                return
            }
            lastError = nil  // clear any previous error on success
            lastRawText = raw
            debugLog("[holdtotalk] Raw: \(raw)")

            var finalText = raw
            // Only enter .cleaning state when Apple Intelligence is actually available;
            // otherwise cleanup() is a no-op and the state flash is misleading.
            if cleanupEnabled && TextProcessor.isAvailable {
                state = .cleaning
                let cleaned = try await TextProcessor(prompt: cleanupPrompt).cleanup(raw)
                if cleaned != raw {
                    debugLog("[holdtotalk] Cleaned: \(cleaned)")
                    finalText = cleaned
                }
            }
            lastCleanText = finalText

            // Reactivate the target app and give it a brief moment to focus.
            // 80ms is sufficient for app activation; reduced from 180ms for snappier feel.
            reactivateRecordingTargetAppIfNeeded()
            try? await Task.sleep(nanoseconds: 80_000_000)
            // Capture target info into locals before the async gap so the stored properties
            // can be cleared at the end of this function without a race.
            let insertText = finalText + " "
            let insertBundleID = recordingTargetBundleID
            let insertPID = recordingTargetAppPID
            // TextInserter.insert() is synchronous and may call usleep() per character in typing
            // profiles (e.g. 2ms × 3000 chars ≈ 6s for long dictation in Cursor/Slack/VSCode).
            // Run it off the main actor so the HUD and all animations remain responsive.
            let report = await Task.detached(priority: .userInitiated) {
                TextInserter.insert(
                    insertText,
                    targetBundleID: insertBundleID,
                    targetPID: insertPID
                )
            }.value
            if report.success {
                lastInsertDebug = report.summary
                debugLog("[holdtotalk] Inserted via \(report.method ?? "unknown").")
            } else {
                lastInsertDebug = report.summary
                debugLog("[holdtotalk] Insert unconfirmed. \(report.attempts.joined(separator: " | "))")
            }
        } catch {
            lastError = error.localizedDescription
            debugLog("[holdtotalk] Error: \(error)")
        }

        state = .idle
        recordingTargetAppPID = nil
        recordingTargetBundleID = nil
    }

    private var resolvedHotkey: HotkeyManager.Hotkey {
        HotkeyManager.Hotkey.preferredSelection(from: hotkeyChoice)
    }

    private func ensureActiveTranscriber() -> Transcriber {
        if transcriber?.modelSize != whisperModel {
            transcriber = Transcriber(modelSize: whisperModel)
        }
        return transcriber!
    }

    private var resolvedTranscriptionProfile: TranscriptionProfile {
        TranscriptionProfile(rawValue: transcriptionProfile) ?? .balanced
    }

    /// Polls until Accessibility is granted so the UI updates live.
    /// Fix #14: stored so stop() can cancel it; uses try await (not try?) so it respects cancellation.
    private func pollAccessibilityPermission() {
        axPollTask = Task { @MainActor in
            do {
                while !AXIsProcessTrusted() {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            } catch {
                return  // Task was cancelled — exit cleanly
            }
            hasAccessibility = true
            print("[holdtotalk] Accessibility permission granted.")
        }
    }

    private func reactivateRecordingTargetAppIfNeeded() {
        guard let pid = recordingTargetAppPID else { return }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        app.activate()
    }

    /// Reads current macOS permission state into the engine's published properties.
    /// Internal so views can call this directly instead of duplicating the logic.
    func refreshPermissionSnapshot() {
        #if DEBUG
        if DebugFlags.skipPermissions {
            hasMicrophone = true
            hasAccessibility = true
            hasInputMonitoring = true
            return
        }
        #endif
        hasMicrophone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        hasAccessibility = AXIsProcessTrusted()
        hasInputMonitoring = CGPreflightListenEventAccess()
    }
}
