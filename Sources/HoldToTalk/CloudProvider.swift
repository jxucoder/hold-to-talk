import Foundation

// MARK: - URL Validation

enum CloudURLError: LocalizedError {
    case insecureURL(String)

    var errorDescription: String? {
        switch self {
        case .insecureURL(let url):
            return "Refusing to send API request to non-HTTPS URL: \(url). Check your base URL in Settings."
        }
    }
}

/// Validate that a base URL uses HTTPS before sending API keys or audio over the network.
func validateCloudBaseURL(_ baseURL: String) throws {
    guard let url = URL(string: baseURL), url.scheme?.lowercased() == "https" else {
        throw CloudURLError.insecureURL(baseURL)
    }
}

// MARK: - Transcription Provider

enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case local
    case openAI = "openai"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local:  return "On-Device"
        case .openAI: return "OpenAI"
        }
    }
}

// MARK: - Cleanup Provider

enum CleanupProvider: String, CaseIterable, Identifiable {
    case appleIntelligence = "apple_intelligence"
    case openAI = "openai"
    case anthropic = "anthropic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleIntelligence: return "Apple Intelligence"
        case .openAI:            return "OpenAI"
        case .anthropic:         return "Anthropic"
        }
    }

    var defaultModel: String {
        switch self {
        case .appleIntelligence: return ""
        case .openAI:            return "gpt-4o-mini"
        case .anthropic:         return "claude-haiku-3-5-20241022"
        }
    }

    var keychainAccount: String {
        switch self {
        case .appleIntelligence: return ""
        case .openAI:            return "openai"
        case .anthropic:         return "anthropic"
        }
    }
}
