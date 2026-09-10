import Foundation
import Testing
@testable import VoxInkUI

@MainActor struct ShortcutPreferenceTests {
    @Test func successfulRegistrationPersistsAndFailureKeepsPreviousCombination() throws {
        let name = "VoxInk.ShortcutTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let store = AppStore(preferences: preferences)
        store.configureShortcutRegistration { $0 != .controlOptionSpace }
        #expect(store.shortcutAvailable)
        store.setShortcutCombination(.optionShiftSpace)
        #expect(store.shortcutCombination == .optionShiftSpace)
        store.setShortcutCombination(.controlOptionSpace)
        #expect(store.shortcutCombination == .optionShiftSpace)
        #expect(store.shortcutAvailable)
        #expect(store.shortcutStatus.contains("仍使用"))
        #expect(AppStore(preferences: preferences).shortcutCombination == .optionShiftSpace)
        #expect(store.shortcutInstruction.contains("⌥ ⇧ Space"))
    }

    @Test func failedInitialRegistrationCanRecoverUsingAnotherCombination() {
        let store = AppStore(preferences: nil)
        store.configureShortcutRegistration { $0 == .controlOptionSpace }
        #expect(!store.shortcutAvailable)
        store.setShortcutCombination(.controlOptionSpace)
        #expect(store.shortcutAvailable)
        #expect(store.shortcutCombination == .controlOptionSpace)
    }

    @Test func cannotChangeUnconnectedShortcutOrDuringAnOperation() async {
        let store = AppStore(preferences: nil)
        store.setShortcutCombination(.optionShiftSpace)
        #expect(store.shortcutCombination == .optionSpace)
        store.configureShortcutRegistration { _ in true }
        store.scheduleFixedTextTest(after: .seconds(10))
        store.setShortcutCombination(.optionShiftSpace)
        #expect(store.shortcutCombination == .optionSpace)
        await store.cancel()
    }
}
