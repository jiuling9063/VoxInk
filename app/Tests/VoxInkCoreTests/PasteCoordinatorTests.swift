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
    var postedTarget: PasteTarget?
    var postedUsingControl = false
    var restored: PasteboardSnapshot?
    var delays: [Duration] = []
    var cleanupDelays: [Duration] = []
    var onDelay: ((Int) -> Void)?
    var onCleanupDelay: (() -> Void)?
    var beforeRestore: (() -> Void)?
    var afterWriteFailureChangeCount: Int?
    var pauseCleanup = false
    var cleanupContinuation: CheckedContinuation<Void, Never>?
    var snapshotCount = 0
    var onSnapshot: (() -> Void)?

    var capturedTarget: PasteTarget?
    var currentDevice: String?
    func captureTarget() -> PasteTarget? { capturedTarget }
    func remoteDeviceName(for target: PasteTarget, candidates: [String]) -> String? {
        currentDevice.flatMap { candidates.contains($0) ? $0 : nil }
    }
    var accessibilityGranted: Bool { accessibility }
    func requestAccessibility() -> Bool { accessibility }
    func isTargetValid(_ target: PasteTarget) -> Bool { targetIsValid }
    func activateAndConfirm(_ target: PasteTarget, timeout: Duration) async -> Bool { focused }
    func isKnownSecureFocusedField() -> Bool { secure }
    func pasteboardSnapshot() throws -> PasteboardSnapshot {
        snapshotCount += 1
        onSnapshot?()
        return try snapshotResult.get()
    }
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
    func postPaste(to target: PasteTarget, usingControl: Bool) -> Bool {
        postedPasteCount += 1
        postedTarget = target
        postedUsingControl = usingControl
        return true
    }
    func delay(for duration: Duration) async {
        delays.append(duration)
        onDelay?(delays.count)
    }
    func delayIgnoringCancellation(for duration: Duration) async {
        cleanupDelays.append(duration)
        onCleanupDelay?()
        if pauseCleanup { await withCheckedContinuation { cleanupContinuation = $0 } }
    }
}

private struct FakeError: Error {}

@Test func remoteProfilesMatchExactlyAndRejectAmbiguity() {
    let profiles = RemoteDeviceProfiles.make(mac: " Mini ， Shared,Mini", windows: "PC\nShared")
    #expect(profiles == ["Mini": false, "PC": true])
    #expect(RemoteDeviceProfiles.match(labels: [" Mini "], candidates: Array(profiles.keys)) == "Mini")
    #expect(RemoteDeviceProfiles.match(labels: ["Mini", "PC"], candidates: Array(profiles.keys)) == nil)
    #expect(RemoteDeviceProfiles.match(labels: ["Mini 2"], candidates: Array(profiles.keys)) == nil)
}

@Test @MainActor func remoteDeviceSelectsPasteAndFreezesFallbackAtCapture() async throws {
    for device in ["Mini", "PC", "Unknown"] {
        let environment = FakePasteEnvironment()
        environment.capturedTarget = .init(pid: 43, bundleID: "com.netease.uuremote", name: "UU")
        environment.currentDevice = device
        let coordinator = PasteCoordinator(environment: environment)
        coordinator.setRemoteDevices(["Mini": false, "PC": true])
        let captured = try #require(coordinator.captureTarget())
        coordinator.setUUWindowsPaste(true)
        #expect(await coordinator.paste(text: "test", to: captured, sessionID: UUID()) == .sent)
        await coordinator.finishPendingCleanup()
        #expect(environment.postedUsingControl == (device == "PC"))
    }
}

@Test @MainActor func remoteSwitchDuringSynchronizationDoesNotPaste() async throws {
    let environment = FakePasteEnvironment()
    environment.capturedTarget = .init(pid: 43, bundleID: "com.netease.uuremote", name: "UU")
    environment.currentDevice = "Mini"
    let coordinator = PasteCoordinator(environment: environment)
    coordinator.setRemoteDevices(["Mini": false, "PC": true])
    let captured = try #require(coordinator.captureTarget())
    environment.onDelay = { _ in environment.currentDevice = "PC" }
    let result = await coordinator.paste(text: "test", to: captured, sessionID: UUID())
    #expect(!result.wasIssued)
    #expect(environment.postedPasteCount == 0)
    #expect(environment.restored != nil)
}

