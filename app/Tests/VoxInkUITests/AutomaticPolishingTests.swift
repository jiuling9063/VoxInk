import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

private actor AutomaticTranscriber: TranscriptionService {
    func prepare() async throws {}
    func transcribe(url: URL) async throws -> String { "明天下午开会，明天下午开会。" }
    func cancel() async {}
}

private actor AutomaticPolisher: PolishingService {
    enum Outcome: Sendable { case accepted, rejected, timeout, empty }
    let outcome: Outcome
    let delayed: Bool
    let generationSeconds: Double
    private(set) var calls = 0
    private(set) var selectedModels: [PolishModel] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    init(_ outcome: Outcome = .accepted, delayed: Bool = false, generationSeconds: Double = 1) {
        self.outcome = outcome; self.delayed = delayed; self.generationSeconds = generationSeconds
    }
    func polish(_ text: String, model: PolishModel) async throws -> PolishResult {
        calls += 1
        selectedModels.append(model)
        if delayed && !released { await withCheckedContinuation { continuation = $0 } }
        released = false
        switch outcome {
        case .accepted: return .init(accepted: true, reason: "test", text: "明天下午开会。", generationSeconds: generationSeconds)
        case .rejected: return .init(accepted: false, reason: "protected_content_changed", text: "错误输出")
        case .empty: return .init(accepted: true, reason: "test", text: "  ")
        case .timeout: throw LocalPolishingService.Failure.timeout
        }
    }
    func releaseResult() { released = true; continuation?.resume(); continuation = nil }
}

@MainActor private final class AutomaticRecorder: AudioRecording {
    var isRecording = false
    func requestPermission() async -> Bool { true }
    func start() throws { isRecording = true }
    func stop() throws -> URL { isRecording = false; return URL(fileURLWithPath: "/automatic-polish-fixture.wav") }
    func sample() -> AudioCaptureSample { .init(elapsed: 1, level: 0.2) }
    func cancel() { isRecording = false }
}

@MainActor private final class AutomaticPaste: PasteService {
    var accessibilityGranted = true
    var texts: [String] = []
    func requestAccessibility() -> Bool { true }
    func captureTarget() -> PasteTarget? { .init(pid: 123, bundleID: "test.fixture", name: "测试框") }
    func paste(text: String, to target: PasteTarget, sessionID: UUID) async -> PasteOutcome {
        texts.append(text); return .sent
    }
    func cancel() {}
}

private actor DelayedAutomaticTranscriber: TranscriptionService {
    var started = false
    private var waiter: CheckedContinuation<String, Never>?
    func prepare() async throws {}
    func transcribe(url: URL) async throws -> String {
        started = true
        return await withCheckedContinuation { waiter = $0 }
    }
    func releaseResult() { waiter?.resume(returning: "明天下午开会。"); waiter = nil }
    func cancel() async {}
}

private actor ReleaseFailurePolisher: PolishingService {
    var started = false
    private var waiter: CheckedContinuation<PolishResult, Error>?
    func polish(_ text: String, model: PolishModel) async throws -> PolishResult {
        started = true
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiter = $0 }
        } onCancel: { Task { await self.finish() } }
    }
    func finish() { waiter?.resume(throwing: LocalPolishingService.Failure.failed); waiter = nil }
    func release() async {
        let hadWaiter = waiter != nil
        finish()
        if hadWaiter { try? await Task.sleep(for: .milliseconds(100)) }
    }
}

