import AppKit
import Security
import TranslationCore

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var configuration: AppConfiguration
    @Published private(set) var apiKey = ""
    @Published private(set) var credentialError: String?
    @Published var shortcutError: String?
    private let defaultsKey = "appConfiguration.v1"
    private let service = "io.github.yza167-jp.translate-shortcut"

    var isConfigured: Bool {
        (try? configuration.validate(apiKey: apiKey, mode: .translate)) != nil
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(AppConfiguration.self, from: data) {
            configuration = saved
        } else {
            configuration = AppConfiguration()
        }
        do { apiKey = try readKey() }
        catch { credentialError = error.localizedDescription }
    }

    func save(_ configuration: AppConfiguration, apiKey: String) throws {
        _ = try configuration.endpointURL()
        guard !configuration.language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.configuration("目标语言不能为空。")
        }
        for mode in TranslationMode.allCases {
            guard PromptTemplate.containsTextPlaceholder(configuration.prompt(for: mode)) else {
                throw TranslationError.configuration("\(mode.title)提示词中缺少文本占位符。")
            }
        }
        let data = try JSONEncoder().encode(configuration)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        try writeKey(key)
        UserDefaults.standard.set(data, forKey: defaultsKey)
        self.apiKey = key
        self.configuration = configuration
        credentialError = nil
    }

    private var keyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "api-key"]
    }

    private func readKey() throws -> String {
        var query = keyQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = value as? Data,
              let key = String(data: data, encoding: .utf8) else { throw keychainError(status) }
        return key
    }

    private func writeKey(_ key: String) throws {
        // Avoid unnecessary writes and authorization prompts when only prompts change.
        if key == apiKey && credentialError == nil { return }
        if key.isEmpty {
            let status = SecItemDelete(keyQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
            return
        }
        let data = Data(key.utf8)
        let status = SecItemUpdate(keyQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = keyQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(query as CFDictionary, nil)
            guard result == errSecSuccess else { throw keychainError(result) }
        } else if status != errSecSuccess {
            throw keychainError(status)
        }
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey:
            "无法访问 macOS 钥匙串（\(status)）。请解锁钥匙串，并允许此应用访问已保存的 API Key。"])
    }
}
