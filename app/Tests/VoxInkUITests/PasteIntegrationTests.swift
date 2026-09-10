import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

@MainActor private final class StubPaste: PasteService {
    var accessibilityGranted = true
    var target: PasteTarget? = PasteTarget(pid: 123, bundleID: "test.fixture", name: "Test")
    var requests: [(String, UUID)] = []
    var blocked = false
    var cancellationOutcome: PasteOutcome = .cancelledAfterSend
    var continuation: CheckedContinuation<PasteOutcome, Never>?
    func requestAccessibility() -> Bool { accessibilityGranted }
    func captureTarget() -> PasteTarget? { target }
    func paste(text: String, to target: PasteTarget, sessionID: UUID) async -> PasteOutcome {
        requests.append((text, sessionID))
        if blocked { return await withCheckedContinuation { continuation = $0 } }
        return .sent
    }
    func cancel() { continuation?.resume(returning: cancellationOutcome); continuation = nil }
}

private actor QuickTranscriber: TranscriptionService {
    func prepare() async throws {}
    func transcribe(url: URL) async throws -> String { "导入内容" }
    func cancel() async {}
}

@MainActor struct PasteIntegrationTests {
    @Test func delayedFixedTestPastesWithoutShortcut() async throws {
        let paste = StubPaste()
        let store = AppStore(service: QuickTranscriber(), pasteService: paste)
        store.scheduleFixedTextTest(after: .milliseconds(10))
        #expect(!store.canStart)
        #expect(paste.requests.isEmpty)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !store.canStart && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(paste.requests.count == 1)
        #expect(paste.requests.first?.0 == "语落固定文字测试：中文、English、123。")
        #expect(store.canPasteAgain)
    }

    @Test func cancellingDelayedTestDoesNotPasteOrArmRecording() async throws {
        let paste = StubPaste()
        let store = AppStore(service: QuickTranscriber(), pasteService: paste)
        store.scheduleFixedTextTest(after: .milliseconds(30))
        await store.cancel()
        try await Task.sleep(for: .milliseconds(50))
        #expect(paste.requests.isEmpty)
        #expect(!store.fixedTextTestArmed)
        #expect(store.phase == .ready)
    }

    @Test func importingAudioNeverAutomaticallyPastes() async {
        let paste = StubPaste()
        let store = AppStore(service: QuickTranscriber(), pasteService: paste,
            audioPreparer: { $0 }, audioCleaner: { _ in })
        store.importAudio(URL(fileURLWithPath: "/fixture.wav"))
        while !store.canStart { await Task.yield() }
        #expect(store.transcript == "导入内容")
        #expect(paste.requests.isEmpty)
    }

    @Test func fixedTextShortcutPostsOnceAndManualRetryGetsNewID() async {
        let paste = StubPaste()
        let store = AppStore(service: QuickTranscriber(), pasteService: paste)
        store.armFixedTextTest(); store.handleGlobalShortcut()
        store.handleGlobalShortcut()
        while !store.canStart { await Task.yield() }
        #expect(paste.requests.count == 1)
        #expect(!store.fixedTextTestArmed)
        #expect(store.canPasteAgain)
        #expect(store.repasteTargetName == "Test")
        store.pasteAgain()
        while !store.canStart { await Task.yield() }
        #expect(paste.requests.count == 2)
        #expect(paste.requests[0].1 != paste.requests[1].1)
    }

    @Test func cancellationAfterKeyIsNotReportedAsRetraction() async {
        let paste = StubPaste(); paste.blocked = true
        let store = AppStore(service: QuickTranscriber(), pasteService: paste)
        store.armFixedTextTest(); store.handleGlobalShortcut()
        while paste.continuation == nil { await Task.yield() }
        await store.cancel()
        #expect(store.phase == .ready)
        #expect(store.status.contains("未撤回"))
        #expect(!store.transcript.isEmpty)
    }

    @Test func cancellationAfterKeyPreservesCleanupFailure() async {
        let paste = StubPaste()
        paste.blocked = true
        paste.cancellationOutcome = .sentWithCleanupFailure("已发送粘贴，但剪贴板恢复失败")
        let store = AppStore(service: QuickTranscriber(), pasteService: paste)
        store.armFixedTextTest(); store.handleGlobalShortcut()
        while paste.continuation == nil { await Task.yield() }

        await store.cancel()

        #expect(store.phase == .failed)
        #expect(store.status == "已发送粘贴，但剪贴板恢复失败")
        #expect(!store.transcript.isEmpty)
    }

    @Test func permissionFailurePreservesTestAndDoesNotStartCapture() {
        let paste = StubPaste(); paste.accessibilityGranted = false
        let store = AppStore(service: QuickTranscriber(), pasteService: paste)
        store.armFixedTextTest(); store.handleGlobalShortcut()
        #expect(store.phase == .failed)
        #expect(store.fixedTextTestArmed)
        #expect(paste.requests.isEmpty)
    }
}
