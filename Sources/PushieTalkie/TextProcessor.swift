import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Cleans up raw transcription via Apple Intelligence (on-device).
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
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            if case .available = model.availability { return true }
        }
        #endif
        return false
    }

    private static func userMessage(_ raw: String) -> String {
        """
        Clean up this transcription. Return ONLY the corrected text, no explanation.
        <transcription>
        \(raw)
        </transcription>
        """
    }

    func cleanup(_ raw: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else {
                print("[cleanup] Apple Intelligence not available, returning raw text")
                return raw
            }
            let instructions = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Self.defaultPrompt
                : prompt
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: Self.userMessage(raw))
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        print("[cleanup] Apple Intelligence not supported on this OS version")
        return raw
    }
}
