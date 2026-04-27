import Foundation
import Security

// MARK: - Pinned URLSession

/// Known provider hostnames where we perform strict server trust evaluation.
/// Custom base URLs (enterprise proxies) use standard HTTPS validation only.
private let pinnedHosts: Set<String> = ["api.openai.com", "api.anthropic.com"]

/// Returns a URLSession that performs server trust evaluation for known provider
/// hosts. For requests to custom base URLs, standard HTTPS validation applies.
func cloudURLSession() -> URLSession {
    URLSession(configuration: .default, delegate: CloudTrustDelegate.shared, delegateQueue: nil)
}

final class CloudTrustDelegate: NSObject, URLSessionDelegate, Sendable {
    static let shared = CloudTrustDelegate()

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }

        let host = challenge.protectionSpace.host

        // For known provider hosts, perform strict evaluation with hostname check.
        // For custom hosts (enterprise proxies), use default system validation.
        guard pinnedHosts.contains(host) else {
            return (.performDefaultHandling, nil)
        }

        let policy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(serverTrust, policy)

        var error: CFError?
        let trusted = SecTrustEvaluateWithError(serverTrust, &error)

        if trusted {
            return (.useCredential, URLCredential(trust: serverTrust))
        } else {
            debugLog("[holdtotalk] TLS trust evaluation failed for \(host): \(error?.localizedDescription ?? "unknown")")
            return (.cancelAuthenticationChallenge, nil)
        }
    }
}

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
