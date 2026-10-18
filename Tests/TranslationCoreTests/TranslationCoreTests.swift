import Foundation
import XCTest
@testable import TranslationCore

final class TranslationCoreTests: XCTestCase, @unchecked Sendable {
    func testDefaultPromptsMatchRequestedBehavior() {
        let configuration = AppConfiguration()
        XCTAssertEqual(configuration.language, "Chinese")
        XCTAssertEqual(PromptTemplate.render(configuration.translationPrompt, text: "Hello", language: "Chinese"),
                       "please translate Hello into Chinese, just give me simple answer:")
        XCTAssertEqual(PromptTemplate.render(configuration.dictionaryPrompt, text: "serendipity", language: "Chinese"),
            "now you're a dictionary-bot, please explain \"serendipity\" to me with English and tell me how to pronounce phonetically, after that translate it/them into Chinese, just give me simple answer:")
    }

    func testAllTextAliasesAndUnicode() {
        XCTAssertEqual(PromptTemplate.render("{selection}|{Text}|{text}|{argument name=\"Text\"}|{language}",
                                             text: "你好 👋", language: "Japanese"),
                       "你好 👋|你好 👋|你好 👋|你好 👋|Japanese")
        XCTAssertTrue(PromptTemplate.containsTextPlaceholder("{argument name = \"Text\"}"))
        XCTAssertFalse(PromptTemplate.containsTextPlaceholder("Translate into {language}"))
    }

    func testSelectionIsNotRecursivelyExpanded() {
        XCTAssertEqual(PromptTemplate.render("{selection} → {language}", text: "{language} $1 \\ \"test\"", language: "中文"),
                       "{language} $1 \\ \"test\" → 中文")
    }

    func testEndpointNormalization() throws {
        var configuration = AppConfiguration()
        for base in ["https://api.example.com/v1", "https://api.example.com/v1/", "https://api.example.com/v1/chat/completions"] {
            configuration.baseURL = base
            XCTAssertEqual(try configuration.endpointURL().absoluteString, "https://api.example.com/v1/chat/completions")
        }
        configuration.baseURL = "http://127.0.0.1:11434/v1"
        XCTAssertEqual(try configuration.endpointURL().absoluteString, "http://127.0.0.1:11434/v1/chat/completions")
    }

    func testRejectsUnsafeAndMalformedEndpoints() {
        var configuration = AppConfiguration()
        for base in ["", "not a URL", "http://example.com/v1", "file:///tmp/api", "https://user:pass@example.com/v1",
                     "https://example.com/v1?api_key=secret", "https://example.com/v1#fragment"] {
            configuration.baseURL = base
            XCTAssertThrowsError(try configuration.endpointURL(), base)
        }
    }

    func testValidatesConfigurationAndEmptyInput() throws {
        var configuration = AppConfiguration()
        XCTAssertThrowsError(try configuration.validate(apiKey: "key", mode: .translate))
        configuration.model = "test-model"
        XCTAssertThrowsError(try configuration.validate(apiKey: "", mode: .translate))
        configuration.baseURL = "http://localhost:11434/v1"
        XCTAssertNoThrow(try configuration.validate(apiKey: "", mode: .dictionary))
        XCTAssertThrowsError(try TranslationClient().makeRequest(configuration: configuration, apiKey: "", text: " \n ", mode: .translate))
        configuration.language = " "
        XCTAssertThrowsError(try configuration.validate(apiKey: "", mode: .translate))
        configuration.language = "Chinese"
        configuration.dictionaryPrompt = "No text placeholder"
        XCTAssertThrowsError(try configuration.validate(apiKey: "", mode: .dictionary))
    }

