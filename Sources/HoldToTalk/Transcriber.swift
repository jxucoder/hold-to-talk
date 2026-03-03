import Foundation
import WhisperKit

enum TranscriptionProfile: String, CaseIterable, Identifiable {
    case fast
    case balanced
    case best

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fast: return "Fast"
        case .balanced: return "Balanced"
        case .best: return "Best Quality"
        }
    }

    var summary: String {
        switch self {
        case .fast:
            return "Lowest latency for long dictation."
        case .balanced:
            return "Recommended default for speed and quality."
        case .best:
            return "Higher accuracy with slower transcription."
        }
    }
}

/// Local speech-to-text via WhisperKit (Core ML accelerated on Apple Silicon).
/// Actor isolation eliminates data races on the mutable `whisper` property.
actor Transcriber {
    private var whisper: WhisperKit?
    let modelSize: String

    init(modelSize: String = "small.en") {
        self.modelSize = modelSize
    }

    func loadModel() async throws {
        guard whisper == nil else { return }
        print("[transcriber] Loading \(modelSize)…")
        whisper = try await WhisperKit(model: modelSize, downloadBase: ModelManager.modelBase)
        print("[transcriber] Ready.")
    }

    /// Transcribe 16 kHz mono float audio → text.
    func transcribe(_ audio: [Float], profile: TranscriptionProfile = .balanced) async throws -> String {
        if whisper == nil { try await loadModel() }
        guard let whisper, !audio.isEmpty else { return "" }

        let durationSeconds = Double(audio.count) / Double(WhisperKit.sampleRate)
        let options = decodingOptions(forDuration: durationSeconds, profile: profile)
        let results = try await whisper.transcribe(audioArray: audio, decodeOptions: options)
        return results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tunes decode strategy per profile with duration-aware chunking.
    private func decodingOptions(forDuration durationSeconds: Double, profile: TranscriptionProfile) -> DecodingOptions {
        let cores = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let fallbackCount: Int
        let workerCount: Int
        let chunkingThresholdSeconds: Double

        switch profile {
        case .fast:
            fallbackCount = 0
            workerCount = min(12, cores)
            chunkingThresholdSeconds = 12
        case .balanced:
            fallbackCount = durationSeconds >= 20 ? 0 : 2
            workerCount = max(2, min(cores / 2, 8))
            chunkingThresholdSeconds = 25
        case .best:
            fallbackCount = 4
            workerCount = max(2, min(cores / 2, 6))
            chunkingThresholdSeconds = 40
        }
        let chunking: ChunkingStrategy? = durationSeconds >= chunkingThresholdSeconds ? .vad : nil

        return DecodingOptions(
            temperatureFallbackCount: fallbackCount,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            concurrentWorkerCount: workerCount,
            chunkingStrategy: chunking
        )
    }
}
