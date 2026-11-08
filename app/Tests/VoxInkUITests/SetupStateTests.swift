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
    var target = PasteTarget(pid: 1, bundleID: "test", name: "测试框")
    func requestAccessibility() -> Bool { accessibilityGranted }
    func captureTarget() -> PasteTarget? { target }
    func paste(text: String, to target: PasteTarget, sessionID: UUID) async -> PasteOutcome { outcome }
    func cancel() {}
}

@MainActor private final class SetupRecorder: AudioRecording {
    var isRecording = false
    func requestPermission() async -> Bool { true }
    func start() throws { isRecording = true }
    func stop() throws -> URL { isRecording = false; return URL(fileURLWithPath: "/setup-fixture.wav") }
    func sample() -> AudioCaptureSample { .init(elapsed: 2, level: 0.5) }
    func cancel() { isRecording = false }
}

@MainActor struct SetupStateTests {
    @Test func migratesOldTrialStepsAndDefaultsToLocal() throws {
        for old in ["text", "speech"] {
            let data = try JSONEncoder().encode(old)
            #expect(try JSONDecoder().decode(SetupStep.self, from: data) == .trial)
        }
        #expect(SetupProgress().usage == .local)
    }

    @Test func downloadsWhileUserCanTestDelivery() async throws {
        let paste = SetupPaste()
        paste.accessibilityGranted = true
        paste.outcome = .sent
        let store = AppStore(service: SetupTranscriber(), pasteService: paste, preferences: nil, microphoneStatus: { .authorized })
        store.refreshPermissions()
        store.configureShortcutRegistration { _ in true }
        store.chooseSetupUsage(.local)
        #expect(store.setupProgress.step == .preparation && store.canStartSetupDownload)
        store.prepareAndAdvanceSetup()
        #expect(store.setupProgress.step == .trial && store.transcriptionPreparing)
        #expect(!store.canCompleteSetup)
        store.startSetupTextTest()
        #expect(store.fixedTextTestArmed)
        store.handleGlobalShortcut()
        try await waitUntil { store.canStart && store.transcriptionReady }
        store.confirmSetupTrial(true)
        #expect(store.setupProgress.textConfirmed && !store.canCompleteSetup)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(predicate())
    }

    private func readyStore(_ paste: SetupPaste, preferences: UserDefaults? = nil) async throws -> AppStore {
        paste.accessibilityGranted = true
        let store = AppStore(service: SetupTranscriber(), pasteService: paste, recorder: SetupRecorder(),
            preferences: preferences, microphoneStatus: { .authorized }, audioPreparer: { $0 }, audioCleaner: { _ in },
            clipboardWriter: { _ in true })
        store.refreshPermissions()
        store.configureShortcutRegistration { _ in true }
        store.warmUp()
        try await waitUntil { store.canStart }
        return store
    }

    private func reachTrialStep(_ store: AppStore, remote: Bool) {
        if remote && !store.setupProgress.usage.needsRemote { store.setSetupUsage(.remote) }
        store.advanceSetup()
        store.advanceSetup()
        if remote {
            store.setRemoteApplication(.init(bundleID: "test", name: "远程测试"))
            store.confirmSetupClipboardSync(true)
            store.advanceSetup()
        }
        #expect(store.setupProgress.step == .trial)
    }

    private func sendTestText(_ store: AppStore) async throws {
        store.startSetupTextTest()
        store.handleGlobalShortcut()
        try await waitUntil { store.canStart }
    }

    private func sendSpeech(_ store: AppStore) async throws {
        store.handleShortcutPressed()
        try await waitUntil { store.phase == .recording }
        store.handleShortcutReleased()
        try await waitUntil { store.canStart }
    }

    @Test func fixedTextShortcutCanOnlyConfirmTextAndIsConsumedOnce() async throws {
        let paste = SetupPaste(); paste.outcome = .sent
        let store = try await readyStore(paste)
        reachTrialStep(store, remote: false)
        store.startSetupTextTest()
        store.handleShortcutPressed()
        store.handleShortcutReleased()
        try await waitUntil { store.setupTrialCanConfirm }
        #expect(store.isConfirmingFixedText && !store.fixedTextTestArmed)
        store.confirmSetupTrial(true)
        #expect(store.setupProgress.textConfirmed && !store.setupProgress.speechConfirmed)
        #expect(!store.canCompleteSetup)
        try await sendSpeech(store)
        #expect(!store.isConfirmingFixedText)
        store.confirmSetupTrial(true)
        #expect(store.canCompleteSetup)
    }

