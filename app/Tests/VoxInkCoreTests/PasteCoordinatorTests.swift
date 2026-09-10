import AppKit
import Foundation
import Testing
@testable import VoxInkCore

@MainActor
private final class FakePasteEnvironment: PasteEnvironment {
    var targetIsValid = true
    var focused = true
    var secure = false
    var accessibility = true
    var modifiersReleased = true
    var snapshotResult: Result<PasteboardSnapshot, Error> = .success(.init(items: [], changeCount: 2))
    var writeResult: Result<Int, Error> = .success(2)
    var changeCount = 2
    var restoreSucceeds = true
    var postedPasteCount = 0
    var restored: PasteboardSnapshot?
    var delays: [Duration] = []
    var cleanupDelays: [Duration] = []
    var onDelay: ((Int) -> Void)?
    var onCleanupDelay: (() -> Void)?
    var beforeRestore: (() -> Void)?
    var afterWriteFailureChangeCount: Int?

    func captureTarget() -> PasteTarget? { nil }
    var accessibilityGranted: Bool { accessibility }
    func requestAccessibility() -> Bool { accessibility }
    func isTargetValid(_ target: PasteTarget) -> Bool { targetIsValid }
    func activateAndConfirm(_ target: PasteTarget, timeout: Duration) async -> Bool { focused }
    func isKnownSecureFocusedField() -> Bool { secure }
    func pasteboardSnapshot() throws -> PasteboardSnapshot { try snapshotResult.get() }
    func writePlainText(_ text: String) throws -> Int {
        do {
            let version = try writeResult.get()
            changeCount = version
            return version
        } catch {
            if let afterWriteFailureChangeCount { changeCount = afterWriteFailureChangeCount }
            throw error
        }
    }
    func currentPasteboardChangeCount() -> Int { changeCount }
    func restorePasteboard(_ snapshot: PasteboardSnapshot, expectedChangeCount: Int) -> PasteboardRestoreResult {
        beforeRestore?()
        guard changeCount == expectedChangeCount else { return .skippedOwnershipLost }
        restored = snapshot
        return restoreSucceeds ? .restored : .failed
    }
    func areCommandModifiersReleased() -> Bool { modifiersReleased }
    func postCommandV() -> Bool {
        postedPasteCount += 1
        return true
    }
    func delay(for duration: Duration) async {
        delays.append(duration)
        onDelay?(delays.count)
    }
    func delayIgnoringCancellation(for duration: Duration) async {
        cleanupDelays.append(duration)
        onCleanupDelay?()
    }
}

private struct FakeError: Error {}

@MainActor
private final class RacingPasteboard: PasteboardAccess {
    var changeCount = 10
    var pasteboardItems: [NSPasteboardItem]? = []
    var types: [NSPasteboard.PasteboardType] = []
    var copyBetweenClearAndSet = false

    func clearContents() -> Int {
        changeCount += 1
        return changeCount
    }
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        if copyBetweenClearAndSet { changeCount += 1 }
        return true
    }
    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool { true }
}

private let target = PasteTarget(pid: 42, bundleID: "test.target", name: "Target")

@Test @MainActor
func restoresAllPasteboardItemsAndTypesAfterSend() async {
    let environment = FakePasteEnvironment()
    let snapshot = PasteboardSnapshot(items: [
        .init(types: ["public.utf8-plain-text": Data("first".utf8), "public.html": Data("<b>x</b>".utf8)]),
        .init(types: ["public.png": Data([0, 1, 2])])
    ], changeCount: 2)
    environment.snapshotResult = .success(snapshot)
    let coordinator = PasteCoordinator(environment: environment)

    #expect(await coordinator.paste(text: "new", to: target, sessionID: UUID()) == .sent)
    #expect(environment.postedPasteCount == 1)
    #expect(environment.restored == snapshot)
}

