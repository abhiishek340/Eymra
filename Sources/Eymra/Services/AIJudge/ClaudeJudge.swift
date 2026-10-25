import Foundation
import os

/// Claude Messages API client over plain URLSession. The key comes from the Keychain and is never logged.
nonisolated struct ClaudeJudge: JudgeProvider {
    struct ModelOption: Identifiable, Hashable, Sendable {
        var id: String
        var name: String
        /// Estimated cost of a 60-photo run at 756 px.
        var estimate: String
    }

    static let models: [ModelOption] = [
        ModelOption(id: "claude-sonnet-5-5", name: "Balanced · Sonnet", estimate: "about 15¢ a go"),
        ModelOption(id: "claude-haiku-5-5", name: "Fast and cheap · Haiku", estimate: "about 1¢ a go"),
        ModelOption(id: "claude-opus-5-5", name: "Best quality · Opus", estimate: "about 30¢ a go"),
    ]

    private static let log = Logger(subsystem: "app.eymra", category: "judge")
    static let endpoint: URL? = URL(string: "https://api.anthropic.com/v1/messages")

    var model: String
    var apiKey: String
    var promptVersion: Int { JudgePrompt.version }
    var session: URLSession = ClaudeJudge.makeSession()

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }

    func score(_ images: [JudgeImage]) async throws -> [JudgeScore] {
        let body = requestBody(images: images, instruction: JudgePrompt.scoreInstruction(count: images.count),
                               schema: JudgeSchema.scoreSchema, maxTokens: 8000)
        let json = try await send(body)
        return try JudgeSchema.parseScores(json, sent: images.map(\.photoID))
    }

    func bestOf(_ images: [JudgeImage]) async throws -> BestOfAnswer {
        let body = requestBody(images: images, instruction: JudgePrompt.bestOfInstruction,
                               schema: JudgeSchema.bestOfSchema, maxTokens: 1000)
        let json = try await send(body)
        return try JudgeSchema.parseBestOf(json, sent: images.map(\.photoID))
    }

    func title(_ images: [JudgeImage]) async throws -> String {
        let body = requestBody(images: images, instruction: JudgePrompt.titleInstruction,
                               schema: JudgeSchema.titleSchema, maxTokens: 500)
        return try JudgeSchema.parseTitle(try await send(body))
    }

    // MARK: Request

    func requestBody(images: [JudgeImage], instruction: String, schema: [String: Any], maxTokens: Int) -> [String: Any] {
        var content: [[String: Any]] = []
        for (i, image) in images.enumerated() {
            content.append(["type": "text", "text": "Image \(i + 1):"])
            content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                                         "data": image.jpeg.base64EncodedString()]])
        }
        content.append(["type": "text", "text": instruction])
        return [
            "model": model,
            "max_tokens": maxTokens,
            "system": [["type": "text", "text": JudgePrompt.system, "cache_control": ["type": "ephemeral"]]],
            "messages": [["role": "user", "content": content]],
            "output_config": ["effort": "low", "format": ["type": "json_schema", "schema": schema]],
        ]
    }

    /// Sends one request; one retry on 429, 529 and 5xx after `retry-after` or 2 s. Returns the JSON text of the first text block.
    func send(_ body: [String: Any]) async throws -> Data {
        guard !apiKey.isEmpty else { throw JudgeError.missingKey }
        guard let endpoint = Self.endpoint else { throw JudgeError.badResponse("bad endpoint") }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        for attempt in 0..<2 {
            try Task.checkCancellation()
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                throw JudgeError.offline
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return try Self.extractText(data) }
            let retryable = status == 429 || status == 529 || (500...599).contains(status)
            if retryable && attempt == 0 {
                let after = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after").flatMap(Double.init) ?? 2
                Self.log.info("Judge HTTP \(status), retrying in \(after, privacy: .public)s")
                try await Task.sleep(for: .seconds(min(after, 20)))
                continue
            }
            throw JudgeError.http(status: status, message: Self.errorMessage(data) ?? HTTPURLResponse.localizedString(forStatusCode: status))
        }
        throw JudgeError.badResponse("retry exhausted")
    }

    static func extractText(_ data: Data) throws -> Data {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JudgeError.badResponse("not an object")
        }
        if (root["stop_reason"] as? String) == "refusal" { throw JudgeError.badResponse("refused") }
        let blocks = root["content"] as? [[String: Any]] ?? []
        guard let text = blocks.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let json = text.data(using: .utf8) else {
            throw JudgeError.badResponse("no text block")
        }
        return json
    }

    static func errorMessage(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = root["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }
}
