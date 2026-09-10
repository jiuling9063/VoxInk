import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

private actor RecoveryStorageStub: AudioRecoveryStorage {
    var record: RetainedAudio?
    var saveFails = false
    var discardFails = false
    var gateSave = false
    var saveContinuation: CheckedContinuation<Void, Never>?
    private(set) var saves = 0
    init(record: RetainedAudio? = nil) { self.record = record }
    func configure(saveFails: Bool = false, discardFails: Bool = false, gateSave: Bool = false) {
        self.saveFails = saveFails; self.discardFails = discardFails; self.gateSave = gateSave
    }
    func save(_ source: URL) async throws -> RetainedAudio {
        if gateSave { await withCheckedContinuation { saveContinuation = $0 } }
        if saveFails { throw Failure.disk }
        saves += 1
        let new = RetainedAudio(id: UUID(), createdAt: Date(), url: URL(fileURLWithPath: "/retained-\(saves).wav"))
        record = new
        return new
    }
    func latest() -> RetainedAudio? { record }
    func discard(_ id: UUID) throws {
        if discardFails { throw Failure.disk }
        if record?.id == id { record = nil }
    }
    func purgeExpired() {}
    func releaseSave() { saveContinuation?.resume(); saveContinuation = nil }
    enum Failure: Error { case disk }
}

@MainActor private final class RecoveryTranscriber: TranscriptionService {
    var failure: (any Error)?
    var text = "軟體恢復成功。"
    var urls: [URL] = []
    var blocked = false
    var continuation: CheckedContinuation<String, Never>?
    var blockPreparation = false
    var preparation: CheckedContinuation<Void, Never>?
    func prepare() async throws {
        if blockPreparation { await withCheckedContinuation { preparation = $0 } }
    }
    func transcribe(url: URL) async throws -> String {
        urls.append(url)
        if let failure { throw failure }
        if blocked { return await withCheckedContinuation { continuation = $0 } }
        return text
    }
    func cancel() async {
        continuation?.resume(returning: "迟到文字"); continuation = nil
        preparation?.resume(); preparation = nil
    }
}

@MainActor private final class RecoveryPaste: PasteService {
    var accessibilityGranted = true
    var calls = 0
    var outcome: PasteOutcome = .sent
    func requestAccessibility() -> Bool { true }
    func captureTarget() -> PasteTarget? { .init(pid: 123, bundleID: "fixture", name: "Fixture") }
    func paste(text: String, to: PasteTarget, sessionID: UUID) async -> PasteOutcome { calls += 1; return outcome }
    func cancel() {}
}

@MainActor private final class RecoveryRecorder: AudioRecording {
    var isRecording = false
    func requestPermission() async -> Bool { true }
    func start() throws { isRecording = true }
    func stop() throws -> URL { isRecording = false; return URL(fileURLWithPath: "/prepared.wav") }
    func sample() -> AudioCaptureSample { .init(elapsed: 1, level: 0.5) }
    func cancel() { isRecording = false }
}

@MainActor private final class CopyResultProbe { var succeeds = false }

