import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

@MainActor struct ShortcutPreferenceTests {
    @Test func legacyRemoteConfigurationMigratesOnceAndRemovalSticks() throws {
        let name = "VoxInk.RemoteMigration.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set("Mini", forKey: "uuMacDevices")
        let store = AppStore(preferences: preferences)
        #expect(store.remoteApplications.count == 1)
        #expect(store.remoteApplications.first?.name == "已保存的远程工具")
        store.removeRemoteApplication("com.netease.uuremote")
        #expect(AppStore(preferences: preferences).remoteApplications.isEmpty)
    }

    @Test func remoteApplicationProfilesPersistUpdateAndRemoveIndependently() throws {
        let name = "VoxInk.RemoteApplications.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let store = AppStore(preferences: preferences)
        store.setRemoteApplication(.init(bundleID: "test.one", name: "One", usesControl: true))
        store.setRemoteApplication(.init(bundleID: "test.two", name: "Two"))
        store.setRemoteApplication(.init(bundleID: "test.one", name: "One", usesControl: false))
        let restored = AppStore(preferences: preferences)
        #expect(restored.remoteApplications.count == 2)
        #expect(restored.remoteApplications.allSatisfy { !$0.usesControl })
        restored.removeRemoteApplication("test.one")
        #expect(AppStore(preferences: preferences).remoteApplications.map(\.bundleID) == ["test.two"])
    }
    @Test func remoteDeviceNamesPersistSeparately() throws {
        let name = "VoxInk.RemoteDevicesTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let store = AppStore(preferences: preferences)
        store.setUUDevices(mac: "Mini", windows: "PC")
        let restored = AppStore(preferences: preferences)
        #expect(restored.uuMacDevices == "Mini")
        #expect(restored.uuWindowsDevices == "PC")
    }
    @Test func refreshingPermissionsRetriesUnavailableShortcut() {
        let store = AppStore(preferences: nil)
        var available = false
        store.configureShortcutRegistration { _ in available }
        #expect(!store.shortcutAvailable)
        available = true
        store.refreshPermissions()
        #expect(store.shortcutAvailable)
    }
    @Test func uuWindowsPasteIsOptInAndPersists() throws {
        let name = "VoxInk.WindowsPasteTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let store = AppStore(preferences: preferences)
        #expect(!store.uuWindowsPaste)
        store.setUUWindowsPaste(true)
        #expect(AppStore(preferences: preferences).uuWindowsPaste)
        store.setUUWindowsPaste(false)
        #expect(!AppStore(preferences: preferences).uuWindowsPaste)
    }
    @Test func remoteTimingDefaultsToStableAndPersistsSelection() throws {
        let name = "VoxInk.RemoteTimingTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let store = AppStore(preferences: preferences)
        #expect(store.remotePasteTiming == .stable)
        store.setRemotePasteTiming(.faster)
        #expect(AppStore(preferences: preferences).remotePasteTiming == .faster)
        preferences.set("unknown", forKey: "remotePasteTiming")
        #expect(AppStore(preferences: preferences).remotePasteTiming == .stable)
    }

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
