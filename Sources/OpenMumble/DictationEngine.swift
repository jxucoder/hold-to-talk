import SwiftUI
import ApplicationServices
import AppKit
import Combine

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
    @Published var hasAccessibility: Bool = {
        #if DEBUG
        if DebugFlags.skipPermissions { return true }
        #endif
        return AXIsProcessTrusted()
    }()

    @AppStorage("onboardingComplete") var onboardingComplete = false
    @AppStorage("whisperModel") var whisperModel = "large-v3-turbo"
    @AppStorage("cleanupEnabled") var cleanupEnabled = true
    @AppStorage("cleanupPrompt") var cleanupPrompt = TextProcessor.defaultPrompt
    @AppStorage("hotkeyChoice") var hotkeyChoice = "ctrl"
    @AppStorage("hasPromptedInputMonitoring") private var hasPromptedInputMonitoring = false

    private let recorder = AudioRecorder()
    private var transcriber: Transcriber?
    private let hotkeyManager = HotkeyManager()
    let modelManager = ModelManager()
    private var didStart = false
    private var recordingTargetAppPID: pid_t?
    private var recordingTargetBundleID: String?
    // Fix #14: keep a handle on the AX poll task so stop() can cancel it
    private var axPollTask: Task<Void, Never>?

    init() {
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

    func start() {
        guard !didStart else { return }
        didStart = true

        #if DEBUG
        if DebugFlags.skipPermissions {
            hasAccessibility = true
        } else {
            hasAccessibility = AXIsProcessTrusted()
            if !hasAccessibility { pollAccessibilityPermission() }
        }
        #else
        hasAccessibility = AXIsProcessTrusted()
        if !hasAccessibility {
            pollAccessibilityPermission()
        }
        #endif

        // Request Input Monitoring if not already granted and not yet prompted
        // (onboarding may have already triggered the system dialog)
        if !CGPreflightListenEventAccess() && !hasPromptedInputMonitoring {
            debugLog("[openmumble] Requesting Input Monitoring access…")
            _ = CGRequestListenEventAccess()
            hasPromptedInputMonitoring = true
        }

        // Prompt for Accessibility if not trusted (shows system dialog)
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }

        // Pre-warm the audio engine so start() is near-instant on first hotkey press
        recorder.prepare()

        debugLog("[openmumble] AX=\(AXIsProcessTrusted()), InputMon=\(CGPreflightListenEventAccess())")

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

        Task.detached { [weak self, whisperModel] in
            guard let self else { return }
            let t = Transcriber(modelSize: whisperModel)
            do {
                try await t.loadModel()
                await MainActor.run { self.transcriber = t }
            } catch {
                print("[openmumble] Model pre-warm failed: \(error)")
            }
        }

        debugLog("[openmumble] Ready — hold [\(hotkeyChoice)] to dictate.")
    }

    func stop() {
        hotkeyManager.stop()
        // Fix #14: cancel accessibility poll when the engine stops
        axPollTask?.cancel()
        axPollTask = nil
        // Fix #3: cancel HUD subscription to prevent leaks on re-creation
        hudBinding?.cancel()
        hudBinding = nil
    }

    func reloadHotkey() {
        hotkeyManager.update(hotkey: resolvedHotkey)
    }

    // MARK: - Pipeline

    private func beginRecording() {
        debugLog("[openmumble] beginRecording called, state=\(state)")
        guard state == .idle else { return }

        #if DEBUG
        if !DebugFlags.skipPermissions {
            hasAccessibility = AXIsProcessTrusted()
        }
        #else
        hasAccessibility = AXIsProcessTrusted()
        #endif
        if !hasAccessibility {
            debugLog("[openmumble] ⚠ Accessibility not granted — text insertion will be blocked by macOS.")
        }

        recordingTargetAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        recordingTargetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        debugLog("[openmumble] Recording target: \(recordingTargetBundleID ?? "nil")")
        state = .recording

        // Fix #9: report microphone errors to the user instead of swallowing them
        do {
            try recorder.start()
            debugLog("[openmumble] Microphone started")
        } catch {
            debugLog("[openmumble] ⚠ Microphone failed to start: \(error)")
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
        debugLog("[openmumble] Captured \(String(format: "%.1f", duration))s of audio")

        // Transcribe
        state = .transcribing
        // Rebuild transcriber if model changed
        let currentModelSize = transcriber?.modelSize
        if currentModelSize != whisperModel {
            transcriber = Transcriber(modelSize: whisperModel)
        }
        guard let activeTranscriber = transcriber else {
            debugLog("[openmumble] ⚠ Transcriber not ready — skipping.")
            lastError = "Transcriber not ready"
            state = .idle
            recordingTargetAppPID = nil
            recordingTargetBundleID = nil
            return
        }
        do {
            let raw = try await activeTranscriber.transcribe(audio)
            guard !raw.isEmpty else {
                debugLog("[openmumble] (no speech detected)")
                state = .idle
                // Fix #10: clear stale target info on early return
                recordingTargetAppPID = nil
                recordingTargetBundleID = nil
                return
            }
            lastError = nil  // clear any previous error on success
            lastRawText = raw
            debugLog("[openmumble] Raw: \(raw)")

            var finalText = raw
            if cleanupEnabled {
                state = .cleaning
                let cleaned = try await TextProcessor(prompt: cleanupPrompt).cleanup(raw)
                if cleaned != raw {
                    debugLog("[openmumble] Cleaned: \(cleaned)")
                    finalText = cleaned
                }
            }
            lastCleanText = finalText

            // Reactivate the target app and give it a brief moment to focus.
            // 80ms is sufficient for app activation; reduced from 180ms for snappier feel.
            reactivateRecordingTargetAppIfNeeded()
            try? await Task.sleep(nanoseconds: 80_000_000)
            let report = TextInserter.insert(
                finalText + " ",
                targetBundleID: recordingTargetBundleID,
                targetPID: recordingTargetAppPID
            )
            if report.success {
                lastInsertDebug = report.summary
                debugLog("[openmumble] Inserted via \(report.method ?? "unknown").")
            } else {
                lastInsertDebug = report.summary
                debugLog("[openmumble] Insert unconfirmed. \(report.attempts.joined(separator: " | "))")
            }
        } catch {
            lastError = error.localizedDescription
            debugLog("[openmumble] Error: \(error)")
        }

        state = .idle
        recordingTargetAppPID = nil
        recordingTargetBundleID = nil
    }

    private var resolvedHotkey: HotkeyManager.Hotkey {
        HotkeyManager.Hotkey(rawValue: hotkeyChoice) ?? .ctrl
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
            print("[openmumble] Accessibility permission granted.")
        }
    }

    private func reactivateRecordingTargetAppIfNeeded() {
        guard let pid = recordingTargetAppPID else { return }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        app.activate()
    }
}
