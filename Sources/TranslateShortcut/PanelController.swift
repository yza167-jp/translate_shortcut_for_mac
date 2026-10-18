import AppKit
import SwiftUI
import TranslationCore

@MainActor
private final class TranslationPanel: NSPanel {
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onClose?() }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let model: TranslationViewModel
    private let panel: TranslationPanel
    private var previousApplication: NSRunningApplication?
    var isKeyWindow: Bool { panel.isKeyWindow }

    init(settings: SettingsStore, openSettings: @escaping () -> Void) {
        model = TranslationViewModel(settings: settings)
        panel = TranslationPanel(contentRect: NSRect(x: 0, y: 0, width: 740, height: 570),
                                 styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        panel.title = "Translate Shortcut"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.onClose = { [weak self] in self?.hide() }

        let effect = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 18
        effect.layer?.masksToBounds = true
        let hosting = NSHostingView(rootView: TranslationPanelView(model: model, settings: settings,
            openSettings: openSettings, close: { [weak self] in self?.hide() }))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
        panel.contentView = effect
    }

    func show(mode: TranslationMode, selection: SelectionResult, source: NSRunningApplication?) {
        if source?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = source }
        model.prepare(mode: mode, selection: selection, source: source?.localizedName)
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                y: max(frame.minY + 20, min(frame.maxY - panel.frame.height - 20,
                                           frame.midY - panel.frame.height / 2 + 60))))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.submit() }
    }

    func hide(restoreFocus: Bool = true) {
        model.cancel()
        panel.orderOut(nil)
        if restoreFocus { previousApplication?.activate(options: []) }
    }

    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { hide(restoreFocus: false) }
    }
}
