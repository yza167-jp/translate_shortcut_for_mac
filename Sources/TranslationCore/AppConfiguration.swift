import Foundation

public enum TranslationMode: String, CaseIterable, Sendable {
    case translate, dictionary

    public var title: String { self == .translate ? "翻译" : "词典" }
    public var shortcut: String { self == .translate ? "⌥ E" : "⇧ ⌥ E" }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var baseURL = "https://api.openai.com/v1"
    public var model = ""
    public var language = "Chinese"
    public var translationPrompt = Self.defaultTranslationPrompt
    public var dictionaryPrompt = Self.defaultDictionaryPrompt
    public var stream = true

    public static let defaultTranslationPrompt =
        "please translate {selection} into {language}, just give me simple answer:"
    public static let defaultDictionaryPrompt =
        "now you're a dictionary-bot, please explain \"{argument name=\"Text\"}\" to me with English and tell me how to pronounce phonetically, after that translate it/them into {language}, just give me simple answer:"

    public init() {}

    public func prompt(for mode: TranslationMode) -> String {
        mode == .translate ? translationPrompt : dictionaryPrompt
    }

    public func endpointURL() throws -> URL {
        guard var parts = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else {
            throw TranslationError.configuration("请填写有效的 API Base URL，不要包含密码、查询参数或片段。")
        }
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host.lowercased())
        guard parts.scheme == "https" || (parts.scheme == "http" && local) else {
            throw TranslationError.configuration("远程 API 必须使用 HTTPS；本机服务可以使用 HTTP。")
        }
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        if !parts.path.hasSuffix("/chat/completions") { parts.path += "/chat/completions" }
        guard let url = parts.url else {
            throw TranslationError.configuration("无法解析 API 地址。")
        }
        return url
    }

    public func validate(apiKey: String, mode: TranslationMode) throws {
        let endpoint = try endpointURL()
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.configuration("请先在设置中填写模型 ID。")
        }
        guard !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.configuration("请选择或填写目标语言。")
        }
        if endpoint.scheme == "https" && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TranslationError.configuration("请先在设置中填写 API Key。")
        }
        guard PromptTemplate.containsTextPlaceholder(prompt(for: mode)) else {
            throw TranslationError.configuration("提示词需要包含 {selection}、{Text} 或 {argument name=\"Text\"}。")
        }
    }
}

public enum TranslationError: LocalizedError, Sendable {
    case configuration(String)
    case server(Int, String)
    case invalidResponse
    case emptyResponse
    case incompleteResponse
    case responseTooLarge

    public var errorDescription: String? {
        switch self {
        case .configuration(let message): return message
        case .server(let code, let message): return "API 请求失败（\(code)）：\(message)"
        case .invalidResponse: return "服务返回了无法识别的数据，请确认接口支持 Chat Completions。"
        case .emptyResponse: return "模型没有返回文字。请检查模型是否支持文本输出，或更换模型后重试。"
        case .incompleteResponse: return "连接提前结束，回答可能不完整。请重试。"
        case .responseTooLarge: return "服务返回的内容过长，请缩短输入后重试。"
        }
    }
}