@MainActor struct AudioRecoveryTests {
    private let source = URL(fileURLWithPath: "/prepared.wav")
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(condition())
    }
    private func make(_ service: RecoveryTranscriber, _ storage: RecoveryStorageStub,
                      paste: RecoveryPaste = RecoveryPaste(), copy: @escaping @MainActor (String) -> Bool = { _ in true }) -> AppStore {
        AppStore(service: service, pasteService: paste, recorder: RecoveryRecorder(), preferences: nil,
                 audioPreparer: { $0 }, audioCleaner: { _ in }, audioRecovery: storage, clipboardWriter: copy)
    }

    @Test func failureRetryKeepsDeadlineAndNeverAutomaticallyPastes() async throws {
        let service = RecoveryTranscriber(); service.failure = RecoveryStorageStub.Failure.disk
        let storage = RecoveryStorageStub(); let paste = RecoveryPaste(); let store = make(service, storage, paste: paste)
        store.handleShortcutPressed()
        try await wait { store.phase == .recording }
        store.handleShortcutReleased()
        try await wait { store.canStart }
        let record = try #require(store.retainedAudio)
        #expect(store.phase == .failed)
        service.failure = nil
        store.retryRetainedAudio()
        try await wait { store.canStart }
        #expect(store.transcript == "软件恢复成功。")
        #expect(store.retainedAudio == record)
        #expect(service.urls.last == record.url)
        #expect(await storage.saves == 1)
        #expect(paste.calls == 0)
        #expect(store.canPasteAgain)
        store.pasteAgain()
        try await wait { store.canStart }
        #expect(paste.calls == 1)
        #expect(store.retainedAudio == nil)
        #expect(await storage.record == nil)
    }

    @Test func successfulAutomaticPasteNeedsNoRetainedAudio() async throws {
        let service = RecoveryTranscriber(); let storage = RecoveryStorageStub(); let paste = RecoveryPaste()
        let store = make(service, storage, paste: paste)
        store.handleShortcutPressed()
        try await wait { store.phase == .recording }
        store.handleShortcutReleased()
        try await wait { store.canStart }
        #expect(paste.calls == 1)
        #expect(await storage.saves == 0)
        #expect(store.retainedAudio == nil)
    }

    @Test func pasteFailureRetainsUntilExplicitSuccessfulPaste() async throws {
        let service = RecoveryTranscriber(); let storage = RecoveryStorageStub(); let paste = RecoveryPaste()
        paste.outcome = .failed("目标不可用")
        let store = make(service, storage, paste: paste)
        store.handleShortcutPressed()
        try await wait { store.phase == .recording }
        store.handleShortcutReleased()
        try await wait { store.canStart }
        #expect(store.retainedAudio != nil)
        paste.outcome = .sent
        store.pasteAgain()
        try await wait { store.canStart }
        #expect(store.retainedAudio == nil)
    }

    @Test func previewSurvivesQuitAndRestoresWithoutTranscriptionOrTarget() async throws {
        let storage = RecoveryStorageStub(); let service = RecoveryTranscriber(); let first = make(service, storage)
        await first.transcribePrepared(source)
        let record = try #require(first.retainedAudio)
        await first.shutdown()
        #expect(await storage.record == record)
        let nextService = RecoveryTranscriber(); let next = make(nextService, storage)
        next.prepareForUse()
        try await wait { next.canStart }
        #expect(next.retainedAudio == record)
        #expect(nextService.urls.isEmpty)
        #expect(next.transcript.isEmpty)
        #expect(!next.canPasteAgain)
        await next.shutdown()
    }

    @Test func successfulCopyDeletesButFailedCopyKeepsAudio() async throws {
        let storage = RecoveryStorageStub(); let copy = CopyResultProbe()
        let store = make(RecoveryTranscriber(), storage, copy: { _ in copy.succeeds })
        await store.transcribePrepared(source)
        store.copyResult()
        #expect(store.retainedAudio != nil)
        copy.succeeds = true; store.copyResult()
        try await wait { store.canStart }
        #expect(store.retainedAudio == nil)
        #expect(await storage.record == nil)
    }

    @Test func quittingDuringModelReloadPreservesPreviousRecoverableAudio() async throws {
        let storage = RecoveryStorageStub(); let service = RecoveryTranscriber(); let store = make(service, storage)
        await store.transcribePrepared(source)
        let record = try #require(store.retainedAudio)
        service.blockPreparation = true
        store.warmUp()
        try await wait { service.preparation != nil }
        await store.shutdown()
        #expect(await storage.record == record)
        #expect(store.retainedAudio == record)
    }

    @Test func copyingPreviousTextDoesNotDeleteNewFailedAudio() async throws {
        let service = RecoveryTranscriber(); let storage = RecoveryStorageStub(); let store = make(service, storage)
        await store.transcribePrepared(source)
        service.failure = RecoveryStorageStub.Failure.disk
        await store.transcribePrepared(source)
        let failedRecord = try #require(store.retainedAudio)
        store.copyResult()
        try await wait { store.canStart }
        #expect(store.retainedAudio == failedRecord)
        #expect(await storage.record == failedRecord)
    }

    @Test func rejectedSpeechKeepsAudioWithoutPastingOrAssociatingPreviousText() async throws {
        let service = RecoveryTranscriber(); let storage = RecoveryStorageStub(); let paste = RecoveryPaste()
        let store = make(service, storage, paste: paste)
        await store.transcribePrepared(source)
        let previous = store.transcript
        service.failure = QwenTranscriptionService.ServiceError.noSpeechDetected
        store.handleShortcutPressed()
        try await wait { store.phase == .recording }
        store.handleShortcutReleased()
        try await wait { store.canStart }
        let record = try #require(store.retainedAudio)
        #expect(paste.calls == 0)
        #expect(store.transcript == previous)
        #expect(store.status.contains("没有检测到清晰语音"))
        store.copyResult()
        try await wait { store.canStart }
        #expect(store.retainedAudio == record)
        store.retryRetainedAudio()
        try await wait { store.canStart }
        #expect(!store.status.contains("重试识别完成"))
        #expect(store.modelState == .notLoaded)
        #expect(store.retainedAudio == record)
        #expect(paste.calls == 0)
        service.failure = nil
        store.retryRetainedAudio()
        try await wait { store.canStart }
        #expect(store.status.contains("重试识别完成"))
        #expect(paste.calls == 0)
        store.copyResult()
        try await wait { store.canStart }
        #expect(store.retainedAudio == nil)
    }

    @Test func cancellingRetryDeletesAudioAndRejectsLateText() async throws {
        let service = RecoveryTranscriber(); let storage = RecoveryStorageStub(); let store = make(service, storage)
        await store.transcribePrepared(source)
        let previous = store.transcript
        service.blocked = true; store.retryRetainedAudio()
        try await wait { service.continuation != nil }
        await store.cancel()
        #expect(store.retainedAudio == nil)
        #expect(await storage.record == nil)
        #expect(store.transcript == previous)
    }

    @Test func cancellationWaitsForLateSaveAndRemovesIt() async throws {
        let storage = RecoveryStorageStub(); await storage.configure(gateSave: true)
        let store = make(RecoveryTranscriber(), storage)
        store.importAudio(source)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await storage.saveContinuation == nil, ContinuousClock.now < deadline { await Task.yield() }
        try #require(await storage.saveContinuation != nil)
        let cancel = Task { await store.cancel() }
        try await wait { store.phase == .cancelling }
        await storage.releaseSave()
        await cancel.value
        #expect(await storage.record == nil)
        #expect(store.retainedAudio == nil)
        #expect(store.phase == .ready)
    }

    @Test func storageFailureStillShowsRecognizedText() async {
        let storage = RecoveryStorageStub(); await storage.configure(saveFails: true)
        let store = make(RecoveryTranscriber(), storage)
        await store.transcribePrepared(source)
        #expect(store.transcript == "软件恢复成功。")
        #expect(store.phase == .ready)
        #expect(store.recoveryStorageWarning != nil)
        #expect(store.retainedAudio == nil)
    }

    @Test func expiredAudioCannotRetryAndMaintenanceDeletesIt() async throws {
        let record = RetainedAudio(id: UUID(), createdAt: Date().addingTimeInterval(-86_401), url: source)
        let storage = RecoveryStorageStub(record: record); let store = make(RecoveryTranscriber(), storage)
        store.prepareForUse()
        try await wait { store.canStart }
        #expect(!store.canRetryAudio)
        await store.removeExpiredAudio()
        #expect(store.retainedAudio == nil)
        #expect(await storage.record == nil)
        await store.shutdown()
    }

    @Test func deletionFailureLeavesActionableState() async throws {
        let storage = RecoveryStorageStub(); let service = RecoveryTranscriber(); let store = make(service, storage)
        await store.transcribePrepared(source)
        await storage.configure(discardFails: true)
        await store.transcribePrepared(source)
        #expect(store.phase == .failed)
        #expect(store.retainedAudio != nil)
        #expect(store.recoveryStorageWarning != nil)
        #expect(service.urls.count == 1)
        store.deleteRetainedAudio()
        try await wait { store.canStart }
        #expect(store.retainedAudio != nil)
    }
}
