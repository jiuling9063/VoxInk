import Carbon
import Foundation

struct ShortcutLatch {
    private var held: Set<UInt32> = []
    mutating func receive(id: UInt32, pressed: Bool) -> Bool {
        if !pressed { held.remove(id); return false }
        return held.insert(id).inserted
    }
    mutating func reset() { held.removeAll() }
    mutating func release(id: UInt32) -> Bool { held.remove(id) != nil }
}

@MainActor public final class GlobalShortcutController {
    private var handler: EventHandlerRef?
    private var toggleKey: EventHotKeyRef?
    private var escapeKeys: [EventHotKeyRef] = []
    private var combination: ShortcutCombination?
    private var latch = ShortcutLatch()
    private let toggle: () -> Void
    private let released: () -> Void
    private let cancel: () -> Void
    public init(toggle: @escaping () -> Void, released: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.toggle = toggle; self.released = released; self.cancel = cancel
    }

    public func start(combination: ShortcutCombination = .optionSpace) -> Bool {
        guard handler == nil else { return toggleKey != nil }
        var events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            guard result == noErr, key.signature == 0x564F5849 else { return OSStatus(eventNotHandledErr) }
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            MainActor.assumeIsolated {
                let controller = Unmanaged<GlobalShortcutController>.fromOpaque(context).takeUnretainedValue()
                controller.receive(id: key.id, pressed: pressed)
            }
            return noErr
        }, events.count, &events, context, &handler)
        guard installed == noErr else { stop(); return false }
        let registered = RegisterEventHotKey(UInt32(kVK_Space), combination.modifiers,
            EventHotKeyID(signature: 0x564F5849, id: 1), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &toggleKey)
        guard registered == noErr else { stop(); return false }
        self.combination = combination
        return true
    }

    public func changeShortcut(to combination: ShortcutCombination) -> Bool {
        guard handler != nil else { return start(combination: combination) }
        if self.combination == combination, toggleKey != nil { return true }
        var candidate: EventHotKeyRef?
        let result = RegisterEventHotKey(UInt32(kVK_Space), combination.modifiers,
            EventHotKeyID(signature: 0x564F5849, id: 1), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &candidate)
        // Keep the existing registration until the replacement is known to work.
        guard result == noErr, let candidate else { return false }
        if let toggleKey { UnregisterEventHotKey(toggleKey) }
        toggleKey = candidate
        self.combination = combination
        latch.reset()
        return true
    }

    @discardableResult public func setCancellationEnabled(_ enabled: Bool) -> Bool {
        if enabled, escapeKeys.isEmpty {
            guard let combination else { return false }
            var candidates: [EventHotKeyRef] = []
            for modifiers in combination.cancellationModifiers {
                var candidate: EventHotKeyRef?
                let result = RegisterEventHotKey(UInt32(kVK_Escape), modifiers,
                    EventHotKeyID(signature: 0x564F5849, id: 2), GetApplicationEventTarget(),
                    OptionBits(kEventHotKeyExclusive), &candidate)
                guard result == noErr, let candidate else {
                    for registered in candidates { UnregisterEventHotKey(registered) }
                    return false
                }
                candidates.append(candidate)
            }
            escapeKeys = candidates
        }
        if !enabled {
            for escapeKey in escapeKeys { UnregisterEventHotKey(escapeKey) }
            escapeKeys.removeAll()
            _ = latch.receive(id: 2, pressed: false)
        }
        return true
    }

    public func stop() {
        if let toggleKey { UnregisterEventHotKey(toggleKey) }
        for escapeKey in escapeKeys { UnregisterEventHotKey(escapeKey) }
        if let handler { RemoveEventHandler(handler) }
        toggleKey = nil; escapeKeys.removeAll(); handler = nil; combination = nil; latch.reset()
    }

    private func receive(id: UInt32, pressed: Bool) {
        if !pressed {
            if latch.release(id: id), id == 1 { released() }
            return
        }
        guard latch.receive(id: id, pressed: pressed) else { return }
        switch id { case 1: toggle(); case 2: cancel(); default: break }
    }
}