    @Test func anotherOperationExpiresTheArmedTextShortcutAndPendingConfirmation() async throws {
        let paste = SetupPaste(); paste.outcome = .sent
        let store = try await readyStore(paste)
        reachTrialStep(store, remote: false)
        store.startSetupTextTest()
        store.warmUp()
        try await waitUntil { store.canStart }
        #expect(!store.fixedTextTestArmed)
        try await sendSpeech(store)
        #expect(store.setupTrialCanConfirm && !store.isConfirmingFixedText)
        store.warmUp()
        try await waitUntil { store.canStart }
        store.confirmSetupTrial(true)
        #expect(!store.setupProgress.speechConfirmed)
    }

    private final class MicrophoneProbe {
        var status: MicrophoneAuthorization = .authorized
    }
    @Test func recordingReadinessRequiresModelAndMicrophoneButNotAutomaticPaste() async throws {
        let microphone = MicrophoneProbe()
        let store = AppStore(service: SetupTranscriber(), pasteService: SetupPaste(), preferences: nil,
            microphoneStatus: { microphone.status })
        store.refreshPermissions()
        #expect(store.canStart)
        #expect(!store.canRecord)
        store.warmUp()
        #expect(!store.canRecord)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !store.canStart && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(store.modelState == .ready)
        #expect(store.canRecord)
        #expect(!store.canCompleteSetup)
        microphone.status = .denied
        store.refreshPermissions()
        #expect(!store.canRecord)
        microphone.status = .authorized
        store.refreshPermissions()
        #expect(store.canRecord)
        await store.cancel()
        #expect(store.canRecord)
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
        #expect(store.inputReady)
        #expect(!store.canCompleteSetup)
        store.completeSetup()
        #expect(!store.setupCompleted)
        // Existing users keep the old completion flag without being forced through the new guide.
        preferences.set(true, forKey: "setupCompleted")
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

    @Test func cancellingIdleSessionPreservesReadyState() async {
        let store = AppStore(service: SetupTranscriber(), preferences: nil)
        store.warmUp()
        for _ in 0..<1_000 where !store.canStart { await Task.yield() }
        #expect(store.modelState == .ready)
        await store.cancel()
        #expect(store.modelState == .ready)
    }
    @Test(arguments: SetupUsage.allCases)
    func guideRequiresHumanConfirmationOfSpeech(usage: SetupUsage) async throws {
        let name = "VoxInk.SetupComplete.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let paste = SetupPaste(); paste.outcome = .sent
        let store = try await readyStore(paste, preferences: preferences)
        store.setSetupUsage(usage)
        reachTrialStep(store, remote: usage.needsRemote)
        store.confirmSetupTrial(true)
        #expect(!store.setupProgress.textConfirmed)
        #expect(!store.canCompleteSetup)
        store.handleGlobalShortcut()
        try await waitUntil { store.phase == .recording }
        store.finishRecording()
        try await waitUntil { store.canStart }
        #expect(store.setupTrialCanConfirm)
        #expect(!store.canCompleteSetup)
        store.confirmSetupTrial(true)
        #expect(store.canCompleteSetup)
        store.leaveSetupTrial()
        #expect(store.setupCompleted)
        #expect(!store.isShowingSetup)
        let restored = AppStore(preferences: preferences)
        #expect(store.setupHandoffVisible && !restored.setupHandoffVisible)
        #expect(restored.setupCompleted)
        #expect(restored.setupProgress.verified)
        #expect(!restored.isShowingSetup)
        store.showSetup()
        #expect(store.isShowingSetup)
        #expect(store.setupProgress.step == .usage)
        #expect(!store.setupProgress.verified)
    }

    @Test(arguments: SetupUsage.allCases)
    func canEnterWorkspaceWithoutTrialAndResumeOnlyOnRequest(usage: SetupUsage) async throws {
        let name = "VoxInk.SkipTrial.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let store = try await readyStore(SetupPaste(), preferences: preferences)
        store.setSetupUsage(usage)
        reachTrialStep(store, remote: usage.needsRemote)
        #expect(store.setupBlockingHint == nil)
        store.startSetupTextTest()
        store.leaveSetupTrial()
        #expect(!store.isShowingSetup && !store.fixedTextTestArmed)
        #expect(!store.setupCompleted && !store.setupProgress.verified)
        #expect(store.canRecord)
        let reopened = AppStore(preferences: preferences)
        #expect(!reopened.isShowingSetup)
        reopened.showSetup()
        #expect(reopened.isShowingSetup && reopened.setupProgress.step == .trial)
    }

    @Test func deferredGuidePersistsProgressWithoutClaimingCompletion() async throws {
        let name = "VoxInk.SetupResume.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let paste = SetupPaste(); paste.outcome = .sent
        let store = try await readyStore(paste, preferences: preferences)
        reachTrialStep(store, remote: true)
        try await sendTestText(store)
        store.confirmSetupTrial(true)
        store.deferSetup()
        #expect(!store.setupCompleted)
        #expect(!store.isShowingSetup)
        let restored = AppStore(preferences: preferences)
        #expect(!restored.isShowingSetup)
        restored.showSetup()
        #expect(restored.setupProgress.step == .trial)
        #expect(restored.setupProgress.textConfirmed)
        #expect(!restored.setupTrialCanConfirm)
        #expect(restored.isShowingSetup)
    }

    @Test func remoteGuideRequiresProfileAndClipboardAcknowledgement() async throws {
        let store = try await readyStore(SetupPaste())
        store.setSetupUsage(.remote)
        store.advanceSetup(); store.advanceSetup()
        #expect(store.setupProgress.step == .remote)
        #expect(!store.canAdvanceSetup)
        store.setRemoteApplication(.init(bundleID: "test", name: "测试"))
        #expect(!store.canAdvanceSetup)
        store.confirmSetupClipboardSync(true)
        #expect(store.canAdvanceSetup)
        store.advanceSetup()
        store.setRemoteApplication(.init(bundleID: "test", name: "测试", usesControl: true))
        #expect(store.setupProgress.step == .remote)
        #expect(!store.setupProgress.clipboardSyncConfirmed)
        #expect(!store.canAdvanceSetup)
    }

    @Test func remoteTrialCannotBeConfirmedForAnUnconfiguredLocalTarget() async throws {
        let paste = SetupPaste(); paste.outcome = .sent
        let store = try await readyStore(paste)
        reachTrialStep(store, remote: true)
        paste.target = .init(pid: 2, bundleID: "local.editor", name: "本地编辑器")
        try await sendTestText(store)
        store.confirmSetupTrial(true)
        #expect(!store.setupTrialCanConfirm)
        #expect(!store.setupProgress.textConfirmed)
    }

    @Test func failedOrUnobservedPasteNeverCompletesTextStep() async throws {
        let paste = SetupPaste()
        let store = try await readyStore(paste)
        reachTrialStep(store, remote: false)
        try await sendTestText(store)
        store.confirmSetupTrial(true)
        #expect(!store.setupProgress.textConfirmed)
        paste.outcome = .sent
        try await sendTestText(store)
        store.confirmSetupTrial(false)
        #expect(!store.setupProgress.textConfirmed)
        #expect(!store.canAdvanceSetup)
        store.copySetupTestText()
        #expect(!store.setupTrialCanConfirm)
    }

    @Test func navigationAndDeferralDisarmFixedTextTest() async throws {
        let store = try await readyStore(SetupPaste())
        reachTrialStep(store, remote: false)
        store.startSetupTextTest()
        #expect(store.fixedTextTestArmed)
        store.previousSetupStep()
        #expect(!store.fixedTextTestArmed)
        store.advanceSetup()
        store.startSetupTextTest()
        store.deferSetup()
        #expect(!store.fixedTextTestArmed)
        #expect(!store.setupCompleted)
    }

    @Test func remoteChangesAndUsageChangesInvalidateEarlierEvidence() async throws {
        let paste = SetupPaste(); paste.outcome = .sent
        let store = try await readyStore(paste)
        reachTrialStep(store, remote: true)
        try await sendTestText(store)
        store.confirmSetupTrial(true)
        store.setRemotePasteTiming(.fast)
        #expect(!store.setupProgress.textConfirmed)
        #expect(!store.setupProgress.clipboardSyncConfirmed)
        #expect(store.setupProgress.step == .remote)
        store.setSetupUsage(.local)
        #expect(!store.setupProgress.steps.contains(.remote))
        #expect(store.setupProgress.step == .usage)
    }

    @Test(arguments: SetupUsage.allCases)
    func changingShortcutInvalidatesEarlierInputEvidence(usage: SetupUsage) async throws {
        let paste = SetupPaste(); paste.outcome = .sent
        let store = try await readyStore(paste)
        store.setSetupUsage(usage)
        reachTrialStep(store, remote: usage.needsRemote)
        try await sendTestText(store)
        store.confirmSetupTrial(true)
        try await sendSpeech(store)
        store.confirmSetupTrial(true)
        try #require(store.setupProgress.textConfirmed && store.canCompleteSetup)
        #expect(store.setShortcutCombination(.controlOptionSpace))
        #expect(store.setupProgress.textConfirmed == !usage.needsRemote && !store.setupProgress.speechConfirmed)
        #expect(!store.setupTrialCanConfirm && !store.canAdvanceSetup)
        #expect(store.setupProgress.step == (usage.needsRemote ? .remote : .trial))
        #expect(store.setupNotice != nil)
        #expect((store.setupBlockingHint != nil) == usage.needsRemote)
        if usage.needsRemote {
            #expect(!store.setupProgress.clipboardSyncConfirmed)
            store.confirmSetupClipboardSync(true)
            store.advanceSetup()
            store.confirmSetupTrial(true)
            #expect(store.setupProgress.step == .trial && !store.canCompleteSetup)
            try await sendSpeech(store)
            store.confirmSetupTrial(true)
            #expect(store.canCompleteSetup)
        }
    }

    @Test func unchangedOrRejectedShortcutPreservesInputEvidence() async throws {
        let paste = SetupPaste(); paste.outcome = .sent
        let store = try await readyStore(paste)
        reachTrialStep(store, remote: true)
        try await sendTestText(store)
        store.confirmSetupTrial(true)
        let current = store.shortcutCombination
        #expect(store.setShortcutCombination(current))
        #expect(store.setupProgress.textConfirmed)
        store.configureShortcutRegistration { $0 == current }
        #expect(!store.setShortcutCombination(.controlOptionSpace))
        #expect(store.setupProgress.textConfirmed && !store.canAdvanceSetup)
    }

    @Test func changingGestureModeRequiresAnotherInputTest() async throws {
        let paste = SetupPaste(); paste.outcome = .sent
        let store = try await readyStore(paste)
        reachTrialStep(store, remote: false)
        try await sendTestText(store)
        store.confirmSetupTrial(true)
        store.advanceSetup()
        store.setShortcutMode(.toggle)
        #expect(store.setupProgress.step == .trial)
        #expect(store.setupProgress.textConfirmed && !store.canCompleteSetup)
    }

    @Test func cancelledTrialAndWorkspaceRecordingDoNotCountAsInputVerification() async throws {
        let paste = SetupPaste(); paste.outcome = .sent
        let store = try await readyStore(paste)
        reachTrialStep(store, remote: false)
        store.startSetupTextTest()
        await store.cancel()
        #expect(!store.fixedTextTestArmed)
        #expect(!store.setupTrialCanConfirm)
        try await sendTestText(store)
        store.confirmSetupTrial(true)
        store.advanceSetup()
        store.beginRecording()
        try await waitUntil { store.phase == .recording }
        store.finishRecording()
        try await waitUntil { store.canStart }
        #expect(!store.setupTrialCanConfirm)
        store.confirmSetupTrial(true)
        #expect(!store.setupProgress.speechConfirmed)
    }

}
