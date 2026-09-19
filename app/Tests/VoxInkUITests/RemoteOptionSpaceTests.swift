import CoreGraphics
import Testing
@testable import VoxInkUI

struct RemoteOptionSpaceTests {
    private func begin(_ filter: inout RemoteOptionSpaceFilter) -> RemoteOptionSpaceFilter.Decision {
        filter.receive(type: .flagsChanged, key: 58, flags: .maskAlternate, inUU: true)
    }
    private func press(_ filter: inout RemoteOptionSpaceFilter) -> RemoteOptionSpaceFilter.Decision {
        filter.receive(type: .keyDown, key: 49, flags: .maskAlternate, inUU: true)
    }

    @Test func capturesComboWithoutForwardingOptionOrSpace() {
        var filter = RemoteOptionSpaceFilter()
        #expect(begin(&filter).delivery == .buffer)
        let down = press(&filter)
        #expect(down.delivery == .discard && down.clear && down.signal == .pressed)
        let up = filter.receive(type: .keyUp, key: 49, flags: .maskAlternate, inUU: true)
        #expect(up.delivery == .discard && up.signal == .released)
        let optionUp = filter.receive(type: .flagsChanged, key: 58, flags: [], inUU: true)
        #expect(optionUp.delivery == .discard && optionUp.signal == nil)
        #expect(filter.isQuiescent)
    }

    @Test func releasingOptionFirstStillConsumesTheLaterSpaceRelease() {
        var filter = RemoteOptionSpaceFilter()
        _ = begin(&filter); _ = press(&filter)
        let optionUp = filter.receive(type: .flagsChanged, key: 58, flags: [], inUU: true)
        #expect(optionUp.signal == .released && optionUp.delivery == .discard)
        #expect(!filter.isQuiescent)
        let up = filter.receive(type: .keyUp, key: 49, flags: [], inUU: true)
        #expect(up.signal == nil && up.delivery == .discard && filter.isQuiescent)
    }

    @Test func otherAppsKeepTheirOriginalEvents() {
        var filter = RemoteOptionSpaceFilter()
        let option = filter.receive(type: .flagsChanged, key: 58, flags: .maskAlternate, inUU: false)
        let space = filter.receive(type: .keyDown, key: 49, flags: .maskAlternate, inUU: false)
        #expect(option.delivery == .pass && space.delivery == .pass)
        #expect(option.signal == nil && space.signal == nil && filter.isQuiescent)
    }

    @Test func ordinaryOptionTapReplaysItsPressBeforeItsRelease() {
        var filter = RemoteOptionSpaceFilter()
        _ = begin(&filter)
        let up = filter.receive(type: .flagsChanged, key: 58, flags: [], inUU: true)
        #expect(up.flush && up.delivery == .pass && up.signal == nil && filter.isQuiescent)
    }

    @Test func optionTypingClickScrollAndOtherModifiersFlushInOrder() {
        let alternatives: [(CGEventType, Int64, CGEventFlags)] = [
            (.keyDown, 0, .maskAlternate), (.leftMouseDown, 0, .maskAlternate),
            (.rightMouseDown, 0, .maskAlternate), (.scrollWheel, 0, .maskAlternate),
            (.flagsChanged, 56, [.maskAlternate, .maskShift])
        ]
        for (type, key, flags) in alternatives {
            var filter = RemoteOptionSpaceFilter()
            _ = begin(&filter)
            let result = filter.receive(type: type, key: key, flags: flags, inUU: true)
            #expect(result.flush && result.delivery == .pass && !result.stripOption)
            #expect(result.signal == nil && filter.isQuiescent)
        }
    }

    @Test func mouseMovementDoesNotLeakThePendingModifierOrStartRecording() {
        var filter = RemoteOptionSpaceFilter()
        _ = begin(&filter)
        let result = filter.receive(type: .mouseMoved, flags: .maskAlternate, inUU: true)
        #expect(result.delivery == .pass && result.stripOption && !result.flush && result.signal == nil)
        #expect(press(&filter).signal == .pressed)
    }

