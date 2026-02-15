import SwiftUI

/// Orchestrates the record → transcribe → cleanup → paste pipeline.
@MainActor
final class DictationEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case cleaning
    }

    @Published var state: State = .idle
    @Published var lastRawText: String = ""
    @Published var lastCleanText: String = ""

    @AppStorage("whisperModel") var whisperModel = "large-v3"
    @AppStorage("cleanupEnabled") var cleanupEnabled = true
    @AppStorage("cleanupProvider") var cleanupProvider = "claude"
    @AppStorage("claudeApiKey") var claudeApiKey = ""
    @AppStorage("claudeModel") var claudeModel = "claude-sonnet-4-20250514"
    @AppStorage("openaiApiKey") var openaiApiKey = ""
    @AppStorage("openaiModel") var openaiModel = "gpt-4o-mini"
    @AppStorage("hotkeyChoice") var hotkeyChoice = "ctrl"

    private let recorder = AudioRecorder()
    private var transcriber: Transcriber?
    private let hotkeyManager = HotkeyManager()

    func start() {
        hotkeyManager.onPress = { [weak self] in
            Task { @MainActor in self?.beginRecording() }
        }
        hotkeyManager.onRelease = { [weak self] in
            Task { @MainActor in await self?.endRecording() }
        }
        hotkeyManager.update(hotkey: resolvedHotkey)
        hotkeyManager.start()

        // Pre-warm Whisper model
        Task.detached { [whisperModel] in
            let t = Transcriber(modelSize: whisperModel)
            try? await t.loadModel()
            await MainActor.run { self.transcriber = t }
        }

        print("[openmumble] Ready — hold [\(hotkeyChoice)] to dictate.")
    }

    func stop() {
        hotkeyManager.stop()
    }

    func reloadHotkey() {
        hotkeyManager.update(hotkey: resolvedHotkey)
    }

    /// The active API key for the selected provider, if any.
    var activeApiKey: String {
        switch TextProcessor.Provider(rawValue: cleanupProvider) {
        case .claude:  return claudeApiKey
        case .openai:  return openaiApiKey
        case .none:    return ""
        }
    }

    // MARK: - Pipeline

    private func beginRecording() {
        guard state == .idle else { return }
        state = .recording
        try? recorder.start()
    }

    private func endRecording() async {
        guard state == .recording else { return }
        let audio = recorder.stop()
        guard !audio.isEmpty else {
            state = .idle
            return
        }

        let duration = Double(audio.count) / 16000.0
        print("[openmumble] Captured \(String(format: "%.1f", duration))s")

        // Transcribe
        state = .transcribing
        if transcriber == nil || transcriber?.modelSize != whisperModel {
            transcriber = Transcriber(modelSize: whisperModel)
        }
        do {
            let raw = try await transcriber!.transcribe(audio)
            guard !raw.isEmpty else {
                print("[openmumble] (no speech detected)")
                state = .idle
                return
            }
            lastRawText = raw
            print("[openmumble] Raw: \(raw)")

            // Cleanup
            var final = raw
            let provider = TextProcessor.Provider(rawValue: cleanupProvider) ?? .claude
            let key = activeApiKey
            if cleanupEnabled && !key.isEmpty {
                state = .cleaning
                let model = provider == .claude ? claudeModel : openaiModel
                let processor = TextProcessor(provider: provider, apiKey: key, model: model)
                let cleaned = try await processor.cleanup(raw)
                if cleaned != raw {
                    print("[openmumble] Cleaned: \(cleaned)")
                    final = cleaned
                }
            }
            lastCleanText = final

            // Insert
            TextInserter.insert(final)
            print("[openmumble] Inserted.")
        } catch {
            print("[openmumble] Error: \(error)")
        }

        state = .idle
    }

    private var resolvedHotkey: HotkeyManager.Hotkey {
        HotkeyManager.Hotkey(rawValue: hotkeyChoice) ?? .ctrl
    }
}
