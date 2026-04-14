import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum TextCleanupAvailability: Equatable {
    case available
    case unavailableOSVersion
    case unavailableNotEnabled
    case unavailableDeviceNotEligible
    case unavailableModelNotReady
}

enum TextCleanup {
    static func checkAvailability() -> TextCleanupAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return _checkAvailability()
        }
        #endif
        return .unavailableOSVersion
    }

    static func cleanup(_ text: String, prompt: String = "") async -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return await _cleanup(text, prompt: prompt)
        }
        #endif
        return text
    }

    static let defaultPrompt = """
        You fix grammar and punctuation in speech-to-text transcriptions. \
        Output ONLY the cleaned transcription — nothing else.
        - Remove filler words (um, uh, like, you know) unless intentional.
        - Resolve self-corrections: "Tuesday no Wednesday" → "Wednesday".
        - Do NOT add, remove, or change any other words.
        """

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private static func _checkAvailability() -> TextCleanupAvailability {
        let availability = SystemLanguageModel.default.availability
        switch availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailableDeviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailableNotEnabled
        case .unavailable(.modelNotReady):
            return .unavailableModelNotReady
        default:
            return .unavailableNotEnabled
        }
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

    @available(macOS 26, *)
    private static func _cleanup(_ text: String, prompt: String) async -> String {
        guard _checkAvailability() == .available else { return text }

        let instructions = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultPrompt
            : prompt

        do {
            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let session = LanguageModelSession(instructions: instructions)
                    let response = try await session.respond(to: userMessage(text))
                    let cleaned = stripLeakedTags(response.content)
                    return cleaned.isEmpty ? text : cleaned
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                    throw CancellationError()
                }
                guard let result = try await group.next() else {
                    return text
                }
                group.cancelAll()
                return result
            }
        } catch {
            debugLog("[holdtotalk] Text cleanup failed: \(error)")
            return text
        }
    }
    #endif
}
