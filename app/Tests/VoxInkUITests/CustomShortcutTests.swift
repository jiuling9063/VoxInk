import Carbon
import Foundation
import Testing
@testable import VoxInkUI

struct CustomShortcutTests {
    @Test func oldPreferencesAndCustomCombinationsRoundTrip() throws {
        for preset in ShortcutCombination.allCases {
            #expect(ShortcutCombination(rawValue: preset.rawValue) == preset)
        }
        #expect(ShortcutCombination.optionSpace.rawValue == "optionSpace")
        let custom = try #require(ShortcutCombination(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | cmdKey)))
        #expect(ShortcutCombination(rawValue: custom.rawValue) == custom)
        #expect(custom.keyCode == UInt32(kVK_ANSI_K))
        #expect(custom.cancellationModifiers.count == 4)
        #expect(custom.cancellationModifiers.contains(UInt32(cmdKey)))
        #expect(ShortcutCombination(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) == .optionSpace)
    }

    @Test func invalidAndCommonSystemShortcutsAreRejected() {
        for (key, modifiers) in [(kVK_ANSI_A, 0), (kVK_ANSI_A, shiftKey), (kVK_Escape, optionKey),
                                  (kVK_Command, optionKey), (kVK_Space, controlKey),
                                  (kVK_Space, cmdKey | optionKey), (kVK_ANSI_C, cmdKey),
                                  (kVK_ANSI_3, cmdKey | shiftKey)] {
            #expect(ShortcutCombination(keyCode: UInt32(key), modifiers: UInt32(modifiers)) == nil)
        }
        for raw in ["custom-v1:40:0", "custom-v1:40:4294967295", "custom-v1:65536:256", "custom-v2:40:256", "custom-v1::", "unknown"] {
            #expect(ShortcutCombination(rawValue: raw) == nil)
        }
    }

    @MainActor @Test func failedReregistrationOfSameKeyRetriesAndReportsRestorationFailure() {
        let store = AppStore(preferences: nil)
        var accepts = true
        var attempts = 0
        store.configureShortcutRegistration { _ in attempts += 1; return accepts }
        #expect(store.beginShortcutRecording())
        accepts = false
        store.finishShortcutRecording(.optionSpace)
        #expect(attempts == 3)
        #expect(!store.shortcutAvailable)
        #expect(store.shortcutStatus.contains("恢复失败"))
        #expect(store.canChangeShortcut)
    }

    @MainActor @Test func captureSuspendsRestoresAndPersistsOnlyAcceptedCombination() throws {
        let name = "VoxInk.CustomShortcut.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let store = AppStore(preferences: preferences)
        let custom = try #require(ShortcutCombination(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | optionKey)))
        var suspended = false
        var accept = true
        store.configureShortcutSuspension { suspended = true }
        store.configureShortcutRegistration { combination in
            if !accept && combination == custom { return false }
            suspended = false
            return true
        }
        #expect(store.beginShortcutRecording())
        #expect(suspended && !store.canStart && !store.canChangeShortcut)
        #expect(!store.beginShortcutRecording())
        store.refreshPermissions()
        #expect(suspended)
        store.handleShortcutPressed()
        store.finishShortcutRecording()
        #expect(!suspended && store.canChangeShortcut)
        #expect(store.shortcutCombination == .optionSpace)
        #expect(store.beginShortcutRecording())
        accept = false
        store.finishShortcutRecording(custom)
        #expect(!suspended && store.shortcutAvailable)
        #expect(store.shortcutCombination == .optionSpace)
        #expect(store.shortcutStatus.contains("仍使用"))
        #expect(AppStore(preferences: preferences).shortcutCombination == .optionSpace)
        #expect(store.beginShortcutRecording())
        accept = true
        store.finishShortcutRecording(custom)
        #expect(!suspended && store.shortcutCombination == custom)
        #expect(AppStore(preferences: preferences).shortcutCombination == custom)
        store.finishShortcutRecording() // Sheet dismissal is idempotent.
        #expect(store.shortcutCombination == custom)
    }
}
