import Foundation
import SwiftLlama

/// Manages the llama.cpp model instance for text cleanup.
actor TextProcessorEngine {
    static let shared = TextProcessorEngine()

    private var llama: SwiftLlama?
    private var loadedModelPath: String?

    func loadIfNeeded(modelPath: String) throws {
        guard loadedModelPath != modelPath else { return }
        let config = Configuration(
            topK: 20,
            topP: 0.9,
            nCTX: 2048,
            temperature: 0.1,
            maxTokenCount: 512,
            stopTokens: ["<end_of_turn>"]
        )
        llama = try SwiftLlama(modelPath: modelPath, modelConfiguration: config)
        loadedModelPath = modelPath
    }

    func generate(systemPrompt: String, userMessage: String) async throws -> String {
        guard let llama else { throw TextProcessorError.modelNotLoaded }
        let prompt = Prompt(
            type: .gemma,
            systemPrompt: systemPrompt,
            userMessage: userMessage
        )
        return try await llama.start(for: prompt)
    }

    func unload() {
        llama = nil
        loadedModelPath = nil
    }
}

/// Cleans up raw transcription via Gemma 3 1B (on-device).
struct TextProcessor {
    static let defaultPrompt = """
        You fix grammar and punctuation in speech-to-text transcriptions. \
        Output ONLY the cleaned transcription — nothing else.
        - Remove filler words (um, uh, like, you know) unless intentional.
        - Resolve self-corrections: "Tuesday no Wednesday" → "Wednesday".
        - Do NOT add, remove, or change any other words.
        """

    var prompt: String

    static var isAvailable: Bool {
        let modelPath = ModelManager.modelBase
            .appendingPathComponent(CleanupModelInfo.fileName)
        return FileManager.default.fileExists(atPath: modelPath.path)
    }

    private static func userMessage(_ raw: String) -> String {
        """
        Clean up this transcription. Return ONLY the corrected text, no explanation.

        \(raw)
        """
    }

    private static func stripLeakedTags(_ text: String) -> String {
        var result = text
        let patterns = [
            #"</?transcription>"#,
            #"</?model>"#,
            #"/model"#,
            #"<start_of_turn>[a-z]*"#,
            #"<end_of_turn>"#,
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func cleanup(_ raw: String) async throws -> String {
        let modelPath = ModelManager.modelBase
            .appendingPathComponent(CleanupModelInfo.fileName).path

        try await TextProcessorEngine.shared.loadIfNeeded(modelPath: modelPath)

        let instructions = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultPrompt
            : prompt

        let response = try await TextProcessorEngine.shared.generate(
            systemPrompt: instructions,
            userMessage: Self.userMessage(raw)
        )

        let cleaned = Self.stripLeakedTags(response)
        return cleaned.isEmpty ? raw : cleaned
    }
}

enum TextProcessorError: LocalizedError {
    case modelNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Cleanup model is not loaded"
        }
    }
}
