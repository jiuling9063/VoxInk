import AppKit
import SwiftUI

final class NonactivatingRecordingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct RecordingPanelPlacement {
    static func width(in visibleFrame: NSRect) -> CGFloat { min(430, max(1, visibleFrame.width - 32)) }
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

    public init() {
        panel = NonactivatingRecordingPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "语落语音输入状态"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
    }

    public func update(store: AppStore) {
        guard store.shortcutTargetName != nil else { hide(); return }
        let presentation = RecordingFeedbackPresentation(store: store)
        show(presentation: presentation) { width in
            AnyView(LiveRecordingFeedback(store: store).frame(width: width))
        }
    }

    // The standalone visual checker uses the same panel and view without recording or pasting.
    public func showPreview(_ presentation: RecordingFeedbackPresentation) {
        show(presentation: presentation) { width in
            AnyView(RecordingFeedbackView(presentation: presentation).frame(width: width))
        }
    }

    private func show(presentation: RecordingFeedbackPresentation, content: (CGFloat) -> AnyView) {
        guard presentation.dismissAfter != .zero else { hide(); return }
        dismissal?.cancel()
        let connected = selectedScreen.map { chosen in NSScreen.screens.contains { $0 == chosen } } ?? false
        if !connected || (!wasBusy && presentation.busy) || !panel.isVisible {
            selectedScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        }
        wasBusy = presentation.busy
        guard let frame = selectedScreen?.visibleFrame else { hide(); return }
        let width = RecordingPanelPlacement.width(in: frame)
        let measured = NSHostingView(rootView: RecordingFeedbackView(presentation: presentation).frame(width: width))
        let size = NSSize(width: width, height: ceil(measured.fittingSize.height))
        panel.contentView = NSHostingView(rootView: content(width))
        panel.setFrame(NSRect(origin: RecordingPanelPlacement.origin(size: size, in: frame), size: size), display: true)
        panel.orderFrontRegardless()
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
