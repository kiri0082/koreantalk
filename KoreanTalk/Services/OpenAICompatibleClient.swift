import Foundation
import os

enum AIClientError: LocalizedError {
    case invalidURL
    case missingAPIKey
    case httpError(Int, String)
    case decodingError(String)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:               return "Invalid API URL. Check Settings."
        case .missingAPIKey:            return "API key not set — add your Groq key in Settings."
        case .httpError(let code, _):
            switch code {
            case 401: return "Invalid Groq API key — check your key in Settings."
            case 429: return "Rate limit reached — Groq's free tier has a per-minute limit. Wait a moment and try again."
            case 500, 502, 503: return "Groq server error — try again in a moment."
            default:  return "API error \(code) — check your connection and try again."
            }
        case .decodingError:            return "Unexpected response from server — try again."
        case .networkError:             return "No connection — check your internet and try again."
        }
    }
}

struct APIMessage: Codable {
    let role: String
    let content: String
}

final class OpenAICompatibleClient {

    struct Config {
        var baseURL: String
        var apiKey: String
        var model: String
        var timeoutSeconds: Double = 90
    }

    private var config: Config

    init(config: Config) {
        self.config = config
    }

    func updateConfig(_ config: Config) {
        self.config = config
        Logger.api.info("Config updated — model: \(config.model), baseURL: \(config.baseURL)")
    }

    // MARK: - Streaming chat (with 429 retry)

    func streamChat(messages: [APIMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !config.apiKey.isEmpty else {
                        Logger.api.error("streamChat failed: API key is empty")
                        throw AIClientError.missingAPIKey
                    }

                    let urlString = config.baseURL
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        + "/chat/completions"
                    guard let url = URL(string: urlString) else {
                        Logger.api.error("streamChat failed: invalid URL '\(urlString)'")
                        throw AIClientError.invalidURL
                    }

                    Logger.api.info("→ POST \(urlString) | model=\(self.config.model) | messages=\(messages.count)")

                    // Retry up to 3 times on 429 with exponential backoff (5s, 10s, 15s)
                    let maxAttempts = 3
                    for attempt in 1...maxAttempts {
                        let isRateLimited = try await self.runStream(
                            url: url, messages: messages, continuation: continuation
                        )
                        guard isRateLimited else { return }  // success or non-429 error already thrown

                        if attempt < maxAttempts {
                            let waitSeconds: UInt64 = UInt64(attempt) * 5
                            Logger.api.warning("Rate limited (429) — waiting \(waitSeconds)s before retry \(attempt + 1)/\(maxAttempts)")
                            try await Task.sleep(nanoseconds: waitSeconds * 1_000_000_000)
                        }
                    }

                    throw AIClientError.httpError(429, "Rate limit hit. Wait a moment and try again.")
                } catch {
                    Logger.api.error("streamChat error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Attempts one stream request. Returns `true` if rate-limited (caller should retry),
    /// `false` if completed successfully. Throws on any other error.
    private func runStream(
        url: URL,
        messages: [APIMessage],
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = config.timeoutSeconds

        let body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true,
            "temperature": 0.7,
            "max_tokens": 2048
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeoutSeconds
        let session = URLSession(configuration: sessionConfig)

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.decodingError("Invalid response type")
        }

        Logger.api.info("← HTTP \(httpResponse.statusCode)")

        // Signal caller to retry
        if httpResponse.statusCode == 429 {
            return true
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await byte in bytes {
                errorBody += String(bytes: [byte], encoding: .utf8) ?? ""
            }
            Logger.api.error("streamChat HTTP error \(httpResponse.statusCode): \(errorBody)")
            throw AIClientError.httpError(httpResponse.statusCode, errorBody)
        }

        var chunkCount = 0
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard jsonStr != "[DONE]" else { break }

            guard
                let data = jsonStr.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let choices = json["choices"] as? [[String: Any]],
                let delta = choices.first?["delta"] as? [String: Any],
                let content = delta["content"] as? String
            else { continue }

            chunkCount += 1
            continuation.yield(content)
        }

        Logger.api.info("Stream complete — \(chunkCount) chunks received")
        continuation.finish()
        return false  // success
    }

    // MARK: - Non-streaming (connection test)

    func chat(messages: [APIMessage]) async throws -> String {
        guard !config.apiKey.isEmpty else {
            Logger.api.error("chat failed: API key is empty")
            throw AIClientError.missingAPIKey
        }

        let urlString = config.baseURL
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/chat/completions"
        guard let url = URL(string: urlString) else {
            Logger.api.error("chat failed: invalid URL '\(urlString)'")
            throw AIClientError.invalidURL
        }

        Logger.api.info("→ POST (non-stream) \(urlString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false,
            "max_tokens": 20
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            Logger.api.error("chat HTTP error \(code): \(body)")
            throw AIClientError.httpError(code, body)
        }

        Logger.api.info("← HTTP 200 OK")

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw AIClientError.decodingError("Unexpected response format")
        }

        return content
    }

    func isReachable() async -> Bool {
        Logger.api.info("Testing API reachability…")
        do {
            _ = try await chat(messages: [APIMessage(role: "user", content: "hi")])
            Logger.api.info("API reachable ✓")
            return true
        } catch {
            Logger.api.error("API not reachable: \(error.localizedDescription)")
            return false
        }
    }
}
