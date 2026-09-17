import Carbon
import Foundation

@MainActor
final class HotKeys {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var onPress: ((UInt32) -> Void)?
    private(set) var errors: [String] = []
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                          MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == 0x44414353 else { return OSStatus(eventNotHandledErr) }
            let keys = Unmanaged<HotKeys>.fromOpaque(context).takeUnretainedValue()
            let number = id.id
            Task { @MainActor in keys.onPress?(number) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { errors.append("Global shortcut handler failed (\(installed)). Menu commands remain available."); return }
        for (number, key) in [(UInt32(1), UInt32(kVK_ANSI_1)), (UInt32(2), UInt32(kVK_ANSI_2))] {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(key, UInt32(optionKey | cmdKey), EventHotKeyID(signature: 0x44414353, id: number),
                                            GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { refs.append(ref) }
            else { errors.append("Option-Command-\(number) unavailable (\(result)); another app may own it. Use the menu or release the conflicting shortcut and restart the switcher.") }
        }
    }
    deinit { for ref in refs { UnregisterEventHotKey(ref) }; if let handler { RemoveEventHandler(handler) } }
}
