# Translate Shortcut for Mac

原生 macOS 菜单栏翻译工具。选中文字后按下快捷键，在带有背景模糊效果的浮窗中获取大模型回答。

| 快捷键 | 功能 |
| --- | --- |
| **Option + E** | 将选中文本翻译为目标语言 |
| **Shift + Option + E** | 英文释义、音标，再翻译为目标语言；没有选区时手动输入 |
| **Command + Return** | 在浮窗中发送或重新发送 |
| **Escape** | 关闭浮窗并取消当前请求 |

两种模式都支持手动输入、流式显示、停止生成和复制回答。目标语言默认是 `Chinese`。

## 安装与运行

要求 macOS 14 或更新版本。源码构建需要 Swift 6 / Xcode 16 或更新版本，无第三方依赖。

## 获取项目

```bash
git clone https://github.com/yza167-jp/translate_shortcut_for_mac.git
cd translate_shortcut_for_mac
bash scripts/build-app.sh
open "dist/Translate Shortcut.app"
```

构建脚本生成可运行的 `.app`，并进行本机 ad-hoc 签名。也可以将应用复制到 `/Applications` 后运行。请在首次授权前选定稳定的安装位置。

首次启动会打开设置窗口，之后通过菜单栏的文字气泡图标打开设置或退出应用。

## 首次设置

1. 填写 **Base URL**：支持 OpenAI 兼容的 Chat Completions 接口，例如 `https://api.openai.com/v1`。也可填写完整的 `/chat/completions` 地址。
2. 填写服务商提供的 **模型 ID** 和 **API Key**。点击“测试连接”发送一个简短请求，再点击“保存设置”。测试请求可能产生服务商的 API 费用。
3. 选择目标语言，或输入任意语言名称。需要时编辑两条提示词。
4. 点击“去授权”，在系统设置 → 隐私与安全性 → 辅助功能中允许 **Translate Shortcut**。
5. 回到任意文本应用，选中文字并使用快捷键。

远程 API 地址必须使用 HTTPS。本机服务可使用 `http://localhost:端口/v1` 或 `http://127.0.0.1:端口/v1`，且可不填 API Key。仅支持兼容的 Chat Completions 协议；Anthropic Messages、Gemini 原生接口等需要兼容网关。

本次实测使用的 DeepSeek 配置：

| 设置 | 值 |
| --- | --- |
| Base URL | `https://api.deepseek.com` |
| 模型 ID | `deepseek-flash` |
| 目标语言 | `Chinese` |

API Key 使用自己的 DeepSeek API Key，在设置窗口中填写并保存。

## 提示词

翻译模式默认：

```text
please translate {selection} into {language}, just give me simple answer:
```

词典模式默认：

```text
now you're a dictionary-bot, please explain "{argument name="Text"}" to me with English and tell me how to pronounce phonetically, after that translate it/them into {language}, just give me simple answer:
```

`{selection}`、`{Text}`、`{text}` 和 `{argument name="Text"}` 均替换为选区或手动输入的文本；`{language}` 替换为目标语言。每条提示词需保留至少一个文本占位符。替换只执行一次，输入文本中的类似占位符不会被再次展开。

## 选区与隐私

- 优先通过 macOS 辅助功能读取当前聚焦元素的选区。部分应用需要临时发送 `⌘C`，随后恢复原剪贴板内容。
- 没有选区或未授权时，浮窗提供手动输入入口。安全输入框不会被读取；部分应用、受保护内容及 macOS 的安全输入模式可能限制选区读取或全局快捷键。
- 仅主动触发查询时读取选区。文本只发送到用户配置的 API 服务；应用不保存查询历史，也不记录 API Key 或请求内容。
- API Key 存储在 macOS 钥匙串中，其余设置保存在应用的 UserDefaults 中。
- 重建或移动本地签名的应用后，macOS 可能要求重新授权辅助功能；必要时在系统设置中移除旧条目，再添加当前 `.app`。
- 若快捷键被其他应用占用，设置页会显示注册错误；解除冲突后重启应用。

## 开发与验证

```bash
swift test
swift build
bash scripts/build-app.sh
```

也可以直接用 Xcode 打开 `Package.swift`。使用选区读取时，请运行打包后的 `.app`，以便系统权限绑定到稳定的应用标识。

```text
Sources/TranslationCore/    提示词、配置验证、流式 / 非流式 API 客户端
Sources/TranslateShortcut/  菜单栏、全局快捷键、选区读取、SwiftUI / AppKit 界面
Tests/TranslationCoreTests/ 不访问真实 API 的请求、响应和错误处理测试
Resources/Info.plist        应用元信息
scripts/                   构建、图标生成
```

项目使用原生 `NSVisualEffectView` 实现背景模糊，SwiftUI 绘制内容，Carbon 注册全局快捷键，URLSession 调用 API。网络请求支持取消；关闭浮窗或发起新查询会取消前一个请求。

2026-10-18 已在 Apple Silicon Mac 上完成以下验证：

- 18 项自动化测试通过，覆盖提示词、配置与请求验证、流式和非流式响应、错误处理及取消请求。
- Release 构建和应用签名检查通过。
- DeepSeek 真实连接及回答通过；使用 Swift/CGEvent 从 TextEdit 发送系统级快捷键，确认 `Option + E` 将 `The early bird catches the worm.` 译为“早起的鸟儿有虫吃。”，`Shift + Option + E` 为 `serendipity` 返回英文释义、音标和中文翻译。
- 没有选区时，词典浮窗提供空输入框，不沿用上次查询文本；手动输入与发送流程已验证。

## Git 忽略规则

`.gitignore` 覆盖 macOS 元数据、Swift/Xcode 构建产物、`dist/` 应用包、用户工程状态和本地环境文件。项目源码、工程共享配置和 `Package.resolved` 可以正常纳入版本控制。
