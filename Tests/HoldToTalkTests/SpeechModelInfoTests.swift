import Testing
@testable import HoldToTalk

@Suite("SpeechModelInfo Tests")
struct SpeechModelInfoTests {
    @Test("Model info constants are populated")
    func modelInfoConstants() {
        #expect(!SpeechModelInfo.id.isEmpty)
        #expect(!SpeechModelInfo.displayName.isEmpty)
        #expect(!SpeechModelInfo.sizeLabel.isEmpty)
        #expect(SpeechModelInfo.englishOnly == true)
    }

    @Test("Download URL points to GitHub releases")
    func downloadURL() {
        let url = SpeechModelInfo.downloadURL
        #expect(url.host()?.contains("github.com") == true)
        #expect(url.absoluteString.contains("sherpa-onnx"))
    }

    @Test("Trust and provenance URLs are valid")
    func provenanceURLs() {
        #expect(SpeechModelInfo.parakeetURL.absoluteString.contains("huggingface.co"))
        #expect(SpeechModelInfo.sherpaOnnxURL.absoluteString.contains("github.com"))
        #expect(SpeechModelInfo.nvidiaURL.absoluteString.contains("nvidia.com"))
    }

    // MARK: - Deduplication: Pass 1 (sentence-level)

    @Test("Deduplication removes repeated sentences")
    func deduplicateRepeatedSentences() {
        let input = "I love dogs. I love dogs. I love cats."
        let result = Transcriber.deduplicateRepeatedPhrases(input)
        #expect(result == "I love dogs. I love cats.")
    }

    // MARK: - Deduplication: Pass 2 (suffix-overlap)

    @Test("Deduplication drops garbled suffix echo")
    func deduplicateSuffixEcho() {
        // "ore changes?" tail words ["changes"] match prev tail ["changes"]
        // but need 2+ word match -- let's test the real pattern
        let input = "Do we need to make more changes? more changes?"
        let result = Transcriber.deduplicateRepeatedPhrases(input)
        #expect(result == "Do we need to make more changes?")
    }

    @Test("Deduplication drops trailing suffix fragment")
    func deduplicateTrailingSuffix() {
        let input = "I want terminal B for terminals. for terminals."
        let result = Transcriber.deduplicateRepeatedPhrases(input)
        #expect(result == "I want terminal B for terminals.")
    }

    @Test("Deduplication drops tiny garbage fragment")
    func deduplicateGarbageFragment() {
        let input = "Reopen one. e."
        let result = Transcriber.deduplicateRepeatedPhrases(input)
        #expect(result == "Reopen one.")
    }

    @Test("Deduplication drops cascading suffix echoes")
    func deduplicateCascadingSuffix() {
        let input = "This will take 8 to 10 minutes to complete. take 8 to 10 minutes to complete. s to complete."
        let result = Transcriber.deduplicateRepeatedPhrases(input)
        #expect(result == "This will take 8 to 10 minutes to complete.")
    }

    @Test("Deduplication preserves distinct trailing sentence")
    func deduplicatePreservesDistinct() {
        let input = "I like dogs. Cats are nice too."
        let result = Transcriber.deduplicateRepeatedPhrases(input)
        #expect(result == "I like dogs. Cats are nice too.")
    }

    // MARK: - Deduplication: Pass 3 (word runs)

    @Test("Deduplication collapses word runs of 3+")
    func deduplicateWordRuns() {
        let input = "the the the quick brown"
        let result = Transcriber.deduplicateRepeatedPhrases(input)
        #expect(result == "the quick brown")
    }

    @Test("Deduplication preserves legitimate word pairs")
    func deduplicatePreservesLegitPairs() {
        let input = "that that is, is"
        let result = Transcriber.deduplicateRepeatedPhrases(input)
        #expect(result == "that that is, is")
    }

    // MARK: - Deduplication: Pass 4 (n-gram loops)

    @Test("Deduplication collapses repeated 3-word phrase")
    func deduplicateNGram3() {
        let input = "part of the part of the quick brown"
        let result = Transcriber.deduplicateRepeatedPhrases(input)
        #expect(result == "part of the quick brown")
    }

