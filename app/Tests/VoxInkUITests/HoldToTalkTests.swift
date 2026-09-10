import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

@MainActor private final class HoldRecorder: AudioRecording {
    var isRecording = false
    var duration = 1.0
    var starts = 0
    var stops = 0
    var waitForPermission = false
    var permissionAllowed = true
    var permission: CheckedContinuation<Bool, Never>?
    func requestPermission() async -> Bool {
        if waitForPermission { return await withCheckedContinuation { permission = $0 } }
        return permissionAllowed
    }
    func start() throws { starts += 1; isRecording = true }
    func stop() throws -> URL { stops += 1; isRecording = false; return URL(fileURLWithPath: "/hold-fixture.wav") }
    func sample() -> AudioCaptureSample { .init(elapsed: duration, level: 0.5) }
    func cancel() { isRecording = false }
}

private actor HoldTranscriber: TranscriptionService {
    func prepare() async throws {}
    func transcribe(url: URL) async throws -> String { "軟體平台，English 123。" }
    func cancel() async {}
}

@MainActor private final class HoldPaste: PasteService {
    var accessibilityGranted = true
    var texts: [String] = []
    var sessions: [UUID] = []
    var outcome: PasteOutcome = .sent
    func requestAccessibility() -> Bool { true }
    func captureTarget() -> PasteTarget? { .init(pid: 123, bundleID: "fixture", name: "Fixture") }
    func paste(text: String, to: PasteTarget, sessionID: UUID) async -> PasteOutcome {
        texts.append(text); sessions.append(sessionID)
        return outcome
    }
    func cancel() {}
}

@MainActor private final class ControlledHoldTranscriber: TranscriptionService {
    enum Failure: Error { case inference }
    var shouldFail = false
    var failure: any Error = Failure.inference
    var blocked = false
    var text = "第一次成功。"
    var pending: CheckedContinuation<String, Never>?
    func prepare() async throws {}
    func transcribe(url: URL) async throws -> String {
        if shouldFail { throw failure }
        if blocked { return await withCheckedContinuation { pending = $0 } }
        return text
    }
    func cancel() async {
        // A worker may finish after cancellation; its late result must never be pasted.
        pending?.resume(returning: "取消后迟到的结果。")
        pending = nil
    }
}

