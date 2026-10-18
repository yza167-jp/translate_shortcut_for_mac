import Foundation

public struct TranslationClient: Sendable {
    private let session: URLSession
    private static let maximumResponseBytes = 2 * 1_024 * 1_024

    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    public func makeRequest(configuration: AppConfiguration, apiKey: String,
                            text: String, mode: TranslationMode) throws -> URLRequest {
        try configuration.validate(apiKey: apiKey, mode: mode)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.configuration("请输入要翻译或查询的文本。")
        }
        var request = URLRequest(url: try configuration.endpointURL())
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(configuration.stream ? "text/event-stream, application/json" : "application/json",
                         forHTTPHeaderField: "Accept")
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": configuration.model.trimmingCharacters(in: .whitespacesAndNewlines),
            "messages": [["role": "user", "content": PromptTemplate.render(
                configuration.prompt(for: mode), text: text, language: configuration.language)]],
            "stream": configuration.stream
        ])
        return request
    }

    public func translate(configuration: AppConfiguration, apiKey: String, text: String,
                          mode: TranslationMode,
                          onUpdate: @Sendable (String) async -> Void = { _ in }) async throws -> String {
        let request = try makeRequest(configuration: configuration, apiKey: apiKey, text: text, mode: mode)
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranslationError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                data.append(byte)
                if data.count >= 16_384 { break }
            }
            let message = Self.serverMessage(data, status: http.statusCode)
            throw TranslationError.server(http.statusCode, Self.redact(message, key: apiKey))
        }

        if http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true {
            var result = ""
            var receivedBytes = 0
            var finished = false
            for try await line in bytes.lines {
                try Task.checkCancellation()
                receivedBytes += line.utf8.count
                guard receivedBytes <= Self.maximumResponseBytes else { throw TranslationError.responseTooLarge }
                guard line.hasPrefix("data:") else { continue }
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload == "[DONE]" { finished = true; break }
                guard !payload.isEmpty else { continue }
                let chunk: Completion
                do { chunk = try JSONDecoder().decode(Completion.self, from: Data(payload.utf8)) }
                catch { throw TranslationError.invalidResponse }
                if let error = chunk.error {
                    throw TranslationError.server(http.statusCode, Self.redact(error.message, key: apiKey))
                }
                // Ignore usage-only chunks and reasoning tokens; show only the answer.
                if let choice = chunk.choices?.first {
                    if let text = choice.delta?.content ?? choice.delta?.refusal {
                        result += text
                        await onUpdate(result)
                    }
                    if choice.finish_reason != nil { finished = true }
                }
            }
            try Task.checkCancellation()
            guard finished else { throw TranslationError.incompleteResponse }
            guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw TranslationError.emptyResponse
            }
            return result
        }

        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            data.append(byte)
            guard data.count <= Self.maximumResponseBytes else { throw TranslationError.responseTooLarge }
        }
        let completion: Completion
        do { completion = try JSONDecoder().decode(Completion.self, from: data) }
        catch { throw TranslationError.invalidResponse }
        if let error = completion.error {
            throw TranslationError.server(http.statusCode, Self.redact(error.message, key: apiKey))
        }
        guard let message = completion.choices?.first?.message,
              let text = message.content ?? message.refusal,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.emptyResponse
        }
        try Task.checkCancellation()
        await onUpdate(text)
        return text
    }

    private static func redact(_ text: String, key: String) -> String {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleanKey.isEmpty ? text : text.replacingOccurrences(of: cleanKey, with: "[redacted]")).prefix(500))
    }

    private static func serverMessage(_ data: Data, status: Int) -> String {
        if let error = try? JSONDecoder().decode(Completion.self, from: data).error { return error.message }
        switch status {
        case 401, 403: return "请检查 API Key、模型权限及服务地址。"
        case 429: return "请求过于频繁或额度不足，请稍后重试并检查账户额度。"
        default: return "服务暂时不可用，请确认 API 地址后重试。"
        }
    }
}

private struct Completion: Decodable {
    var choices: [Choice]?
    var error: APIError?

    struct Choice: Decodable {
        var delta: Message?
        var message: Message?
        var finish_reason: String?
    }
    struct Message: Decodable {
        var content: String?
        var refusal: String?
    }
    struct APIError: Decodable { var message: String }
}