    @Test func repeatedKeysDoNotStartOrStopTwice() {
        var filter = RemoteOptionSpaceFilter()
        _ = begin(&filter); _ = press(&filter)
        for _ in 0..<10 {
            let repeatKey = filter.receive(type: .keyDown, key: 49, flags: .maskAlternate, repeating: true, inUU: true)
            #expect(repeatKey.delivery == .discard && repeatKey.signal == nil)
        }
        #expect(filter.receive(type: .keyUp, key: 49, flags: .maskAlternate, inUU: true).signal == .released)
        #expect(press(&filter).signal == .pressed)
    }

    @Test func optionAlreadyHeldAtStartupOrUsedForAnotherKeyDoesNotStart() {
        var initial = RemoteOptionSpaceFilter(optionDown: true)
        #expect(press(&initial).signal == nil)
        var filter = RemoteOptionSpaceFilter()
        _ = begin(&filter)
        _ = filter.receive(type: .keyDown, key: 0, flags: .maskAlternate, inUU: true)
        #expect(press(&filter).signal == nil)
    }

    @Test func rightOptionAndBothOptionKeysStayLocalForRecording() {
        var filter = RemoteOptionSpaceFilter()
        let right: CGEventFlags = [.maskAlternate, CGEventFlags(rawValue: 0x40)]
        #expect(filter.receive(type: .flagsChanged, key: 61, flags: right, inUU: true).delivery == .buffer)
        #expect(filter.receive(type: .flagsChanged, key: 58, flags: [right, CGEventFlags(rawValue: 0x20)], inUU: true).delivery == .buffer)
        #expect(press(&filter).signal == .pressed)
        let oneUp = filter.receive(type: .flagsChanged, key: 58, flags: right, inUU: true)
        #expect(oneUp.delivery == .discard && oneUp.signal == nil)
        #expect(filter.receive(type: .flagsChanged, key: 61, flags: [], inUU: true).signal == .released)
    }

    @Test func interruptedRecordingCancelsAndDrainsHeldKeysWithoutRestarting() {
        var filter = RemoteOptionSpaceFilter()
        _ = begin(&filter); _ = press(&filter)
        let cancelled = filter.interrupt(optionDown: true, spaceDown: true)
        #expect(cancelled)
        #expect(filter.receive(type: .keyUp, key: 49, flags: .maskAlternate, inUU: true).signal == nil)
        #expect(press(&filter).signal == nil)
        #expect(filter.receive(type: .flagsChanged, key: 58, flags: [], inUU: true).delivery == .discard)
        #expect(filter.isQuiescent)
        _ = begin(&filter)
        #expect(press(&filter).signal == .pressed)
    }

    @Test func focusChangeFlushesUnusedOptionButDoesNotLeakCapturedReleases() {
        var pending = RemoteOptionSpaceFilter()
        _ = begin(&pending)
        #expect(pending.receive(type: .keyDown, key: 0, flags: .maskAlternate, inUU: false).flush)
        var active = RemoteOptionSpaceFilter()
        _ = begin(&active); _ = press(&active)
        let up = active.receive(type: .keyUp, key: 49, flags: .maskAlternate, inUU: false)
        #expect(up.delivery == .discard && up.signal == .released)
        #expect(active.receive(type: .flagsChanged, key: 58, flags: [], inUU: false).delivery == .discard)
    }

    @Test func otherKeysKeepControlShiftAndCommandWhileCapturedOptionIsRemoved() {
        let flags: CGEventFlags = [.maskAlternate, .maskCommand, .maskShift, .maskControl, CGEventFlags(rawValue: 0x60)]
        #expect(RemoteOptionSpaceFilter.removingOption(from: flags) == [.maskCommand, .maskShift, .maskControl])
        var filter = RemoteOptionSpaceFilter()
        _ = begin(&filter); _ = press(&filter)
        let escape = filter.receive(type: .keyDown, key: 53, flags: .maskAlternate, inUU: true)
        #expect(escape.delivery == .pass && escape.stripOption && escape.signal == nil)
    }
}
