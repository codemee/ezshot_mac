import Carbon
import Foundation

@MainActor
final class GlobalHotKey {
    struct Modifiers: OptionSet {
        let rawValue: UInt32

        static let option = Modifiers(rawValue: UInt32(optionKey))
        static let shift = Modifiers(rawValue: UInt32(shiftKey))
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
    }

    private let id: UInt32
    private let keyCode: UInt32
    private let modifiers: Modifiers
    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?

    init(id: UInt32, keyCode: UInt32, modifiers: Modifiers, action: @escaping @MainActor () -> Void) {
        self.id = id
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    func register() {
        unregister()
        HotKeyRegistry.shared.installIfNeeded()
        HotKeyRegistry.shared.actions[id] = action

        let hotKeyID = EventHotKeyID(signature: fourCharCode("EZSR"), id: id)
        RegisterEventHotKey(
            keyCode,
            modifiers.rawValue,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        HotKeyRegistry.shared.actions.removeValue(forKey: id)
    }
}

@MainActor
private final class HotKeyRegistry {
    static let shared = HotKeyRegistry()

    var actions: [UInt32: @MainActor () -> Void] = [:]
    private var eventHandlerRef: EventHandlerRef?

    func installIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, _ in
            guard let event else {
                return noErr
            }

            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            Task { @MainActor in
                HotKeyRegistry.shared.actions[hotKeyID.id]?()
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }
}

private func fourCharCode(_ string: String) -> FourCharCode {
    string.utf8.reduce(0) { result, character in
        (result << 8) + FourCharCode(character)
    }
}
