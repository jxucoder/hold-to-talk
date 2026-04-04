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
            return "Fastest transcription with minimal post-processing."
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
        let joined = results
            .compactMap { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.deduplicateRepeatedPhrases(joined)
    }

    /// Tunes decode strategy per profile with duration-aware chunking.
    private func decodingOptions(forDuration durationSeconds: Double, profile: TranscriptionProfile) -> DecodingOptions {
        let cores = max(2, ProcessInfo.processInfo.activeProcessorCount)
        let fallbackCount: Int
        let workerCount: Int
        let chunkingThresholdSeconds: Double

        switch profile {
        case .fast:
            fallbackCount = 2
            workerCount = min(12, cores)
            chunkingThresholdSeconds = 12
        case .balanced:
            fallbackCount = 2
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

    /// Removes repeated phrases that Whisper sometimes hallucinates.
    ///
    /// **Pass 1** splits on sentence-ending punctuation (`.` `!` `?`) and removes
    /// consecutive duplicate clauses. Comparison ignores trailing punctuation and
    /// whitespace so `"I love dogs. I love dogs"` is still caught.
    ///
    /// **Pass 2** collapses runs of 3+ identical consecutive words into one,
    /// preserving legitimate pairs like "that that" or "had had".
    static func deduplicateRepeatedPhrases(_ text: String) -> String {
        guard !text.isEmpty else { return text }

        // --- Pass 1: sentence-level dedup (splits on . ! ?) ---
        let sentenceDelimiters: Set<Character> = [".", "!", "?"]
        let sentences: [String] = {
            var result: [String] = []
            var search = text.startIndex
            while search < text.endIndex {
                if let delimIdx = text[search...].firstIndex(where: { sentenceDelimiters.contains($0) }) {
                    let end = text.index(after: delimIdx)
                    var trailing = end
                    while trailing < text.endIndex && text[trailing].isWhitespace {
                        trailing = text.index(after: trailing)
                    }
                    result.append(String(text[search..<trailing]))
                    search = trailing
                } else {
                    result.append(String(text[search...]))
                    break
                }
            }
            return result
        }()

        var deduped: [String] = []
        for sentence in sentences {
            // Strip punctuation and whitespace for comparison so
            // "I love dogs." and "I love dogs" are treated as equal.
            let normalized = sentence
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: .punctuationCharacters)
                .lowercased()
            if let last = deduped.last {
                let lastNormalized = last
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: .punctuationCharacters)
                    .lowercased()
                if lastNormalized == normalized { continue }
            }
            deduped.append(sentence)
        }
        var result = deduped.joined()

        // --- Pass 2: collapse runs of 3+ identical consecutive words ---
        // Keeps legitimate pairs like "that that" or "had had" intact.
        let words = result.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 2 else { return result.trimmingCharacters(in: .whitespacesAndNewlines) }

        var dedupedWords: [String] = []
        var runCount = 1
        for i in 1...words.count {
            let prev = words[i - 1]
            let curr = i < words.count ? words[i] : nil
            if let curr, curr.lowercased() == prev.lowercased() {
                runCount += 1
            } else {
                dedupedWords.append(prev)
                if runCount == 2 {
                    dedupedWords.append(prev)
                }
                runCount = 1
            }
        }
        result = dedupedWords.joined(separator: " ")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
