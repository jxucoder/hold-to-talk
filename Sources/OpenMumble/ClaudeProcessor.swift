import Foundation

/// Cleans up raw transcription via the Anthropic Messages API.
/// Zero dependencies — raw URLSession.
struct ClaudeProcessor {
    var apiKey: String
    var model: String = "claude-sonnet-4-20250514"

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
            print("[claude] API error: \(String(data: data, encoding: .utf8) ?? "unknown")")
            return raw
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            return raw
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
