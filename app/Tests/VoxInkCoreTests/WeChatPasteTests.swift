import AppKit
import Carbon
import Testing
@testable import VoxInkCore

/// Interactive opt-in. Focus an empty File Transfer Assistant draft before running.
/// Read back only the known test suffix, then remove that exact selection.
@Test(.enabled(if: ProcessInfo.processInfo.environment["VOXINK_TEST_WECHAT_SELF_DRAFT"] == "1"))
@MainActor func weChatDraftReceivesAutomaticPaste() async throws {
    let environment = AppKitPasteEnvironment()
    let coordinator = PasteCoordinator(environment: environment)
    let client = try #require(NSRunningApplication.runningApplications(withBundleIdentifier: WeChatPasteCommand.bundleID).first)
    for _ in 0..<100 where !client.isActive { try await Task.sleep(for: .milliseconds(100)) }
    try #require(client.isActive && AXIsProcessTrusted() && !IsSecureEventInputEnabled())
    let target = try #require(coordinator.captureTarget())
    try #require(target.pid == client.processIdentifier && target.weChatWindowToken != nil)
    let window = try #require(WeChatPasteCommand(application: client))
    var windowTarget = target
    windowTarget.weChatWindowToken = window.token
    func stillInDraft() -> Bool { window.matches(windowTarget) && !IsSecureEventInputEnabled() }
    func key(_ code: CGKeyCode, flags: CGEventFlags) throws {
        try #require(stillInDraft())
        for down in [true, false] {
            let event = try #require(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down))
            event.flags = flags
            event.postToPid(client.processIdentifier)
        }
    }

    let marker = "VX" + UUID().uuidString.prefix(8)
    let outcome = await coordinator.paste(text: marker, to: target, sessionID: UUID())
    await coordinator.finishPendingCleanup()
    try #require(outcome == .sent)
    try #require(stillInDraft())
    let original = try environment.pasteboardSnapshot()
    try #require(environment.currentPasteboardChangeCount() == original.changeCount)
    var owned = try environment.writePlainText(UUID().uuidString, transient: true)
    defer { _ = environment.restorePasteboard(original, expectedChangeCount: owned) }
    for _ in marker { try key(123, flags: .maskShift) }
    try key(8, flags: .maskCommand)
    for _ in 0..<30 where environment.currentPasteboardChangeCount() == owned { try await Task.sleep(for: .milliseconds(50)) }
    let copied = environment.currentPasteboardChangeCount()
    try #require(copied != owned)
    let exactMatch = NSPasteboard.general.string(forType: .string) == marker
    try #require(exactMatch && environment.currentPasteboardChangeCount() == copied)
    owned = copied
    try key(51, flags: [])
}
