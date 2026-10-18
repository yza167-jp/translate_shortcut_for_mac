import SwiftUI
import TranslationCore

struct TranslationPanelView: View {
    @ObservedObject var model: TranslationViewModel
    @ObservedObject var settings: SettingsStore
    var openSettings: () -> Void
    var close: () -> Void
    @FocusState private var inputFocused: Bool
    private let accent = Color(red: 0.46, green: 0.91, blue: 0.77)

    var body: some View {
        VStack(spacing: 0) {
            header.padding(22)
            Divider().overlay(.white.opacity(0.05))
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(model.sourceName.map { "来自 \($0)" } ?? "输入文本")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.input.count) 字符").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                ZStack(alignment: .topLeading) {
                    if model.input.isEmpty {
                        Text(model.mode == .dictionary ? "输入单词、短语或句子…" : "输入要翻译的文本…")
                            .foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $model.input)
                        .font(.system(size: 16)).scrollContentBackground(.hidden)
                        .focused($inputFocused).accessibilityLabel("待查询文本")
                        .frame(height: 76)
                }
                .padding(8)
                .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.07)))

                if let notice = model.notice {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "info.circle")
                        Text(notice)
                        Spacer(minLength: 0)
                        if !SelectionReader.isTrusted {
                            Button("授权") { SelectionReader.requestPermission() }.buttonStyle(.link)
                        }
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }

                HStack {
                    Text(model.mode == .translate ? "译文" : "释义 · 发音 · 翻译")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                    Spacer()
                    if !model.output.isEmpty {
                        Button { model.copyOutput() } label: {
                            Label(model.copied ? "已复制" : "复制", systemImage: model.copied ? "checkmark" : "doc.on.doc")
                        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(.top, 8)

                result.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if let error = model.error {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        Text(error).font(.system(size: 12)).textSelection(.enabled)
                        Spacer(minLength: 0)
                        if !settings.isConfigured {
                            Button("打开设置", action: openSettings).buttonStyle(.link)
                        }
                    }
                    .padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(.horizontal, 24).padding(.vertical, 18)
            Divider().overlay(.white.opacity(0.05))
            footer.padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(width: 740, height: 570)
        .background(Color(red: 0.09, green: 0.105, blue: 0.12).opacity(0.72))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.15), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .preferredColorScheme(.dark)
        .onAppear { inputFocused = true }
        .onChange(of: model.mode) { _, _ in inputFocused = true }
        .onExitCommand(perform: close)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "character.bubble.fill").font(.system(size: 24)).foregroundStyle(accent)
            HStack(spacing: 4) {
                ForEach(TranslationMode.allCases, id: \.self) { mode in
                    Button {
                        guard mode != model.mode else { return }
                        let text = model.input
                        model.prepare(mode: mode, selection: SelectionResult(text: text, notice: model.notice), source: model.sourceName)
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.submit() }
                    } label: {
                        Text(mode.title).font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .background(model.mode == mode ? .white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).foregroundStyle(model.mode == mode ? .primary : .secondary)
                }
            }
            Spacer()
            Text(settings.configuration.language).font(.system(size: 11, weight: .medium))
                .foregroundStyle(accent).padding(.horizontal, 10).padding(.vertical, 6)
                .background(accent.opacity(0.09), in: Capsule())
            Text(model.mode.shortcut).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            Button(action: openSettings) { Image(systemName: "gearshape").font(.system(size: 15)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("设置")
                .accessibilityLabel("打开设置")
        }
    }

    @ViewBuilder private var result: some View {
        if !model.output.isEmpty {
            ScrollView {
                Text(model.output).font(.system(size: 17)).lineSpacing(7)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
        } else if model.isLoading {
            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("正在等待模型回答…").font(.system(size: 14)).foregroundStyle(.secondary)
            }.padding(.top, 22)
        } else {
            VStack(spacing: 10) {
                Image(systemName: model.mode == .translate ? "character.book.closed" : "text.magnifyingglass")
                    .font(.system(size: 34, weight: .ultraLight)).foregroundStyle(accent.opacity(0.65))
                Text(model.mode == .translate ? "让文字跨越语言" : "理解含义，也读准发音")
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(.secondary)
                Text("选中文本后按 \(model.mode.shortcut)，或在上方输入后发送")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle().fill(model.isLoading ? accent : .white.opacity(0.3)).frame(width: 5, height: 5)
            Text(model.isLoading ? "生成中" : (model.wasCancelled ? "已停止" : (settings.configuration.model.isEmpty ? "尚未配置模型" : settings.configuration.model)))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Text("esc 关闭").font(.system(size: 11)).foregroundStyle(.tertiary)
            if model.isLoading {
                Button("停止", action: model.cancel).buttonStyle(.bordered)
            } else {
                Button { model.submit() } label: {
                    HStack(spacing: 12) {
                        Text(model.output.isEmpty ? "发送" : "重新发送").fontWeight(.semibold)
                        Text("⌘ ↩").opacity(0.65)
                    }.font(.system(size: 12)).padding(.horizontal, 5).padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent).tint(accent).foregroundStyle(.black)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
