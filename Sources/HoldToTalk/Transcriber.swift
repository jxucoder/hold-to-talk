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
    private var loadTask: Task<WhisperKit, Error>?
    private var decodeWarmupTask: Task<Void, Error>?
    private var hasCompletedDecodeWarmup = false
    let modelSize: String

    init(modelSize: String = "small.en") {
        self.modelSize = modelSize
    }

    func loadModel() async throws {
        guard whisper == nil else { return }

        if let loadTask {
            whisper = try await loadTask.value
            return
        }

        print("[transcriber] Loading \(modelSize)…")
        let modelSize = self.modelSize
        let task = Task {
            try await WhisperKit(
                model: modelSize,
                downloadBase: ModelManager.modelBase,
                verbose: false,
                prewarm: true,
                load: true
            )
        }
        loadTask = task
        defer { loadTask = nil }

        whisper = try await task.value
        print("[transcriber] Ready.")
    }

    func prepareForFirstTranscription(profile: TranscriptionProfile = .balanced) async throws {
        if hasCompletedDecodeWarmup {
            return
        }

        if let decodeWarmupTask {
            try await decodeWarmupTask.value
            return
        }

        let task = Task { [self] in
            try await runDecodeWarmup(profile: profile)
        }
        decodeWarmupTask = task
        defer { decodeWarmupTask = nil }

        try await task.value
        hasCompletedDecodeWarmup = true
        print("[transcriber] Decode warm-up complete.")
    }

    /// Transcribe 16 kHz mono float audio → text.
    func transcribe(_ audio: [Float], profile: TranscriptionProfile = .balanced) async throws -> String {
        if let decodeWarmupTask {
            try await decodeWarmupTask.value
        } else if whisper == nil {
            try await loadModel()
        }
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

    private func runDecodeWarmup(profile: TranscriptionProfile) async throws {
        try await loadModel()
        guard let whisper, !hasCompletedDecodeWarmup else { return }

        print("[transcriber] Running decode warm-up…")
        let silence = Array(repeating: Float(0), count: Int(WhisperKit.sampleRate))
        let options = decodingOptions(forDuration: 1.0, profile: profile)
        _ = try await whisper.transcribe(audioArray: silence, decodeOptions: options)
    }
}