@MainActor struct HoldToTalkTests {
    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(predicate(), "Session did not reach its expected state within 3 seconds")
    }

    private func recordAndRelease(_ store: AppStore) async throws {
        store.handleShortcutPressed()
        try await waitUntil { store.phase == .recording }
        store.handleShortcutReleased()
        try await waitUntil { store.canStart }
    }

    @Test func fiftyConsecutiveSessionsHaveUniqueSinglePastes() async throws {
        let recorder = HoldRecorder(); let paste = HoldPaste(); let store = make(recorder, paste)
        for index in 0..<50 {
            store.setShortcutMode(index.isMultiple(of: 2) ? .holdToTalk : .toggle)
            store.handleShortcutPressed()
            try await waitUntil { store.phase == .recording }
            for _ in 0..<5 { store.handleShortcutPressed() }
            store.handleShortcutReleased()
            if store.shortcutMode == .toggle {
                store.handleShortcutPressed(); store.handleShortcutReleased()
            }
            store.handleShortcutReleased()
            try await waitUntil { store.canStart }
            #expect(store.phase == .ready)
            #expect(paste.texts.count == index + 1)
            #expect(!recorder.isRecording)
        }
        #expect(recorder.starts == 50)
        #expect(recorder.stops == 50)
        #expect(Set(paste.sessions).count == 50)
        #expect(paste.texts.allSatisfy { $0 == "软件平台，English 123。" })
    }

    @Test func durationLimitFinishesOnceEvenBeforeKeyRelease() async throws {
        let recorder = HoldRecorder(); let paste = HoldPaste(); let store = make(recorder, paste)
        recorder.duration = 60
        store.handleShortcutPressed()
        try await waitUntil { store.canStart }
        #expect(recorder.stops == 1)
        #expect(paste.texts.count == 1)
        store.handleShortcutPressed()
        store.handleShortcutReleased(); store.handleShortcutReleased()
        #expect(recorder.starts == 1)
        #expect(paste.texts.count == 1)
        recorder.duration = 1
        try await recordAndRelease(store)
        #expect(paste.texts.count == 2)
    }

    @Test func microphonePermissionFailureCanRecoverOnNextHold() async throws {
        let recorder = HoldRecorder(); let paste = HoldPaste(); let store = make(recorder, paste)
        recorder.permissionAllowed = false
        store.handleShortcutPressed()
        try await waitUntil { store.phase == .failed }
        store.handleShortcutReleased()
        #expect(recorder.starts == 0)
        #expect(paste.texts.isEmpty)
        recorder.permissionAllowed = true
        try await recordAndRelease(store)
        #expect(paste.texts.count == 1)
    }

    @Test func inferenceFailurePreservesPreviousTextAndNextSessionRecovers() async throws {
        let recorder = HoldRecorder(); let paste = HoldPaste(); let service = ControlledHoldTranscriber()
        let store = AppStore(service: service, pasteService: paste, recorder: recorder,
                             preferences: nil, audioCleaner: { _ in })
        try await recordAndRelease(store)
        service.shouldFail = true
        try await recordAndRelease(store)
        #expect(store.phase == .failed)
        #expect(store.transcript == "第一次成功。")
        #expect(paste.texts.count == 1)
        service.shouldFail = false; service.text = "恢复成功。"
        try await recordAndRelease(store)
        #expect(store.phase == .ready)
        #expect(paste.texts == ["第一次成功。", "恢复成功。"])
    }

    @Test func silentRecordingNeverPastesAndNextHoldStillWorks() async throws {
        let recorder = HoldRecorder(); let paste = HoldPaste(); let service = ControlledHoldTranscriber()
        let store = AppStore(service: service, pasteService: paste, recorder: recorder,
                             preferences: nil, audioCleaner: { _ in })
        service.shouldFail = true; service.failure = QwenTranscriptionService.ServiceError.noSpeech
        try await recordAndRelease(store)
        #expect(store.phase == .ready)
        #expect(store.status.contains("未写入文字"))
        #expect(paste.texts.isEmpty)
        service.shouldFail = false
        try await recordAndRelease(store)
        #expect(paste.texts.count == 1)
    }

    @Test func busyKeysAndLateCancelledInferenceCannotLeakIntoNextSession() async throws {
        let recorder = HoldRecorder(); let paste = HoldPaste(); let service = ControlledHoldTranscriber()
        let store = AppStore(service: service, pasteService: paste, recorder: recorder,
                             preferences: nil, audioCleaner: { _ in })
        try await recordAndRelease(store)
        service.blocked = true
        store.handleShortcutPressed()
        try await waitUntil { store.phase == .recording }
        store.handleShortcutReleased()
        try await waitUntil { service.pending != nil }
        for _ in 0..<10 { store.handleShortcutPressed(); store.handleShortcutReleased() }
        #expect(recorder.starts == 2)
        await store.cancel()
        #expect(store.phase == .ready)
        #expect(store.transcript == "第一次成功。")
        #expect(paste.texts.count == 1)
        service.blocked = false; service.text = "新的会话。"
        try await recordAndRelease(store)
        #expect(paste.texts == ["第一次成功。", "新的会话。"])
    }

    @Test func pasteFailureKeepsResultAndOnlyExplicitRetrySendsAgain() async throws {
        let recorder = HoldRecorder(); let paste = HoldPaste(); let store = make(recorder, paste)
        paste.outcome = .failed("目标应用不可用")
        try await recordAndRelease(store)
        #expect(store.phase == .failed)
        #expect(store.canPasteAgain)
        #expect(store.transcript == "软件平台，English 123。")
        store.handleShortcutReleased()
        #expect(paste.texts.count == 1)
        paste.outcome = .sent
        store.pasteAgain()
        try await waitUntil { store.canStart }
        #expect(store.phase == .ready)
        #expect(paste.texts.count == 2)
        #expect(Set(paste.sessions).count == 2)
    }

    private func make(_ recorder: HoldRecorder, _ paste: HoldPaste) -> AppStore {
        AppStore(service: HoldTranscriber(), pasteService: paste, recorder: recorder,
                 preferences: nil, audioCleaner: { _ in })
    }

    @Test func releaseStopsOnceAndPastesSimplifiedText() async {
        let recorder = HoldRecorder(); let paste = HoldPaste(); let store = make(recorder, paste)
        #expect(store.shortcutMode == .holdToTalk)
        store.handleShortcutPressed()
        while store.phase == .loading { await Task.yield() }
        #expect(store.phase == .recording)
        store.handleShortcutPressed()
        #expect(recorder.starts == 1)
        store.handleShortcutReleased(); store.handleShortcutReleased()
        while !store.canStart { await Task.yield() }
        #expect(recorder.stops == 1)
        #expect(paste.texts == ["软件平台，English 123。"])
        #expect(store.rawTranscript == "軟體平台，English 123。")
    }

    @Test func releaseWhilePermissionPendingNeverStartsLateRecording() async {
        let recorder = HoldRecorder(); recorder.waitForPermission = true
        let paste = HoldPaste(); let store = make(recorder, paste)
        store.handleShortcutPressed()
        while recorder.permission == nil { await Task.yield() }
        store.handleShortcutReleased()
        recorder.permission?.resume(returning: true)
        for _ in 0..<10 { await Task.yield() }
        #expect(store.phase == .ready)
        #expect(recorder.starts == 0)
        #expect(paste.texts.isEmpty)
    }

    @Test func shortTapDoesNotSendEmptyRecording() async {
        let recorder = HoldRecorder(); recorder.duration = 0.05
        let paste = HoldPaste(); let store = make(recorder, paste)
        store.handleShortcutPressed()
        while store.phase == .loading { await Task.yield() }
        store.handleShortcutReleased()
        #expect(store.phase == .ready)
        #expect(!recorder.isRecording)
        #expect(recorder.stops == 0)
        #expect(paste.texts.isEmpty)
    }

    @Test func toggleModeStillRequiresSecondPress() async {
        let recorder = HoldRecorder(); let paste = HoldPaste(); let store = make(recorder, paste)
        store.setShortcutMode(.toggle)
        store.handleShortcutPressed()
        while store.phase == .loading { await Task.yield() }
        store.handleShortcutReleased()
        #expect(store.phase == .recording)
        store.setShortcutMode(.holdToTalk)
        #expect(store.shortcutMode == .toggle)
        store.handleShortcutPressed(); store.handleShortcutReleased()
        while !store.canStart { await Task.yield() }
        #expect(paste.texts.count == 1)
    }

    @Test func cancelledHoldDoesNotPasteOnRelease() async {
        let recorder = HoldRecorder(); let paste = HoldPaste(); let store = make(recorder, paste)
        store.handleShortcutPressed()
        while store.phase == .loading { await Task.yield() }
        await store.cancel(); store.handleShortcutReleased()
        #expect(paste.texts.isEmpty)
        #expect(!recorder.isRecording)
    }

    @Test func fixedTextModeDoesNotRecordWhenHeldOrReleased() async {
        let recorder = HoldRecorder(); let paste = HoldPaste(); let store = make(recorder, paste)
        store.armFixedTextTest()
        store.handleShortcutPressed(); store.handleShortcutReleased()
        while !store.canStart { await Task.yield() }
        #expect(recorder.starts == 0)
        #expect(paste.texts == ["语落固定文字测试：中文、English、123。"])
        #expect(!store.fixedTextTestArmed)
    }

    @Test func modePreferenceSurvivesNewStore() throws {
        let name = "local.voxink.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let first = AppStore(service: HoldTranscriber(), preferences: defaults)
        first.setShortcutMode(.toggle)
        let second = AppStore(service: HoldTranscriber(), preferences: defaults)
        #expect(second.shortcutMode == .toggle)
    }
}
