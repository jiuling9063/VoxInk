import AppKit
import Testing
@testable import VoxInkCore

/// Opt in on a Mac desktop with Accessibility access. TextEdit saves the received
/// text to a unique test document, so dispatching the key alone cannot pass.
@Test(.enabled(if: ProcessInfo.processInfo.environment["VOXINK_TEST_TEXTEDIT_PASTE"] == "1"))
@MainActor func textEditReceivesExactlyOnePaste() async throws {
    try #require(AXIsProcessTrusted())
    let workspace = NSWorkspace.shared
    let previous = workspace.frontmostApplication
    let bundleID = "com.apple.TextEdit"
    let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier)
    let url = try #require(workspace.urlForApplication(withBundleIdentifier: bundleID))
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("VoxInk-paste-\(UUID()).txt")
    try Data().write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let config = NSWorkspace.OpenConfiguration()
    config.createsNewApplicationInstance = true
    config.arguments = ["-ApplePersistenceIgnoreState", "YES"]
    let editor = try await workspace.open([file], withApplicationAt: url, configuration: config)
    try #require(!existing.contains(editor.processIdentifier))
    defer {
        editor.terminate()
        if editor.isActive { previous?.activate(options: []) }
    }

    let ax = AXUIElementCreateApplication(editor.processIdentifier)
    func focusedDocumentIsFixture() -> Bool {
        var window: CFTypeRef?, document: CFTypeRef?
        guard editor.isActive, AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID(),
              AXUIElementCopyAttributeValue(unsafeDowncast(window, to: AXUIElement.self), kAXDocumentAttribute as CFString, &document) == .success,
              let path = document as? String, let docURL = URL(string: path) else { return false }
        return docURL.resolvingSymlinksInPath() == file.resolvingSymlinksInPath()
    }
    for _ in 0..<50 where !focusedDocumentIsFixture() { try await Task.sleep(for: .milliseconds(100)) }
    try #require(focusedDocumentIsFixture())
    let coordinator = PasteCoordinator()
    let target = try #require(coordinator.captureTarget())
    try #require(target.pid == editor.processIdentifier)
    let text = "语落 TextEdit \(UUID())"
    let outcome = await coordinator.paste(text: text, to: target, sessionID: UUID())
    await coordinator.finishPendingCleanup()
    try #require(outcome == .sent)
    try #require(focusedDocumentIsFixture())
    for down in [true, false] {
        let save = try #require(CGEvent(keyboardEventSource: nil, virtualKey: 1, keyDown: down))
        save.flags = .maskCommand
        save.postToPid(editor.processIdentifier)
    }
    for _ in 0..<40 where (try String(contentsOf: file, encoding: .utf8)) != text {
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == text)
}
