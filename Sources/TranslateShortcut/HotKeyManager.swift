import Carbon
import AppKit
import TranslationCore

@MainActor
final class HotKeyManager {
    var onTrigger: ((TranslationMode) -> Void)?
    private var registrations: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var localMonitor: Any?
    private static let signature: OSType = 0x54534D43 // TSMC

    func start() -> String? {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                if id.signature == HotKeyManager.signature {
                    manager.onTrigger?(id.id == 1 ? .translate : .dictionary)
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return "无法安装快捷键处理器（\(installed)）。请重新启动应用。" }

        for (id, modifiers) in [(UInt32(1), UInt32(optionKey)), (UInt32(2), UInt32(optionKey | shiftKey))] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(kVK_ANSI_E), modifiers,
                                            EventHotKeyID(signature: Self.signature, id: id),
                                            GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                stop()
                return "快捷键 \(id == 1 ? "⌥ E" : "⇧ ⌥ E") 注册失败（\(status)）。请检查其他应用是否占用了此组合键，然后重新启动。"
            }
            registrations.append(ref)
        }
        // Text editors can interpret Option-E as an accent before menu key
        // equivalents run. Handle raw local events as well as global hotkeys.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            guard event.keyCode == UInt16(kVK_ANSI_E),
                  modifiers == .option || modifiers == [.option, .shift] else { return event }
            let mode: TranslationMode = modifiers.contains(.shift) ? .dictionary : .translate
            MainActor.assumeIsolated { self?.onTrigger?(mode) }
            return nil
        }
        return nil
    }

    func stop() {
        registrations.forEach { UnregisterEventHotKey($0) }
        registrations.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
    }
}