@Test @MainActor func losingDeviceBeforePasteDoesNotWriteClipboard() async throws {
    let environment = FakePasteEnvironment()
    environment.capturedTarget = .init(pid: 43, bundleID: "com.netease.uuremote", name: "UU")
    environment.currentDevice = "Mini"
    let coordinator = PasteCoordinator(environment: environment)
    coordinator.setRemoteDevices(["Mini": false])
    let captured = try #require(coordinator.captureTarget())
    environment.currentDevice = nil
    #expect(!(await coordinator.paste(text: "test", to: captured, sessionID: UUID())).wasIssued)
    #expect(environment.snapshotCount == 0)
    #expect(environment.postedPasteCount == 0)
}

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
func pasteEventsUseOnlyTheSelectedModifier() throws {
    let events = try #require(AppKitPasteEnvironment.pasteEvents(usingControl: true))
    #expect(events.map(\.type) == [.keyDown, .keyUp])
    #expect(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [9, 9])
    #expect(events.allSatisfy { $0.flags == .maskControl })
    let local = try #require(AppKitPasteEnvironment.pasteEvents(usingControl: false))
    #expect(local.map(\.type) == [.keyDown, .keyUp])
    #expect(local.allSatisfy { $0.flags == .maskCommand })
}

@Test @MainActor
func windowsPasteIsOptInAndOnlyAffectsUU() async {
    for enabled in [false, true] {
        for bundleID in ["com.netease.uuremote", "test.target"] {
            let environment = FakePasteEnvironment()
            let coordinator = PasteCoordinator(environment: environment)
            coordinator.setUUWindowsPaste(enabled)
            let destination = PasteTarget(pid: 43, bundleID: bundleID, name: "Target")
            #expect(await coordinator.paste(text: "test", to: destination, sessionID: UUID()) == .sent)
            await coordinator.finishPendingCleanup()
            #expect(environment.postedPasteCount == 1)
            #expect(environment.postedUsingControl == (enabled && bundleID == "com.netease.uuremote"))
        }
    }
}