@Test @MainActor
func userCopyBeforeKeyPreventsPasteAndDoesNotRestore() async {
    let environment = FakePasteEnvironment()
    environment.onDelay = { index in if index == 1 { environment.changeCount += 1 } }
    let coordinator = PasteCoordinator(environment: environment)

    let result = await coordinator.paste(text: "new", to: target, sessionID: UUID())
    #expect(result == .failed("剪贴板已被其他操作修改"))
    #expect(environment.postedPasteCount == 0)
    #expect(environment.restored == nil)
}

@Test @MainActor
func userCopyAfterKeyKeepsNewClipboardAndStillReportsSent() async {
    let environment = FakePasteEnvironment()
    environment.onCleanupDelay = { environment.changeCount += 1 }
    let coordinator = PasteCoordinator(environment: environment)

    #expect(await coordinator.paste(text: "new", to: target, sessionID: UUID()) == .sent)
    #expect(environment.postedPasteCount == 1)
    #expect(environment.restored == nil)
}

@Test @MainActor
func cancellationBeforeKeyStopsPostingAndCleansUp() async {
    let environment = FakePasteEnvironment()
    let coordinator = PasteCoordinator(environment: environment)
    environment.onDelay = { index in if index == 1 { coordinator.cancel() } }

    #expect(await coordinator.paste(text: "new", to: target, sessionID: UUID()) == .cancelledBeforeSend)
    #expect(environment.postedPasteCount == 0)
    #expect(environment.restored != nil)
}

@Test @MainActor
func cancellationAfterKeyWaitsForCleanupAndCannotClaimRetraction() async {
    let environment = FakePasteEnvironment()
    let coordinator = PasteCoordinator(environment: environment)
    environment.onCleanupDelay = { coordinator.cancel() }

    #expect(await coordinator.paste(text: "new", to: target, sessionID: UUID()) == .cancelledAfterSend)
    #expect(environment.postedPasteCount == 1)
    #expect(environment.restored != nil)
}

@Test @MainActor
func taskCancellationAfterKeyStillUsesNonCancellableCleanupDelay() async {
    let environment = FakePasteEnvironment()
    let coordinator = PasteCoordinator(environment: environment)
    var pasteTask: Task<PasteOutcome, Never>!
    environment.onCleanupDelay = { pasteTask.cancel() }
    pasteTask = Task { await coordinator.paste(text: "new", to: target, sessionID: UUID()) }

    let outcome = await pasteTask.value
    #expect(outcome == .sent)
    #expect(environment.cleanupDelays == [.milliseconds(1_200)])
    #expect(environment.restored != nil)
}

@Test @MainActor
func repeatedSessionIsNeverPastedTwice() async {
    let environment = FakePasteEnvironment()
    let coordinator = PasteCoordinator(environment: environment)
    let sessionID = UUID()

    #expect(await coordinator.paste(text: "one", to: target, sessionID: sessionID) == .sent)
    #expect(await coordinator.paste(text: "two", to: target, sessionID: sessionID) == .failed("该会话已尝试粘贴"))
    #expect(environment.postedPasteCount == 1)
}

@Test @MainActor
func focusFailureDoesNotMutateClipboard() async {
    let environment = FakePasteEnvironment()
    environment.focused = false
    let coordinator = PasteCoordinator(environment: environment)

    #expect(await coordinator.paste(text: "new", to: target, sessionID: UUID()) == .failed("无法确认粘贴目标"))
    #expect(environment.restored == nil)
    #expect(environment.postedPasteCount == 0)
}

@Test @MainActor
func invalidSnapshotAndWriteFailureFailClosed() async {
    let snapshotEnvironment = FakePasteEnvironment()
    snapshotEnvironment.snapshotResult = .failure(FakeError())
    let snapshotCoordinator = PasteCoordinator(environment: snapshotEnvironment)
    #expect(await snapshotCoordinator.paste(text: "new", to: target, sessionID: UUID()) == .failed("无法完整读取剪贴板"))

    let writeEnvironment = FakePasteEnvironment()
    writeEnvironment.writeResult = .failure(FakeError())
    let writeCoordinator = PasteCoordinator(environment: writeEnvironment)
    #expect(await writeCoordinator.paste(text: "new", to: target, sessionID: UUID()) == .failed("无法写入剪贴板"))
    #expect(writeEnvironment.postedPasteCount == 0)
    #expect(writeEnvironment.restored == nil)
}