    @Test("Deduplication collapses repeated multi-word phrase loop")
    func deduplicateNGramLoop() {
        let input = "some part of the sentence some part of the sentence got repeated"
        let result = Transcriber.deduplicateRepeatedPhrases(input)
        #expect(result == "some part of the sentence got repeated")
    }

    @Test("Deduplication collapses triple n-gram repetition")
    func deduplicateNGramTriple() {
        let input = "hello world today hello world today hello world today is nice"
        let result = Transcriber.deduplicateRepeatedPhrases(input)
        #expect(result == "hello world today is nice")
    }

    @Test("Deduplication preserves non-repeating text")
    func deduplicateNGramNoFalsePositive() {
        let input = "the quick brown fox jumps over the lazy dog"
        let result = Transcriber.deduplicateRepeatedPhrases(input)
        #expect(result == "the quick brown fox jumps over the lazy dog")
    }

    // MARK: - Silence trimming

    @Test("Trim silence removes trailing silent tail")
    func trimTrailingSilence() {
        // 1s of speech-level audio + 0.5s of silence
        var audio = (0..<16000).map { _ in Float.random(in: -0.1...0.1) }
        audio += Array(repeating: Float(0), count: 8000)
        let trimmed = Transcriber.trimSilence(audio)
        #expect(trimmed.count < audio.count)
        #expect(trimmed.count >= 16000)
    }

    @Test("Trim silence removes leading silence")
    func trimLeadingSilence() {
        // 0.5s silence + 1s speech
        var audio = Array(repeating: Float(0), count: 8000)
        audio += (0..<16000).map { _ in Float.random(in: -0.1...0.1) }
        let trimmed = Transcriber.trimSilence(audio)
        #expect(trimmed.count < audio.count)
        #expect(trimmed.count >= 16000)
    }

    @Test("Trim silence preserves all-speech audio")
    func trimPreservesAllSpeech() {
        let audio = (0..<16000).map { _ in Float.random(in: -0.1...0.1) }
        let trimmed = Transcriber.trimSilence(audio)
        #expect(trimmed.count == audio.count)
    }

    @Test("Trim silence returns empty for empty input")
    func trimEmptyInput() {
        let trimmed = Transcriber.trimSilence([])
        #expect(trimmed.isEmpty)
    }

    @Test("Trim silence returns empty for silence-only input")
    func trimSilenceOnly() {
        let audio = Array(repeating: Float(0), count: 16000)
        let trimmed = Transcriber.trimSilence(audio)
        #expect(trimmed.isEmpty)
    }

    // MARK: - Segment splitting

    @Test("Split does not segment short audio")
    func splitShortAudio() {
        // 5s of speech -- under the 8s threshold
        let audio = (0..<80000).map { _ in Float.random(in: -0.1...0.1) }
        let segments = Transcriber.splitAtSilenceGaps(audio)
        #expect(segments.count == 1)
    }

    @Test("Split segments long audio at silence gaps")
    func splitLongAudioAtGaps() {
        // 5s speech + 1s silence + 5s speech = 11s (above 8s threshold)
        var audio = (0..<80000).map { _ in Float.random(in: -0.1...0.1) }
        audio += Array(repeating: Float(0), count: 16000)
        audio += (0..<80000).map { _ in Float.random(in: -0.1...0.1) }
        let segments = Transcriber.splitAtSilenceGaps(audio)
        #expect(segments.count >= 2)
    }

    // MARK: - Audio normalization

    @Test("Normalize audio scales to full range")
    func normalizeAudio() {
        let audio: [Float] = [0.0, 0.1, -0.05, 0.05]
        let normalized = Transcriber.normalizeAudio(audio)
        // Peak is 0.1, so gain = 10.0 (capped), all values scaled 10x
        #expect(abs(normalized[1] - 1.0) < 0.001)
    }

    @Test("Normalize audio preserves silence")
    func normalizePreservesSilence() {
        let audio = Array(repeating: Float(0), count: 100)
        let normalized = Transcriber.normalizeAudio(audio)
        #expect(normalized == audio)
    }
}