@Test @MainActor
func uuRemoteAllowsClipboardSynchronizationBeforePasteAndRestore() async {
    let environment = FakePasteEnvironment()
    let remote = PasteTarget(pid: 43, bundleID: "com.netease.uuremote", name: "UU远程")
    let coordinator = PasteCoordinator(environment: environment)
    environment.onDelay = { _ in #expect(environment.postedPasteCount == 0) }
    environment.onCleanupDelay = {
        #expect(environment.postedPasteCount == 1)
        #expect(environment.restored == nil)
    }
    #expect(await coordinator.paste(text: "remote", to: remote, sessionID: UUID()) == .sent)
    #expect(environment.postedTarget == remote)
    #expect(environment.restored == nil)
    await coordinator.finishPendingCleanup()
    #expect(environment.delays == [.seconds(2)])
    #expect(environment.cleanupDelays == [.seconds(3)])
    #expect(environment.restored != nil)
}

@Test @MainActor
func uuCleanupDoesNotBlockReturnAndPreservesNewCopy() async {
    let environment = FakePasteEnvironment()
    environment.pauseCleanup = true
    let coordinator = PasteCoordinator(environment: environment)
    let remote = PasteTarget(pid: 43, bundleID: "com.netease.uuremote", name: "UU")
    #expect(await coordinator.paste(text: "first", to: remote, sessionID: UUID()) == .sent)
    while environment.cleanupContinuation == nil { await Task.yield() }
    #expect(environment.restored == nil)
    environment.changeCount += 1
    environment.cleanupContinuation?.resume()
    await coordinator.finishPendingCleanup()
    #expect(environment.restored == nil)
}

@Test @MainActor
func nextPasteWaitsForPreviousCleanupAndCanBeCancelled() async {
    let environment = FakePasteEnvironment()
    environment.pauseCleanup = true
    let coordinator = PasteCoordinator(environment: environment)
    let remote = PasteTarget(pid: 43, bundleID: "com.netease.uuremote", name: "UU")
    #expect(await coordinator.paste(text: "first", to: remote, sessionID: UUID()) == .sent)
    while environment.cleanupContinuation == nil { await Task.yield() }
    let next = Task { await coordinator.paste(text: "second", to: target, sessionID: UUID()) }
    for _ in 0..<10 { await Task.yield() }
    #expect(environment.snapshotCount == 1)
    coordinator.cancel()
    environment.cleanupContinuation?.resume()
    #expect(await next.value == .cancelledBeforeSend)
    #expect(environment.postedPasteCount == 1)
    #expect(environment.restored != nil)
}

@Test @MainActor
func uuCleanupFailureIsReportedAfterPasteReturned() async {
    let environment = FakePasteEnvironment()
    environment.restoreSucceeds = false
    let coordinator = PasteCoordinator(environment: environment)
    let session = UUID()
    var failedSession: UUID?
    coordinator.setCleanupFailureHandler { failedSession = $0 }
    let remote = PasteTarget(pid: 43, bundleID: "com.netease.uuremote", name: "UU")
    #expect(await coordinator.paste(text: "first", to: remote, sessionID: session) == .sent)
    await coordinator.finishPendingCleanup()
    #expect(failedSession == session)
}

@Test @MainActor
func consecutiveRemotePastesRestoreOriginalBeforeTakingNextSnapshot() async {
    let environment = FakePasteEnvironment()
    environment.pauseCleanup = true
    let coordinator = PasteCoordinator(environment: environment)
    let remote = PasteTarget(pid: 43, bundleID: "com.netease.uuremote", name: "UU")
    #expect(await coordinator.paste(text: "first", to: remote, sessionID: UUID()) == .sent)
    while environment.cleanupContinuation == nil { await Task.yield() }
    environment.onSnapshot = { #expect(environment.restored != nil) }
    let next = Task { await coordinator.paste(text: "second", to: remote, sessionID: UUID()) }
    for _ in 0..<10 { await Task.yield() }
    #expect(environment.snapshotCount == 1)
    environment.pauseCleanup = false
    environment.cleanupContinuation?.resume()
    #expect(await next.value == .sent)
    await coordinator.finishPendingCleanup()
    #expect(environment.snapshotCount == 2)
    #expect(environment.postedPasteCount == 2)
}

@Test @MainActor
func remoteTimingOnlyChangesUUPaste() async {
    for timing in RemotePasteTiming.allCases {
        let environment = FakePasteEnvironment()
        let coordinator = PasteCoordinator(environment: environment)
        coordinator.setRemotePasteTiming(timing)
        let remote = PasteTarget(pid: 43, bundleID: "com.netease.uuremote", name: "UU")
        #expect(await coordinator.paste(text: "first", to: remote, sessionID: UUID()) == .sent)
        await coordinator.finishPendingCleanup()
        #expect(environment.delays == [timing.delay])
        environment.delays = []
        #expect(await coordinator.paste(text: "next", to: target, sessionID: UUID()) == .sent)
        #expect(environment.delays == [.milliseconds(150)])
    }
}

@Test @MainActor
func localPasteKeepsExistingTiming() async {
    let environment = FakePasteEnvironment()
    let coordinator = PasteCoordinator(environment: environment)
    #expect(await coordinator.paste(text: "local", to: target, sessionID: UUID()) == .sent)
    await coordinator.finishPendingCleanup()
    #expect(environment.delays == [.milliseconds(150)])
    #expect(environment.cleanupDelays == [.milliseconds(1_200)])
}

@Test @MainActor
func cancellingWhileUUSynchronizesDoesNotSendPaste() async {
    let environment = FakePasteEnvironment()
    let coordinator = PasteCoordinator(environment: environment)
    environment.onDelay = { _ in coordinator.cancel() }
    let remote = PasteTarget(pid: 43, bundleID: "com.netease.uuremote", name: "UU远程")
    #expect(await coordinator.paste(text: "remote", to: remote, sessionID: UUID()) == .cancelledBeforeSend)
    #expect(environment.postedPasteCount == 0)
    #expect(environment.restored != nil)
}

@Test @MainActor
func copyingDuringUUSynchronizationPreservesUserClipboard() async {
    let environment = FakePasteEnvironment()
    let coordinator = PasteCoordinator(environment: environment)
    environment.onDelay = { _ in environment.changeCount += 1 }
    let remote = PasteTarget(pid: 43, bundleID: "com.netease.uuremote", name: "UU远程")
    #expect(await coordinator.paste(text: "remote", to: remote, sessionID: UUID()) == .failed("剪贴板已被其他操作修改"))
    #expect(environment.postedPasteCount == 0)
    #expect(environment.restored == nil)
}

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
    await coordinator.finishPendingCleanup()
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
    await coordinator.finishPendingCleanup()
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
func cancellationAfterDispatchCannotRetractAndCleanupCompletes() async {
    let environment = FakePasteEnvironment()
    let coordinator = PasteCoordinator(environment: environment)
    environment.onCleanupDelay = { coordinator.cancel() }

    #expect(await coordinator.paste(text: "new", to: target, sessionID: UUID()) == .sent)
    await coordinator.finishPendingCleanup()
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
    await coordinator.finishPendingCleanup()
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
    await coordinator.finishPendingCleanup()
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

    let sessionID = UUID()
    var failureID: UUID?
    coordinator.setCleanupFailureHandler { failureID = $0 }
    let outcome = await coordinator.paste(text: "new", to: target, sessionID: sessionID)
    await coordinator.finishPendingCleanup()
    #expect(outcome == .sent)
    #expect(failureID == sessionID)
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

@Test @MainActor func configuredRemoteApplicationsUseIndependentPasteKeysAndCleanup() async throws {
    for usesControl in [false, true] {
        let env = FakePasteEnvironment()
        env.capturedTarget = .init(pid: 45, bundleID: "test.remote", name: "Remote")
        let coordinator = PasteCoordinator(environment: env)
        coordinator.setRemoteApplications([.init(bundleID: "test.remote", name: "Remote", usesControl: usesControl)])
        let captured = try #require(coordinator.captureTarget())
        coordinator.setRemoteApplications([])
        #expect(await coordinator.paste(text: "text", to: captured, sessionID: UUID()) == .sent)
        await coordinator.finishPendingCleanup()
        #expect(env.postedUsingControl == usesControl)
        #expect(env.delays.first == .seconds(2))
        #expect(env.cleanupDelays == [.seconds(3)])
        #expect(env.restored != nil)
    }
}

@Test @MainActor func remoteApplicationConfigurationNeverLeaksToLocalApps() async throws {
    let env = FakePasteEnvironment()
    env.capturedTarget = .init(pid: 45, bundleID: "test.local", name: "Local")
    let coordinator = PasteCoordinator(environment: env)
    coordinator.setRemoteApplications([.init(bundleID: "test.remote", name: "Remote", usesControl: true)])
    let captured = try #require(coordinator.captureTarget())
    #expect(captured.remoteUsesControl == nil)
    #expect(await coordinator.paste(text: "text", to: captured, sessionID: UUID()) == .sent)
    #expect(!env.postedUsingControl)
    #expect(env.delays.first == .milliseconds(150))
}

@Test @MainActor func genericRemoteCancellationAndClipboardChangeNeverSendPaste() async throws {
    for cancel in [false, true] {
        let env = FakePasteEnvironment()
        env.capturedTarget = .init(pid: 45, bundleID: "test.remote", name: "Remote")
        let coordinator = PasteCoordinator(environment: env)
        coordinator.setRemoteApplications([.init(bundleID: "test.remote", name: "Remote", usesControl: true)])
        let captured = try #require(coordinator.captureTarget())
        env.onDelay = { _ in if cancel { coordinator.cancel() } else { env.changeCount = 99 } }
        let outcome = await coordinator.paste(text: "text", to: captured, sessionID: UUID())
        #expect(!outcome.wasIssued && env.postedPasteCount == 0)
        if !cancel { #expect(env.restored == nil) }
    }
}

@Test @MainActor func localPasteReportsSentBeforeClipboardCleanupFinishes() async {
    let environment = FakePasteEnvironment()
    environment.pauseCleanup = true
    let coordinator = PasteCoordinator(environment: environment)
    let outcome = await coordinator.paste(text: "new", to: target, sessionID: UUID())
    #expect(outcome == .sent)
    #expect(environment.postedPasteCount == 1)
    #expect(environment.restored == nil)
    while environment.cleanupContinuation == nil { await Task.yield() }
    #expect(environment.cleanupDelays == [.milliseconds(1_200)])
    environment.cleanupContinuation?.resume()
    await coordinator.finishPendingCleanup()
    #expect(environment.restored != nil)
}
