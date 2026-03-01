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

    private let recorder = AudioRecorder()
    private var transcriber: Transcriber?
    private let hotkeyManager = HotkeyManager()
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

        hotkeyManager.onPress = { [weak self] in
            Task { @MainActor in self?.beginRecording() }
        }
        hotkeyManager.onRelease = { [weak self] in
            Task { @MainActor in await self?.endRecording() }
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

        print("[openmumble] Ready — hold [\(hotkeyChoice)] to dictate.")
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
        guard state == .idle else { return }

        #if DEBUG
        if !DebugFlags.skipPermissions {
            hasAccessibility = AXIsProcessTrusted()
        }
        #else
        hasAccessibility = AXIsProcessTrusted()
        #endif
        if !hasAccessibility {
            print("[openmumble] ⚠ Accessibility not granted — text insertion will be blocked by macOS.")
            print("[openmumble]   Go to System Settings → Privacy & Security → Accessibility and add OpenMumble.")
        }

        recordingTargetAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        recordingTargetBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        state = .recording

        // Fix #9: report microphone errors to the user instead of swallowing them
        do {
            try recorder.start()
        } catch {
            print("[openmumble] ⚠ Microphone failed to start: \(error)")
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
            // Fix #10: clear stale target info on early return
            recordingTargetAppPID = nil
            recordingTargetBundleID = nil
            return
        }

        let duration = Double(audio.count) / 16000.0
        print("[openmumble] Captured \(String(format: "%.1f", duration))s")

        // Transcribe
        state = .transcribing
        // Rebuild transcriber if model changed
        let currentModelSize = transcriber?.modelSize
        if currentModelSize != whisperModel {
            transcriber = Transcriber(modelSize: whisperModel)
        }
        guard let activeTranscriber = transcriber else {
            print("[openmumble] ⚠ Transcriber not ready — skipping.")
            lastError = "Transcriber not ready"
            state = .idle
            recordingTargetAppPID = nil
            recordingTargetBundleID = nil
            return
        }
        do {
            let raw = try await activeTranscriber.transcribe(audio)
            guard !raw.isEmpty else {
                print("[openmumble] (no speech detected)")
                state = .idle
                // Fix #10: clear stale target info on early return
                recordingTargetAppPID = nil
                recordingTargetBundleID = nil
                return
            }
            lastError = nil  // clear any previous error on success
            lastRawText = raw
            print("[openmumble] Raw: \(raw)")

            var final = raw
            if cleanupEnabled {
                state = .cleaning
                let cleaned = try await TextProcessor(prompt: cleanupPrompt).cleanup(raw)
                if cleaned != raw {
                    print("[openmumble] Cleaned: \(cleaned)")
                    final = cleaned
                }
            }
            lastCleanText = final

            // Note: TextInserter.insert must run on the main thread — NSPasteboard, AX API,
            // and CGEvent posting are all main-thread-only. The brief usleep in clipboard
            // paste (~200ms) is acceptable compared to broken insertion.
            reactivateRecordingTargetAppIfNeeded()
            try? await Task.sleep(nanoseconds: 180_000_000)
            let report = TextInserter.insert(
                final + " ",
                targetBundleID: recordingTargetBundleID,
                targetPID: recordingTargetAppPID
            )
            if report.success {
                lastInsertDebug = report.summary
                print("[openmumble] Inserted via \(report.method ?? "unknown").")
            } else {
                lastInsertDebug = report.summary
                print("[openmumble] Insert unconfirmed. \(report.attempts.joined(separator: " | "))")
            }
        } catch {
            lastError = error.localizedDescription
            print("[openmumble] Error: \(error)")
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
        _ = app.activate(options: [.activateAllWindows])
    }
}
