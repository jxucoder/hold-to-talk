import WhisperKit

/// Local speech-to-text via WhisperKit (Core ML accelerated on Apple Silicon).
final class Transcriber {
    private var whisper: WhisperKit?
    let modelSize: String

    init(modelSize: String = "small.en") {
        self.modelSize = modelSize
    }

    /// Lazily loads the model on first call.
    func loadModel() async throws {
        guard whisper == nil else { return }
        print("[transcriber] Loading \(modelSize)…")
        whisper = try await WhisperKit(model: modelSize)
        print("[transcriber] Ready.")
    }

    /// Transcribe 16 kHz mono float audio → text.
    func transcribe(_ audio: [Float]) async throws -> String {
        if whisper == nil { try await loadModel() }
        guard let whisper, !audio.isEmpty else { return "" }

        let results = try await whisper.transcribe(audioArray: audio)
        return results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
