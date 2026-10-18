import AppKit
import ApplicationServices

struct SelectionResult {
    var text = ""
    var notice: String?
}

@MainActor
enum SelectionReader {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func read(from application: NSRunningApplication?) async -> SelectionResult {
        guard isTrusted else {
            return SelectionResult(notice: "读取其他应用的选区需要辅助功能权限；你也可以直接输入文本。")
        }
        guard let application, application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return SelectionResult()
        }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.4)
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
           let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            let focused = unsafeDowncast(focusedValue, to: AXUIElement.self)
            AXUIElementSetMessagingTimeout(focused, 0.4)
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(focused, kAXSubroleAttribute as CFString, &subrole)
            if (subrole as? String) == kAXSecureTextFieldSubrole {
                return SelectionResult(notice: "安全输入框中的文本不会被读取，请手动输入要查询的内容。")
            }
            var selected: CFTypeRef?
            if AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selected) == .success,
               let text = selected as? String {
                return SelectionResult(text: text)
            }
            var rangeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
               let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() {
                let value = unsafeDowncast(rangeValue, to: AXValue.self)
                var range = CFRange()
                if AXValueGetValue(value, .cfRange, &range) {
                    if range.length == 0 { return SelectionResult() }
                    if AXUIElementCopyParameterizedAttributeValue(focused, kAXStringForRangeParameterizedAttribute as CFString,
                                                                  value, &selected) == .success,
                       let text = selected as? String { return SelectionResult(text: text) }
                }
            }
        }
        guard !Task.isCancelled else { return SelectionResult() }
        // This bounded operation must finish restoring the pasteboard even if a
        // newer shortcut cancels the caller. The caller serializes captures.
        return await Task { @MainActor in await copySelection(from: application) }.value
    }

    /// Some browsers and document viewers expose selection only through Copy.
    /// Restore all original pasteboard types, unless another copy has since occurred.
    private static func copySelection(from application: NSRunningApplication) async -> SelectionResult {
        let pasteboard = NSPasteboard.general
        var byteCount = 0
        var originals: [NSPasteboardItem] = []
        for item in pasteboard.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    byteCount += data.count
                    guard byteCount <= 16 * 1_024 * 1_024 else {
                        return SelectionResult(notice: "此应用未提供可读取的选区，请在下方输入文本。")
                    }
                    copy.setData(data, forType: type)
                }
            }
            originals.append(copy)
        }
        let originalChange = pasteboard.changeCount
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return SelectionResult() }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
            return SelectionResult()
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false) else { return SelectionResult() }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        // Complete pasteboard restoration even if the caller cancels this capture.
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(35))
            if pasteboard.changeCount != originalChange { break }
        }
        guard pasteboard.changeCount != originalChange else { return SelectionResult() }
        let copiedChange = pasteboard.changeCount
        let text = pasteboard.string(forType: .string) ?? ""
        if pasteboard.changeCount == copiedChange {
            pasteboard.clearContents()
            if !originals.isEmpty { pasteboard.writeObjects(originals) }
        }
        return SelectionResult(text: text)
    }
}
