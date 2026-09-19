import AppKit
import Testing
@testable import VoxInkUI

@MainActor struct WorkspaceWindowTests {
    @Test func nativeWindowControlsAndToolbarRemainAvailable() throws {
        _ = NSApplication.shared
        let controller = WorkspaceWindowController(store: AppStore(preferences: nil), restoresFrame: false)
        defer { controller.close() }
        let window = try #require(controller.window)
        #expect(window.standardWindowButton(.closeButton) != nil)
        #expect(window.standardWindowButton(.miniaturizeButton) != nil)
        #expect(window.standardWindowButton(.zoomButton) != nil)
        #expect(window.styleMask.contains(.resizable))
        #expect(window.titleVisibility == .hidden)
        #expect(window.toolbar?.isVisible == true)
        #expect(window.frameAutosaveName.isEmpty)
    }

    @Test func pageChangesUpdateTheAccessibleWindowTitle() throws {
        _ = NSApplication.shared
        let controller = WorkspaceWindowController(store: AppStore(preferences: nil), restoresFrame: false)
        defer { controller.close() }
        let window = try #require(controller.window)
        #expect(window.title == "语音工作台 — 语落 VoxInk")
        controller.navigation.page = .engine
        #expect(window.title == "转录引擎 — 语落 VoxInk")
        controller.navigation.page = .history
        #expect(window.title == "转录历史 — 语落 VoxInk")
        #expect(window.toolbar?.items.contains { $0.itemIdentifier.rawValue == "voxink-model" } == true)
    }
}