@Test @MainActor
func writeFailureDoesNotOverwriteConcurrentUserCopy() async {
    let environment = FakePasteEnvironment()
    environment.writeResult = .failure(PasteboardMutationError(ownedChangeCount: 3))
    environment.afterWriteFailureChangeCount = 4
    let coordinator = PasteCoordinator(environment: environment)

    #expect(await coordinator.paste(text: "new", to: target, sessionID: UUID()) == .failed("无法写入剪贴板"))
    #expect(environment.restored == nil)
}

@Test @MainActor
func userCopyDuringRestorePrebuildIsNeverCleared() async {
    let environment = FakePasteEnvironment()
    environment.beforeRestore = { environment.changeCount += 1 }
    let coordinator = PasteCoordinator(environment: environment)

    #expect(await coordinator.paste(text: "new", to: target, sessionID: UUID()) == .sent)
    #expect(environment.restored == nil)
}

@Test @MainActor
func nativeAdapterDoesNotClaimCopyBetweenClearAndSet() {
    let pasteboard = RacingPasteboard()
    pasteboard.copyBetweenClearAndSet = true
    let environment = AppKitPasteEnvironment(pasteboard: pasteboard)

    do {
        _ = try environment.writePlainText("new")
        Issue.record("Expected ownership race to fail")
    } catch let error as PasteboardMutationError {
        #expect(error.ownedChangeCount == 11)
        #expect(pasteboard.changeCount == 12)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test @MainActor
func revokedAccessibilityBeforeKeyFailsUnsentAndRestoresClipboard() async {
    let environment = FakePasteEnvironment()
    environment.onDelay = { index in if index == 1 { environment.accessibility = false } }
    let coordinator = PasteCoordinator(environment: environment)

    let outcome = await coordinator.paste(text: "new", to: target, sessionID: UUID())
    #expect(outcome == .failed("辅助功能权限已失效"))
    #expect(!outcome.wasIssued)
    #expect(environment.postedPasteCount == 0)
    #expect(environment.restored != nil)
}

@Test @MainActor
func emptyTextFailsBeforeEnvironmentMutation() async {
    let environment = FakePasteEnvironment()
    environment.focused = false
    let coordinator = PasteCoordinator(environment: environment)

    #expect(await coordinator.paste(text: " \n", to: target, sessionID: UUID()) == .failed("没有可粘贴的文字"))
    #expect(environment.postedPasteCount == 0)
    #expect(environment.restored == nil)
}

@Test @MainActor
func cleanupFailureAfterKeyPreservesIssuedTruth() async {
    let environment = FakePasteEnvironment()
    environment.restoreSucceeds = false
    let coordinator = PasteCoordinator(environment: environment)

    let outcome = await coordinator.paste(text: "new", to: target, sessionID: UUID())
    #expect(outcome == .sentWithCleanupFailure("已发送粘贴，但剪贴板恢复失败"))
    #expect(outcome.wasIssued)
}

@Test @MainActor
func secureFieldAndHeldModifiersPreventKeyEvent() async {
    let secureEnvironment = FakePasteEnvironment()
    secureEnvironment.secure = true
    let secureCoordinator = PasteCoordinator(environment: secureEnvironment)
    #expect(await secureCoordinator.paste(text: "new", to: target, sessionID: UUID()) == .failed("安全输入框不允许自动粘贴"))

    let modifierEnvironment = FakePasteEnvironment()
    modifierEnvironment.modifiersReleased = false
    let modifierCoordinator = PasteCoordinator(environment: modifierEnvironment)
    #expect(await modifierCoordinator.paste(text: "new", to: target, sessionID: UUID()) == .failed("修饰键未释放"))
    #expect(modifierEnvironment.postedPasteCount == 0)
    #expect(modifierEnvironment.restored != nil)
}
