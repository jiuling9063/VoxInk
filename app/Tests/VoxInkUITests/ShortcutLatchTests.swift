import Carbon
import Testing
@testable import VoxInkUI

struct ShortcutLatchTests {
    @MainActor @Test func systemDeliveryStartsAndStopsWithoutARemoteMonitorDelivery() {
        var starts = 0
        var stops = 0
        let controller = GlobalShortcutController(toggle: { starts += 1 }, released: { stops += 1 }, cancel: {})

        controller.handleShortcutEvent(id: 1, pressed: true)
        #expect(starts == 1 && stops == 0)
        controller.handleShortcutEvent(id: 1, pressed: false)
        #expect(starts == 1 && stops == 1)
    }

    @MainActor @Test func systemAndRemoteDeliveriesDoNotDuplicateRecordingAcrossConsecutiveGestures() {
        var starts = 0
        var stops = 0
        let controller = GlobalShortcutController(toggle: { starts += 1 }, released: { stops += 1 }, cancel: {})

        for gesture in 1...20 {
            // Both event sources can report the same held shortcut.
            controller.handleShortcutEvent(id: 1, pressed: true)
            controller.handleShortcutEvent(id: 1, pressed: true)
            #expect(starts == gesture && stops == gesture - 1)
            controller.handleShortcutEvent(id: 1, pressed: false)
            controller.handleShortcutEvent(id: 1, pressed: false)
            #expect(starts == gesture && stops == gesture)
        }
    }

    @MainActor @Test func cancellationDoesNotConsumeTheRecordingKeyRelease() {
        var stops = 0
        var cancellations = 0
        let controller = GlobalShortcutController(toggle: {}, released: { stops += 1 }, cancel: { cancellations += 1 })

        controller.handleShortcutEvent(id: 1, pressed: true)
        controller.handleShortcutEvent(id: 2, pressed: true)
        controller.handleShortcutEvent(id: 2, pressed: true)
        controller.handleShortcutEvent(id: 2, pressed: false)
        controller.handleShortcutEvent(id: 1, pressed: false)
        #expect(cancellations == 1 && stops == 1)
    }

    @Test func escapeCoversHeldAndPartiallyReleasedRecordingModifiers() {
        #expect(Set(ShortcutCombination.optionSpace.cancellationModifiers) == Set([0, UInt32(optionKey)]))
        #expect(Set(ShortcutCombination.optionShiftSpace.cancellationModifiers) ==
                Set([0, UInt32(optionKey), UInt32(shiftKey), UInt32(optionKey | shiftKey)]))
        #expect(Set(ShortcutCombination.controlOptionSpace.cancellationModifiers) ==
                Set([0, UInt32(optionKey), UInt32(controlKey), UInt32(optionKey | controlKey)]))
    }

    @Test func releaseIsDeliveredOnlyOnceForAnActualPress() {
        var latch = ShortcutLatch()
        let orphan = latch.release(id: 1)
        let pressed = latch.receive(id: 1, pressed: true)
        let repeated = latch.receive(id: 1, pressed: true)
        let released = latch.release(id: 1)
        let duplicate = latch.release(id: 1)
        #expect(!orphan && pressed && !repeated && released && !duplicate)
    }
    @Test func heldShortcutDoesNotToggleRepeatedly() {
        var latch = ShortcutLatch()
        let first = latch.receive(id: 1, pressed: true)
        let repeated = latch.receive(id: 1, pressed: true)
        let release = latch.receive(id: 1, pressed: false)
        let next = latch.receive(id: 1, pressed: true)
        #expect(first && !repeated && !release && next)
    }
    @Test func escapeAndToggleHaveIndependentReleaseState() {
        var latch = ShortcutLatch()
        let toggle = latch.receive(id: 1, pressed: true)
        let escape = latch.receive(id: 2, pressed: true)
        latch.reset()
        let afterReset = latch.receive(id: 1, pressed: true)
        #expect(toggle && escape && afterReset)
    }
}
