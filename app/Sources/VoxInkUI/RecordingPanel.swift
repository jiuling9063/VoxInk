import VoxInkCore
import AppKit
import SwiftUI

final class NonactivatingRecordingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct RecordingPanelPlacement {
    static func width(in visibleFrame: NSRect) -> CGFloat { min(180, max(1, visibleFrame.width - 32)) }
    static func origin(size: NSSize, in visibleFrame: NSRect) -> NSPoint {
        NSPoint(x: visibleFrame.midX - size.width / 2,
                y: max(visibleFrame.minY, min(visibleFrame.minY + 72, visibleFrame.maxY - size.height - 16)))
    }
}

@MainActor public final class RecordingPanel {
    let panel: NSPanel
    private var dismissal: Task<Void, Never>?
    private var selectedScreen: NSScreen?
    private var wasBusy = false
    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var boundStore: ObjectIdentifier?

    public init() {
        panel = NonactivatingRecordingPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = L("语落语音输入状态")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.contentView = hostingView
    }

    public func update(store: AppStore) {
        guard store.shortcutTargetName != nil else { hide(); return }
        let presentation = RecordingFeedbackPresentation(store: store)
        let replaceContent = boundStore != ObjectIdentifier(store)
        boundStore = ObjectIdentifier(store)
        show(presentation: presentation, replaceContent: replaceContent) { width in
            AnyView(LiveRecordingFeedback(store: store).frame(width: width))
        }
    }

    // The standalone visual checker uses the same panel and view without recording or pasting.
    public func showPreview(_ presentation: RecordingFeedbackPresentation) {
        boundStore = nil
        show(presentation: presentation) { width in
            AnyView(RecordingFeedbackView(presentation: presentation).frame(width: width))
        }
    }

    private func show(presentation: RecordingFeedbackPresentation, replaceContent: Bool = true, content: (CGFloat) -> AnyView) {
        guard presentation.dismissAfter != .zero else { hide(); return }
        dismissal?.cancel()
        let connected = selectedScreen.map { chosen in NSScreen.screens.contains { $0 == chosen } } ?? false
        if !connected || (!wasBusy && presentation.busy) || !panel.isVisible {
            selectedScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        }
        wasBusy = presentation.busy
        guard let frame = selectedScreen?.visibleFrame else { hide(); return }
        let width = RecordingPanelPlacement.width(in: frame)
        let size = NSSize(width: width, height: presentation.panelHeight)
        if replaceContent || panel.frame.width != width { hostingView.rootView = content(width) }
        let rect = NSRect(origin: RecordingPanelPlacement.origin(size: size, in: frame), size: size)
        if panel.frame != rect { panel.setFrame(rect, display: false) }
        if !panel.isVisible {
            hostingView.layoutSubtreeIfNeeded()
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
        }
        if let delay = presentation.dismissAfter {
            dismissal = Task { [weak self] in
                do { try await Task.sleep(for: delay) } catch { return }
                self?.hide()
            }
        }
    }

    public func hide() {
        dismissal?.cancel(); dismissal = nil
        panel.orderOut(nil); selectedScreen = nil; wasBusy = false
    }
}

private struct LiveRecordingFeedback: View {
    @ObservedObject var store: AppStore
    var body: some View { RecordingFeedbackView(presentation: RecordingFeedbackPresentation(store: store)) }
}
