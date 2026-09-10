import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

private actor SetupTranscriber: TranscriptionService {
    enum Failure: Error { case unavailable }
    let fails: Bool
    init(fails: Bool = false) { self.fails = fails }
    func prepare() async throws { if fails { throw Failure.unavailable } }
    func transcribe(url: URL) async throws -> String { "测试文字" }
    func cancel() async {}
}

@MainActor private final class SetupPaste: PasteService {
    var accessibilityGranted = false
    var outcome: PasteOutcome = .failed("目标已关闭")
    func requestAccessibility() -> Bool { accessibilityGranted }
    func captureTarget() -> PasteTarget? { PasteTarget(pid: 1, bundleID: "test", name: "测试框") }
    func paste(text: String, to target: PasteTarget, sessionID: UUID) async -> PasteOutcome { outcome }
    func cancel() {}
}

@MainActor struct SetupStateTests {
    private final class MicrophoneProbe {
        var status: MicrophoneAuthorization = .authorized
    }
    @Test func guideCannotCompleteUntilAllRequirementsAreReady() async throws {
        let name = "VoxInk.SetupTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let paste = SetupPaste()
        let store = AppStore(service: SetupTranscriber(), pasteService: paste, preferences: preferences,
            microphoneStatus: { .authorized })
        store.refreshPermissions()
        store.configureShortcutRegistration { _ in true }
        store.completeSetup()
        #expect(!store.setupCompleted)
        store.warmUp()
        for _ in 0..<1_000 where !store.canStart { await Task.yield() }
        #expect(store.modelState == .ready)
        #expect(!store.canCompleteSetup)
        paste.accessibilityGranted = true
        store.refreshPermissions()
        #expect(store.canCompleteSetup)
        store.completeSetup()
        #expect(preferences.bool(forKey: "setupCompleted"))
        let restored = AppStore(preferences: preferences)
        #expect(restored.setupCompleted)
        restored.showSetup()
        #expect(!restored.setupCompleted)
    }

    @Test func revokedPermissionsAppearWithoutDiscardingResult() async {
        let paste = SetupPaste(); paste.accessibilityGranted = true
        let microphone = MicrophoneProbe()
        let store = AppStore(service: SetupTranscriber(), pasteService: paste, preferences: nil,
            microphoneStatus: { microphone.status })
        await store.transcribePrepared(URL(fileURLWithPath: "/fixture.wav"))
        store.refreshPermissions()
        #expect(store.pastePermissionGranted)
        let previousText = store.transcript
        paste.accessibilityGranted = false; microphone.status = .denied
        store.refreshPermissions()
        #expect(!store.pastePermissionGranted)
        #expect(store.microphoneAuthorization == .denied)
        #expect(!previousText.isEmpty)
        #expect(store.transcript == previousText)
    }

    @Test func failedModelLoadOffersModelRecovery() async {
        let store = AppStore(service: SetupTranscriber(fails: true), preferences: nil)
        store.warmUp()
        for _ in 0..<1_000 where !store.canStart { await Task.yield() }
        #expect(store.modelState == .failed)
        #expect(store.recovery == .reloadModel)
    }

    @Test func pasteFailureDoesNotOfferModelReload() async {
        let paste = SetupPaste(); paste.accessibilityGranted = true
        let store = AppStore(service: SetupTranscriber(), pasteService: paste, preferences: nil)
        store.armFixedTextTest(); store.handleGlobalShortcut()
        for _ in 0..<1_000 where !store.canStart { await Task.yield() }
        #expect(store.phase == .failed)
        #expect(store.recovery == .checkTarget)
        #expect(!store.transcript.isEmpty)
    }

    @Test func sentPasteWithCleanupFailureNeverSuggestsAutomaticRetry() async {
        let paste = SetupPaste(); paste.accessibilityGranted = true
        paste.outcome = .sentWithCleanupFailure("粘贴已发出，恢复失败")
        let store = AppStore(service: SetupTranscriber(), pasteService: paste, preferences: nil)
        store.armFixedTextTest(); store.handleGlobalShortcut()
        for _ in 0..<1_000 where !store.canStart { await Task.yield() }
        #expect(store.recovery == .inspectClipboard)
        #expect(store.phase == .failed)
    }

    @Test func cancellingWorkerClearsReadyState() async {
        let store = AppStore(service: SetupTranscriber(), preferences: nil)
        store.warmUp()
        for _ in 0..<1_000 where !store.canStart { await Task.yield() }
        #expect(store.modelState == .ready)
        await store.cancel()
        #expect(store.modelState == .notLoaded)
    }
}
