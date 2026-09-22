import AppKit
import ApplicationServices

// Only modifier events are buffered. Text, clipboard contents and mouse positions
// are never retained. Other Option operations are replayed before their next event.
struct RemoteOptionSpaceFilter {
    enum Delivery { case pass, buffer, discard }
    enum Signal { case pressed, released }
    struct Decision {
        var delivery: Delivery = .pass
        var flush = false
        var clear = false
        var stripOption = false
        var signal: Signal?
    }
    private enum Phase { case idle, pending, captured, draining }
    private var phase: Phase = .idle
    private var optionDown: Bool
    private var spaceCaptured = false
    private var recording = false
    var isQuiescent: Bool { phase == .idle }

    init(optionDown: Bool = false) { self.optionDown = optionDown }

    mutating func receive(type: CGEventType, key: Int64 = 0, flags: CGEventFlags,
                          repeating: Bool = false, inUU: Bool) -> Decision {
        let wasOptionDown = optionDown
        optionDown = flags.contains(.maskAlternate)
        let optionEvent = type == .flagsChanged && (key == 58 || key == 61)
        let spaceEvent = (type == .keyDown || type == .keyUp) && key == 49
        let relevant: CGEventFlags = [.maskAlternate, .maskControl, .maskCommand, .maskShift, .maskSecondaryFn]
        let onlyOption = flags.intersection(relevant) == .maskAlternate
        switch phase {
        case .idle:
            if inUU && optionEvent && onlyOption && !wasOptionDown {
                phase = .pending
                return .init(delivery: .buffer)
            }
        case .pending:
            if inUU && optionEvent && optionDown && onlyOption {
                return .init(delivery: .buffer)
            }
            if inUU && spaceEvent && type == .keyDown && onlyOption && !repeating {
                phase = .captured; spaceCaptured = true; recording = true
                return .init(delivery: .discard, clear: true, signal: .pressed)
            }
            if inUU && type == .mouseMoved {
                return .init(stripOption: true)
            }
            phase = .idle
            return .init(flush: true)
        case .captured, .draining:
            let draining = phase == .draining
            if optionEvent {
                var signal: Signal?
                if !optionDown && recording { recording = false; signal = .released }
                if !optionDown && !spaceCaptured { phase = .idle }
                return .init(delivery: .discard, signal: signal)
            }
            if spaceEvent {
                if type == .keyUp && spaceCaptured {
                    let signal: Signal? = recording ? .released : nil
                    spaceCaptured = false; recording = false
                    if !optionDown { phase = .idle }
                    return .init(delivery: .discard, signal: signal)
                }
                if type == .keyDown && spaceCaptured { return .init(delivery: .discard) }
                if type == .keyDown && optionDown && onlyOption && !repeating && !draining && inUU {
                    spaceCaptured = true; recording = true
                    return .init(delivery: .discard, signal: .pressed)
                }
            }
            return .init(stripOption: true)
        }
        return .init()
    }

    mutating func interrupt(optionDown: Bool, spaceDown: Bool) -> Bool {
        let shouldCancel = recording
        recording = false
        self.optionDown = optionDown
        spaceCaptured = spaceCaptured && spaceDown
        if phase != .idle { phase = optionDown || spaceCaptured ? .draining : .idle }
        return shouldCancel
    }

    static func removingOption(from flags: CGEventFlags) -> CGEventFlags {
        // Device-specific left/right Option masks from IOKit hidsystem/IOLLEvent.h.
        CGEventFlags(rawValue: flags.rawValue & ~UInt64(0x20 | 0x40) & ~CGEventFlags.maskAlternate.rawValue)
    }
}

@MainActor final class RemoteOptionSpaceMonitor: RemoteShortcutMonitoring {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var buffered: [CGEvent] = []
    private var filter = RemoteOptionSpaceFilter()
    private let pressed: () -> Void
    private let released: () -> Void
    private let interrupted: () -> Void
    var isQuiescent: Bool { filter.isQuiescent }
    var isActive: Bool { AXIsProcessTrusted() && tap.map { CGEvent.tapIsEnabled(tap: $0) } == true }

    init(pressed: @escaping () -> Void, released: @escaping () -> Void, interrupted: @escaping () -> Void) {
        self.pressed = pressed; self.released = released; self.interrupted = interrupted
    }

    func start() -> Bool {
        if let tap { return CGEvent.tapIsEnabled(tap: tap) }
        guard AXIsProcessTrusted() else { return false }
        let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { proxy, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let pass = MainActor.assumeIsolated {
                    Unmanaged<RemoteOptionSpaceMonitor>.fromOpaque(context).takeUnretainedValue()
                        .receive(proxy: proxy, type: type, event: event)
                }
                return pass ? Unmanaged.passUnretained(event) : nil
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap); return false
        }
        self.tap = tap; self.source = source
        filter = RemoteOptionSpaceFilter(optionDown: CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate))
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return CGEvent.tapIsEnabled(tap: tap)
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil; buffered.removeAll(); filter = RemoteOptionSpaceFilter()
    }

    private func receive(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            buffered.removeAll()
            let cancel = filter.interrupt(
                optionDown: CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate),
                spaceDown: CGEventSource.keyState(.combinedSessionState, key: 49))
            if cancel { interrupted() }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        let decision = filter.receive(type: type, key: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags, repeating: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            inUU: NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.netease.uuremote")
        if decision.flush {
            for pending in buffered { pending.tapPostEvent(proxy) }
            buffered.removeAll()
        }
        if decision.clear { buffered.removeAll() }
        if decision.delivery == .buffer {
            guard buffered.count < 4, let copy = event.copy() else {
                for pending in buffered { pending.tapPostEvent(proxy) }
                buffered.removeAll()
                filter = RemoteOptionSpaceFilter(optionDown: event.flags.contains(.maskAlternate))
                return true
            }
            buffered.append(copy)
        }
        if decision.stripOption { event.flags = RemoteOptionSpaceFilter.removingOption(from: event.flags) }
        switch decision.signal {
        case .pressed: pressed()
        case .released: released()
        case nil: break
        }
        return decision.delivery == .pass
    }
}
