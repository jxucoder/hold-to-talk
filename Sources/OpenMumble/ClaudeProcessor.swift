import Foundation

/// Cleans up raw transcription via Claude or OpenAI APIs.
/// Zero dependencies — raw URLSession.
struct TextProcessor {
    enum Provider: String, CaseIterable {
        case claude
        case openai
    }

    var provider: Provider
    var apiKey: String
    var model: String

    enum ModelFetchError: LocalizedError {
        case missingAPIKey
        case invalidResponse
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Missing API key."
            case .invalidResponse:
                return "Unexpected API response."
            case let .requestFailed(message):
                return message
            }
        }
    }

    private static let systemPrompt = """
        You are a dictation post-processor. You receive raw speech-to-text output \
        and return a cleaned version. Rules:
        1. Remove filler words (um, uh, like, you know) unless clearly intentional.
        2. Fix grammar and punctuation.
        3. Resolve self-corrections — "Tuesday no Wednesday" → "Wednesday".
        4. Preserve the speaker's tone.
        5. Do NOT add information or change meaning.
        6. Return ONLY the cleaned text.
        """

    func cleanup(_ raw: String) async throws -> String {
        guard !apiKey.isEmpty else { return raw }

        switch provider {
        case .claude:  return try await callClaude(raw)
        case .openai:  return try await callOpenAI(raw)
        }
    }

    /// Fetches available model IDs for the selected provider.
    func fetchAvailableModels() async throws -> [String] {
        guard !apiKey.isEmpty else { throw ModelFetchError.missingAPIKey }

        switch provider {
        case .claude:
            return try await fetchClaudeModels()
        case .openai:
            return try await fetchOpenAIModels()
        }
    }

    // MARK: - Claude (Anthropic Messages API)

    private func callClaude(_ raw: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": Self.systemPrompt,
            "messages": [["role": "user", "content": raw]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            print("[cleanup] Claude API error: \(String(data: data, encoding: .utf8) ?? "unknown")")
            return raw
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            return raw
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchClaudeModels() async throws -> [String] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelFetchError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown API error"
            throw ModelFetchError.requestFailed(body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            throw ModelFetchError.invalidResponse
        }

        let models = items
            .compactMap { $0["id"] as? String }
            .filter { !$0.isEmpty }
            .sorted()
        return models
    }

    // MARK: - OpenAI (Chat Completions API)

    private func callOpenAI(_ raw: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": raw],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            print("[cleanup] OpenAI API error: \(String(data: data, encoding: .utf8) ?? "unknown")")
            return raw
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            return raw
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fetchOpenAIModels() async throws -> [String] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelFetchError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown API error"
            throw ModelFetchError.requestFailed(body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            throw ModelFetchError.invalidResponse
        }

        let excludedPrefixes = [
            "whisper",
            "tts",
            "dall-e",
            "text-embedding",
            "omni-moderation",
        ]

        let models = items
            .compactMap { $0["id"] as? String }
            .filter { !$0.isEmpty }
            .filter { id in
                !excludedPrefixes.contains(where: { id.hasPrefix($0) })
            }
            .sorted()
        return models
    }
}