    func testRequestContainsExpectedPromptAndHeaders() throws {
        var configuration = AppConfiguration()
        configuration.model = " test-model "
        let request = try TranslationClient().makeRequest(configuration: configuration, apiKey: " test-key ",
                                                           text: "a \"quote\"\nand a newline", mode: .dictionary)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["stream"] as? Bool, true)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0]["role"], "user")
        XCTAssertTrue(try XCTUnwrap(messages[0]["content"]).contains("a \"quote\"\nand a newline"))
    }

    func testLocalRequestOmitsEmptyAuthorization() throws {
        var configuration = AppConfiguration()
        configuration.baseURL = "http://localhost:1234/v1"
        configuration.model = "local-model"
        configuration.stream = false
        let request = try TranslationClient().makeRequest(configuration: configuration, apiKey: "", text: "Hello", mode: .translate)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["stream"] as? Bool, false)
    }

    func testStreamingUnicodeAndUsageOnlyEvents() async throws {
        let stream = """
        : keepalive

        data: {"choices":[{"delta":{"role":"assistant"}}]}

        data: {"choices":[{"delta":{"content":"你"}}]}

        data: {"choices":[{"delta":{"content":"好 👋"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: {"choices":[],"usage":{"total_tokens":8}}

        data: [DONE]

        """
        let (client, configuration) = fixture(stream, mime: "text/event-stream")
        let updates = Updates()
        let result = try await client.translate(configuration: configuration, apiKey: "test-key", text: "Hello", mode: .translate) {
            await updates.append($0)
        }
        XCTAssertEqual(result, "你好 👋")
        let values = await updates.values
        XCTAssertEqual(values, ["你", "你好 👋"])
    }

    func testAcceptsJSONFromNonStreamingProvider() async throws {
        let (client, configuration) = fixture(#"{"choices":[{"message":{"content":"你好"}}]}"#)
        let result = try await client.translate(configuration: configuration, apiKey: "test-key", text: "Hello", mode: .translate)
        XCTAssertEqual(result, "你好")
    }

    func testRefusalIsVisible() async throws {
        let (client, configuration) = fixture(#"{"choices":[{"message":{"content":null,"refusal":"Unable to answer."}}]}"#)
        let result = try await client.translate(configuration: configuration, apiKey: "test-key", text: "Hello", mode: .translate)
        XCTAssertEqual(result, "Unable to answer.")
    }

    func testServerErrorRedactsAPIKey() async {
        let (client, configuration) = fixture(#"{"error":{"message":"Incorrect API key: test-key"}}"#, status: 401)
        do {
            _ = try await client.translate(configuration: configuration, apiKey: "test-key", text: "Hello", mode: .translate)
            XCTFail("Expected server failure")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("test-key"))
            XCTAssertTrue(error.localizedDescription.contains("401"))
            XCTAssertTrue(error.localizedDescription.contains("[redacted]"))
        }
    }

    func testNonJSONRateLimitHasActionableMessage() async {
        let (client, configuration) = fixture("<html>Rate limited</html>", status: 429)
        do {
            _ = try await client.translate(configuration: configuration, apiKey: "test-key", text: "Hello", mode: .translate)
            XCTFail("Expected rate limit")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("429"))
            XCTAssertTrue(error.localizedDescription.contains("额度"))
        }
    }

    func testMalformedAndEmptyResponsesFailClearly() async {
        for body in ["not json", "{}", #"{"choices":[{"message":{"content":""}}]}"#] {
            let (client, configuration) = fixture(body)
            do {
                _ = try await client.translate(configuration: configuration, apiKey: "test-key", text: "Hello", mode: .translate)
                XCTFail("Expected invalid or empty response")
            } catch {
                XCTAssertTrue(error is TranslationError)
            }
        }
    }

    func testInterruptedStreamDoesNotClaimCompleteAnswer() async {
        let (client, configuration) = fixture("data: {\"choices\":[{\"delta\":{\"content\":\"partial\"}}]}\n\n", mime: "text/event-stream")
        do {
            _ = try await client.translate(configuration: configuration, apiKey: "test-key", text: "Hello", mode: .translate)
            XCTFail("Expected incomplete response")
        } catch TranslationError.incompleteResponse {
            // Expected: keep partial content visible, but report that it was interrupted.
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testStreamErrorsAreNotSilentlyIgnored() async {
        let (client, configuration) = fixture("data: {\"error\":{\"message\":\"Provider unavailable\"}}\n\n", mime: "text/event-stream")
        do {
            _ = try await client.translate(configuration: configuration, apiKey: "test-key", text: "Hello", mode: .translate)
            XCTFail("Expected stream error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Provider unavailable"))
        }
    }

    func testCancelledRequestDoesNotReturnAnAnswer() async {
        let (client, configuration) = fixture(#"{"choices":[{"message":{"content":"should not arrive"}}]}"#)
        let task = Task {
            // Wait until cancellation is visible before entering the client.
            while !Task.isCancelled { await Task.yield() }
            return try await client.translate(configuration: configuration, apiKey: "test-key", text: "Hello", mode: .translate)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testConfigurationRoundTripDoesNotContainCredentials() throws {
        var configuration = AppConfiguration()
        configuration.model = "custom-model"
        configuration.language = "Japanese"
        let data = try JSONEncoder().encode(configuration)
        XCTAssertEqual(try JSONDecoder().decode(AppConfiguration.self, from: data), configuration)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("apiKey"))
    }

    private func fixture(_ body: String, status: Int = 200, mime: String = "application/json") -> (TranslationClient, AppConfiguration) {
        let host = UUID().uuidString.lowercased() + ".test"
        StubProtocol.fixtures.insert(Fixture(body: Data(body.utf8), status: status, mime: mime), host: host)
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubProtocol.self]
        var configuration = AppConfiguration()
        configuration.baseURL = "https://\(host)/v1"
        configuration.model = "test-model"
        return (TranslationClient(session: URLSession(configuration: sessionConfiguration)), configuration)
    }
}

private actor Updates {
    var values: [String] = []
    func append(_ value: String) { values.append(value) }
}

private struct Fixture: Sendable {
    var body: Data
    var status: Int
    var mime: String
}

private final class FixtureStore: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: Fixture] = [:]
    func insert(_ fixture: Fixture, host: String) { lock.withLock { entries[host] = fixture } }
    func get(_ host: String) -> Fixture? { lock.withLock { entries[host] } }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    static let fixtures = FixtureStore()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let fixture = Self.fixtures.get(url.host ?? ""),
              let response = HTTPURLResponse(url: url, statusCode: fixture.status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": fixture.mime]) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
