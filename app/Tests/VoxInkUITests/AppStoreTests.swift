import Foundation
import Testing
@testable import VoxInkUI

private actor StubTranscriber: TranscriptionService {
    let text: String
    let delay: Duration
    init(text: String = "测试结果", delay: Duration = .zero) { self.text = text; self.delay = delay }
    func prepare() async throws {}
    func transcribe(url: URL) async throws -> String {
        // Deliberately ignore cancellation to exercise the UI generation guard.
        try? await Task.sleep(for: delay)
        return text
    }
    func cancel() async {}
}

private actor PreparationGate {
    private var continuation: CheckedContinuation<URL, Never>?
    private(set) var started = false

    func prepare() async -> URL {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func release(_ url: URL) { continuation?.resume(returning: url) }
}

private final class CleanupProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var cleaned: Bool { lock.withLock { value } }
    func markCleaned() { lock.withLock { value = true } }
}

private actor CompletionProbe {
    private(set) var completed = false
    func markCompleted() { completed = true }
}

@MainActor struct AppStoreTests {
    @Test func deterministicRulesKeepReadOnlyRecognitionOriginal() async {
        let raw = "呃，請用Swift整理  檔案，， 地址是 https://example.com/繁體。"
        let store = AppStore(service: StubTranscriber(text: raw), preferences: nil)
        await store.transcribePrepared(URL(fileURLWithPath: "/non-owned-fixture.wav"))
        #expect(store.rawTranscript == raw)
        #expect(store.transcript == "请用Swift整理文件，地址是 https://example.com/繁體。")
        #expect(store.phase == .ready)
    }

    @Test func showsSimplifiedTextAndKeepsRawTranscript() async {
        let raw = "  軟體平台，今天的天氣很好。English 123。  "
        let store = AppStore(service: StubTranscriber(text: raw))
        await store.transcribePrepared(URL(fileURLWithPath: "/non-owned-fixture.wav"))
        #expect(store.rawTranscript == raw)
        #expect(store.transcript == "软件平台，今天的天气很好。English 123。")
    }
    @Test func successfulTranscriptIsShown() async {
        let store = AppStore(service: StubTranscriber())
        await store.transcribePrepared(URL(fileURLWithPath: "/non-owned-fixture.wav"))
        #expect(store.transcript == "测试结果")
        #expect(store.phase == .ready)
    }

    @Test func cancelledResultCannotReplacePreviousText() async {
        let store = AppStore(service: StubTranscriber(delay: .milliseconds(60)))
        let pending = Task { await store.transcribePrepared(URL(fileURLWithPath: "/non-owned-fixture.wav")) }
        while store.phase != .transcribing { await Task.yield() }
        await store.cancel()
        await pending.value
        #expect(store.transcript.isEmpty)
        #expect(store.phase == .ready)
    }

    @Test func cancelWaitsForPendingImportCleanup() async {
        let gate = PreparationGate()
        let cleanup = CleanupProbe()
        let completion = CompletionProbe()
        let store = AppStore(
            service: StubTranscriber(),
            audioPreparer: { _ in await gate.prepare() },
            audioCleaner: { _ in cleanup.markCleaned() }
        )
        store.importAudio(URL(fileURLWithPath: "/source.wav"))
        while await !gate.started { await Task.yield() }

        let cancellation = Task {
            await store.cancel()
            await completion.markCompleted()
        }
        await Task.yield()
        #expect(store.phase == .cancelling)
        #expect(await !completion.completed)
        #expect(!cleanup.cleaned)

        await gate.release(URL(fileURLWithPath: "/prepared.wav"))
        await cancellation.value
        #expect(cleanup.cleaned)
        #expect(store.phase == .ready)
        #expect(store.transcript.isEmpty)
    }

    @Test func emptyResultIsReported() async {
        let store = AppStore(service: StubTranscriber(text: "  \n"))
        await store.transcribePrepared(URL(fileURLWithPath: "/non-owned-fixture.wav"))
        #expect(store.phase == .failed)
        #expect(store.transcript.isEmpty)
    }
}
