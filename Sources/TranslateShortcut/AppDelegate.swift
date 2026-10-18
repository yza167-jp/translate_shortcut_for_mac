import AppKit
import SwiftUI
import TranslationCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let hotKeys = HotKeyManager()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var selectionTask: Task<Void, Never>?
    private var lastExternalApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private lazy var panel = PanelController(settings: settings) { [weak self] in self?.showSettings() }

    func applicationDidFinishLaunching(_ notification: Notification) {
        lastExternalApplication = NSWorkspace.shared.frontmostApplication
        installMenus()
        hotKeys.onTrigger = { [weak self] mode in self?.trigger(mode) }
        settings.shortcutError = hotKeys.start()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let pid = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid, pid != ProcessInfo.processInfo.processIdentifier {
                    self?.lastExternalApplication = NSRunningApplication(processIdentifier: pid)
                }
            }
        }
        if !settings.isConfigured || settings.shortcutError != nil { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        selectionTask?.cancel()
        hotKeys.stop()
        panel.model.cancel()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }

    private func trigger(_ mode: TranslationMode) {
        let previousCapture = selectionTask
        previousCapture?.cancel()
        if panel.isKeyWindow {
            let text = panel.model.input
            panel.show(mode: mode, selection: SelectionResult(text: text), source: lastExternalApplication)
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            showManualPanel(mode)
            return
        }
        let source = frontmost
        selectionTask = Task { [weak self] in
            await previousCapture?.value
            guard !Task.isCancelled else { return }
            let selection = await SelectionReader.read(from: source)
            guard let self, !Task.isCancelled else { return }
            panel.show(mode: mode, selection: selection, source: source)
        }
    }

    @objc private func translate() { trigger(.translate) }
    @objc private func dictionary() { trigger(.dictionary) }

    @objc private func showSettings() {
        selectionTask?.cancel()
        panel.hide(restoreFocus: false)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 790),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Translate Shortcut 设置"
            window.minSize = NSSize(width: 680, height: 660)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = NSHostingView(rootView: SettingsView(store: settings) { [weak self] mode in
                self?.showManualPanel(mode)
            })
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func showManualPanel(_ mode: TranslationMode) {
        settingsWindow?.orderOut(nil)
        panel.show(mode: mode, selection: SelectionResult(notice: SelectionReader.isTrusted ? nil :
            "授权辅助功能后可以读取其他应用的选区；也可以直接输入文本。"), source: nil)
    }

    private func item(_ title: String, action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    private func installMenus() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "Translate Shortcut")
        statusItem.button?.toolTip = "Translate Shortcut · ⌥E 翻译 · ⇧⌥E 词典"
        let menu = NSMenu()
        menu.addItem(item("翻译选中文本", action: #selector(translate), key: "e", modifiers: .option))
        menu.addItem(item("词典 / 手动查询", action: #selector(dictionary), key: "e", modifiers: [.option, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("设置…", action: #selector(showSettings), key: ","))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Translate Shortcut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        self.statusItem = statusItem

        // Standard Edit actions keep Copy/Paste/Select All available in native text editors.
        let main = NSMenu()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(item("设置…", action: #selector(showSettings), key: ","))
        applicationMenu.addItem(NSMenuItem(title: "退出 Translate Shortcut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let applicationItem = NSMenuItem()
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"),
                                        ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        main.addItem(editItem)
        let queries = NSMenu(title: "查询")
        queries.addItem(item("翻译选中文本", action: #selector(translate), key: "e", modifiers: .option))
        queries.addItem(item("词典 / 手动查询", action: #selector(dictionary), key: "e", modifiers: [.option, .shift]))
        let queriesItem = NSMenuItem(title: "查询", action: nil, keyEquivalent: "")
        queriesItem.submenu = queries
        main.addItem(queriesItem)
        NSApp.mainMenu = main
    }
}
