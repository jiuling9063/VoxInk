import Carbon
import Testing
@testable import VoxInkUI

struct ShortcutLatchTests {
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