@MainActor struct AutomaticPolishingTests {
    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(predicate())
    }
    private func make(_ polisher: AutomaticPolisher, _ paste: AutomaticPaste) -> AppStore {
        AppStore(polishingService: polisher, polishDeviceProvider: { .init(memoryGB: 16) },
                 polishInventory: { [.light, .balanced] }, service: AutomaticTranscriber(), pasteService: paste,
                 recorder: AutomaticRecorder(), preferences: nil, audioPreparer: { $0 }, audioCleaner: { _ in })
    }
    private func record(_ store: AppStore) async throws {
        store.handleShortcutPressed()
        try await waitUntil { store.phase == .recording }
        store.handleShortcutReleased()
    }

    @Test func automaticCalibratesButManualChoiceStaysFixed() async throws {
        let polisher = AutomaticPolisher(generationSeconds: 10), paste = AutomaticPaste()
        let store = make(polisher, paste)
        #expect(store.automaticPolishModel)
        store.setPolishingEnabled(true)
        for _ in 0..<4 {
            store.importAudio(URL(fileURLWithPath: "/fixture.wav"))
            try await waitUntil { store.canStart }
        }
        #expect(await polisher.selectedModels == [.balanced, .balanced, .balanced, .light])
        store.setPolishModel(.medium)
        #expect(!store.automaticPolishModel)
        store.importAudio(URL(fileURLWithPath: "/fixture.wav"))
        try await waitUntil { store.canStart }
        #expect(await polisher.selectedModels.last == .medium)
        await store.shutdown()
    }

    @Test func criticalPressureDuringASRSkipsPolish() async throws {
        let transcriber = DelayedAutomaticTranscriber(), polisher = AutomaticPolisher(), paste = AutomaticPaste()
        let store = AppStore(polishingService: polisher, polishDeviceProvider: { .init(memoryGB: 16) },
            polishInventory: { [.balanced] }, service: transcriber, pasteService: paste, recorder: AutomaticRecorder(),
            preferences: nil, audioPreparer: { $0 }, audioCleaner: { _ in })
        store.setPolishingEnabled(true)
        try await record(store)
        for _ in 0..<200 {
            if await transcriber.started { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await transcriber.started)
        await store.handlePolishMemoryPressure(2)
        await transcriber.releaseResult()
        try await waitUntil { store.canStart }
        #expect(await polisher.calls == 0)
        #expect(paste.texts == ["明天下午开会。"])
        await store.shutdown()
    }

    @Test func shutdownDuringPolishNeverWritesFallback() async throws {
        let polisher = ReleaseFailurePolisher(), paste = AutomaticPaste()
        let store = AppStore(polishingService: polisher, polishDeviceProvider: { .init(memoryGB: 16) },
            polishInventory: { [.balanced] }, service: AutomaticTranscriber(), pasteService: paste,
            recorder: AutomaticRecorder(), preferences: nil, audioPreparer: { $0 }, audioCleaner: { _ in })
        store.setPolishingEnabled(true)
        try await record(store)
        for _ in 0..<200 {
            if await polisher.started { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await polisher.started)
        await store.shutdown()
        #expect(paste.texts.isEmpty)
        #expect(store.sessionHistory.isEmpty)
    }

    @Test func disabledByDefaultWritesOriginalWithoutCallingModel() async throws {
        let polisher = AutomaticPolisher(), paste = AutomaticPaste()
        let store = make(polisher, paste)
        try await record(store)
        try await waitUntil { store.canStart }
        #expect(await polisher.calls == 0)
        #expect(paste.texts == ["明天下午开会，明天下午开会。"])
    }

    @Test func enabledPolishesBeforeSingleWriteAndKeepsRawText() async throws {
        let polisher = AutomaticPolisher(delayed: true), paste = AutomaticPaste()
        let store = make(polisher, paste)
        store.setPolishingEnabled(true)
        store.setPolishModel(.medium)
        try await record(store)
        try await waitUntil { store.isPolishing }
        #expect(paste.texts.isEmpty)
        #expect(store.canCancel)
        #expect(!store.canStart)
        store.setPolishingEnabled(false)
        store.setPolishModel(.light)
        #expect(store.polishModel == .medium)
        #expect(store.polishingEnabled)
        store.handleShortcutPressed(); store.handleShortcutReleased()
        await polisher.releaseResult()
        try await waitUntil { store.canStart }
        #expect(await polisher.calls == 1)
        #expect(await polisher.selectedModels == [.medium])
        #expect(paste.texts == ["明天下午开会。"])
        #expect(store.transcript == paste.texts.first)
        #expect(store.rawTranscript == "明天下午开会，明天下午开会。")
        #expect(store.sessionHistory.first?.text == store.transcript)
        #expect(!store.isPolishing)
    }

    @Test(arguments: [AutomaticPolisher.Outcome.rejected, .timeout, .empty])
    fileprivate func failureFallsBackOnceWithoutLosingOriginal(_ outcome: AutomaticPolisher.Outcome) async throws {
        let polisher = AutomaticPolisher(outcome), paste = AutomaticPaste()
        let store = make(polisher, paste)
        store.setPolishingEnabled(true)
        try await record(store)
        try await waitUntil { store.canStart }
        #expect(paste.texts == ["明天下午开会，明天下午开会。"])
        #expect(!store.polishMessage.isEmpty)
        #expect(!store.isPolishing)
        #expect(store.phase == .ready)
    }

    @Test func escapeDuringPolishDiscardsLateResultAndNeverPastes() async throws {
        let polisher = AutomaticPolisher(delayed: true), paste = AutomaticPaste()
        let store = make(polisher, paste)
        store.setPolishingEnabled(true)
        try await record(store)
        try await waitUntil { store.isPolishing }
        store.handleShortcutCancelled()
        try await waitUntil { store.phase == .cancelling }
        await polisher.releaseResult()
        try await waitUntil { store.canStart }
        #expect(paste.texts.isEmpty)
        #expect(store.sessionHistory.isEmpty)
        #expect(!store.isPolishing)
        #expect(store.transcript == "明天下午开会，明天下午开会。")
        store.setPolishingEnabled(false)
        try await record(store)
        try await waitUntil { store.canStart }
        #expect(paste.texts.count == 1)
    }

    @Test func importPolishesButNeverWritesToAnotherApplication() async throws {
        let polisher = AutomaticPolisher(), paste = AutomaticPaste()
        let store = make(polisher, paste)
        store.setPolishingEnabled(true)
        store.importAudio(URL(fileURLWithPath: "/automatic-polish-fixture.wav"))
        try await waitUntil { store.canStart }
        #expect(store.transcript == "明天下午开会。")
        #expect(paste.texts.isEmpty)
    }

    @Test func automaticChoicePersistsButOldPreviewOptInDoesNotEnableAutomaticWriting() throws {
        let name = "VoxInk.AutomaticPolishingTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        preferences.set(true, forKey: "polishingEnabled")
        let store = AppStore(polishingService: AutomaticPolisher(), preferences: preferences)
        #expect(!store.polishingEnabled)
        store.setPolishingEnabled(true)
        #expect(AppStore(preferences: preferences).polishingEnabled)
        store.setPolishingEnabled(false)
        #expect(!AppStore(preferences: preferences).polishingEnabled)
    }
}
