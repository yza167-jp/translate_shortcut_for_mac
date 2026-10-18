import SwiftUI
import TranslationCore

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var draft: AppConfiguration
    @State private var apiKey: String
    @State private var message: String?
    @State private var failed = false
    @State private var testing = false
    @State private var testTask: Task<Void, Never>?
    @State private var trusted = SelectionReader.isTrusted
    var openPanel: (TranslationMode) -> Void

    init(store: SettingsStore, openPanel: @escaping (TranslationMode) -> Void) {
        self.store = store
        self.openPanel = openPanel
        _draft = State(initialValue: store.configuration)
        _apiKey = State(initialValue: store.apiKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "character.bubble.fill").font(.system(size: 31)).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Translate Shortcut").font(.system(size: 24, weight: .semibold))
                    Text("选中、按下，即刻理解。").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("设置").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }.padding(26)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("API 与模型", symbol: "network") {
                        field("Base URL", hint: "可填写 /v1 基础地址或完整的 /chat/completions 地址。") {
                            TextField("https://api.openai.com/v1", text: $draft.baseURL).accessibilityIdentifier("baseURL")
                        }
                        field("模型 ID", hint: "填写服务商提供的完整模型名称。") {
                            TextField("例如：你的模型 ID", text: $draft.model).accessibilityIdentifier("modelID")
                        }
                        field("API Key", hint: "保存在 macOS 钥匙串中；本机 HTTP 服务可留空。") {
                            SecureField("填写 API Key", text: $apiKey).accessibilityIdentifier("apiKey")
                        }
                        Toggle("流式显示回答", isOn: $draft.stream)
                        Text("支持 OpenAI 兼容的 Chat Completions 接口。远程地址需使用 HTTPS。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        if let error = store.credentialError {
                            Text(error).font(.system(size: 12)).foregroundStyle(.orange)
                        }
                    }
                    section("目标语言", symbol: "globe") {
                        HStack {
                            TextField("Chinese", text: $draft.language).accessibilityIdentifier("targetLanguage")
                            Menu("常用语言") {
                                ForEach(["Chinese", "Traditional Chinese", "English", "Japanese", "Korean", "French", "German", "Spanish"], id: \.self) { language in
                                    Button(language) { draft.language = language }
                                }
                            }.fixedSize()
                        }
                        Text("默认 Chinese，也可以输入任意语言名称。两种模式共用此设置。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    section("提示词", symbol: "text.alignleft") {
                        Text("支持 {selection}、{Text}、{argument name=\"Text\"} 和 {language}。文本占位符会替换为选区或手动输入的内容。")
                            .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                        promptEditor("翻译 · ⌥ E", text: $draft.translationPrompt)
                        promptEditor("词典 · ⇧ ⌥ E", text: $draft.dictionaryPrompt)
                        Button("恢复默认提示词") {
                            draft.translationPrompt = AppConfiguration.defaultTranslationPrompt
                            draft.dictionaryPrompt = AppConfiguration.defaultDictionaryPrompt
                        }.font(.system(size: 11))
                    }
                    section("快捷键与权限", symbol: "keyboard") {
                        shortcutRow("翻译选中文本", shortcut: "⌥ E") { openPanel(.translate) }
                        shortcutRow("词典 / 手动查询", shortcut: "⇧ ⌥ E") { openPanel(.dictionary) }
                        if let error = store.shortcutError {
                            Text(error).font(.system(size: 12)).foregroundStyle(.orange)
                        }
                        Divider().padding(.vertical, 4)
                        HStack(alignment: .top) {
                            Image(systemName: trusted ? "checkmark.shield.fill" : "hand.raised.fill")
                                .foregroundStyle(trusted ? .mint : .orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(trusted ? "辅助功能已授权" : "需要辅助功能权限读取选区").font(.system(size: 12, weight: .medium))
                                Text("在系统设置中允许 Translate Shortcut。未授权时仍可手动输入。部分应用会临时通过 ⌘C 读取选区，并恢复原剪贴板。")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(trusted ? "系统设置" : "去授权") { SelectionReader.requestPermission() }
                        }
                        Text("浮窗内按 ⌘↩ 发送，Esc 关闭并取消请求。仅主动触发时读取选区；文本只发送至你配置的 API 服务，不保存查询历史。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(26)
            }
            Divider()
            HStack(spacing: 12) {
                if let message {
                    Text(message).font(.system(size: 11)).foregroundStyle(failed ? .orange : .mint)
                        .lineLimit(3).textSelection(.enabled)
                }
                Spacer(minLength: 12)
                Button(testing ? "测试中…" : "测试连接", action: testConnection).disabled(testing)
                    .help("向当前填写的服务发送一条简短测试请求，可能产生 API 费用。")
                Button("保存设置", action: save).buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
                    .keyboardShortcut("s", modifiers: .command).accessibilityIdentifier("saveSettings")
            }.padding(18)
        }
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 660, idealWidth: 720, minHeight: 630, idealHeight: 790)
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = SelectionReader.isTrusted }
        .onDisappear { testTask?.cancel(); testing = false }
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.mint)
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06)))
    }

    private func field<Content: View>(_ title: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium))
            content()
            Text(hint).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func promptEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium))
            TextEditor(text: text).font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden).padding(7).frame(height: 100)
                .background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.08)))
                .accessibilityLabel(title + "提示词")
        }
    }

    private func shortcutRow(_ title: String, shortcut: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Text(shortcut).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
            Button("打开", action: action).font(.system(size: 11))
        }
    }

    private func save() {
        do {
            try store.save(draft, apiKey: apiKey)
            failed = false
            message = "已保存，下次查询生效。"
        } catch { failed = true; message = error.localizedDescription }
    }

    private func testConnection() {
        testing = true
        message = "正在发送测试请求…"
        failed = false
        var configuration = draft
        configuration.translationPrompt = "Reply with just OK. {selection}"
        configuration.stream = false
        let key = apiKey
        testTask = Task {
            defer { testing = false }
            do {
                _ = try await TranslationClient().translate(configuration: configuration, apiKey: key,
                                                            text: "Connection test.", mode: .translate)
                guard !Task.isCancelled else { return }
                message = "连接成功，模型可以正常回答。请保存设置。"
                failed = false
            } catch {
                guard !Task.isCancelled else { return }
                message = error.localizedDescription
                failed = true
            }
        }
    }
}
