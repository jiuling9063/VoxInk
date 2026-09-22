import AppKit
import SwiftUI
import Testing
@testable import VoxInkUI

@MainActor struct RecordingFeedbackTests {
    @Test func cancellationHintReflectsActualRegistrationAndPasteBoundary() {
        let store = AppStore(preferences: nil)
        #expect(!store.cancellationShortcutAvailable)
        store.setCancellationShortcutAvailable(true)
        #expect(store.cancellationShortcutAvailable)
        store.setCancellationShortcutAvailable(false)
        #expect(!store.cancellationShortcutAvailable)
        for phase in [AppStore.Phase.loading, .recording, .transcribing] {
            #expect(RecordingFeedbackPresentation(phase: phase, status: "", target: "", cancellationAvailable: true).hint == "Esc 取消")
            #expect(!RecordingFeedbackPresentation(phase: phase, status: "", target: "").hint.contains("Esc"))
        }
        #expect(RecordingFeedbackPresentation(phase: .pasting, status: "", target: "", cancellationAvailable: true).hint.contains("不会撤回"))
        #expect(!RecordingFeedbackPresentation(phase: .cancelling, status: "", target: "", cancellationAvailable: true).hint.contains("Esc"))
    }

    @Test func busyFeedbackStaysAndFailureGivesMoreReadingTime() {
        for phase in [AppStore.Phase.loading, .recording, .transcribing, .pasting, .cancelling] {
            #expect(RecordingFeedbackPresentation(phase: phase, status: "", target: "").dismissAfter == nil)
        }
        #expect(RecordingFeedbackPresentation(phase: .ready, status: "", target: "").dismissAfter == .zero)
        #expect(RecordingFeedbackPresentation(phase: .failed, status: "", target: "").dismissAfter == .seconds(8))
    }

    @Test func invalidMeterValuesCannotBreakFeedbackRendering() {
        let invalid = RecordingFeedbackPresentation(phase: .recording, status: "", target: "", elapsed: .infinity, level: .nan)
        #expect(invalid.safeElapsed == 0); #expect(invalid.safeLevel == 0)
        let excessive = RecordingFeedbackPresentation(phase: .recording, status: "", target: "", elapsed: 80, level: 2)
        #expect(excessive.safeElapsed == 60); #expect(excessive.safeLevel == 1)
    }

    @Test func completionHidesPanelSynchronouslyAndRepeatedUpdatesStayHidden() {
        let feedback = RecordingPanel()
        defer { feedback.hide() }
        feedback.showPreview(.init(phase: .pasting, status: "正在写入", target: "测试"))
        #expect(feedback.panel.isVisible)
        feedback.showPreview(.init(phase: .ready, status: "已发送粘贴", target: "测试"))
        #expect(!feedback.panel.isVisible)
        feedback.showPreview(.init(phase: .ready, status: "已取消", target: "测试"))
        #expect(!feedback.panel.isVisible)
        feedback.showPreview(.init(phase: .failed, status: "写入失败", target: "测试"))
        #expect(feedback.panel.isVisible)
    }

    @Test func placementFitsOffsetAndNarrowDisplays() {
        for frame in [NSRect(x: 0, y: 40, width: 1440, height: 820),
                      NSRect(x: -900, y: -200, width: 800, height: 600),
                      NSRect(x: 2000, y: 100, width: 360, height: 300)] {
            let size = NSSize(width: RecordingPanelPlacement.width(in: frame), height: 240)
            let rect = NSRect(origin: RecordingPanelPlacement.origin(size: size, in: frame), size: size)
            #expect(frame.contains(rect)); #expect(rect.midX == frame.midX)
        }
    }

    @Test func compactHudKeepsFixedHeightForStatusUpdates() {
        let short = RecordingFeedbackPresentation(phase: .failed, status: "识别失败", target: "测试窗口")
        let long = RecordingFeedbackPresentation(phase: .failed,
            status: String(repeating: "文字已保留，请检查原目标输入框并确认没有重复内容，再手动重新粘贴。", count: 3), target: "测试窗口")
        let shortView = NSHostingView(rootView: RecordingFeedbackView(presentation: short).frame(width: 180))
        let longView = NSHostingView(rootView: RecordingFeedbackView(presentation: long).frame(width: 180))
        #expect(longView.fittingSize.height == shortView.fittingSize.height)
        #expect(longView.fittingSize.width == 180)
    }

    @Test func failedHudReservesSpaceForVisibleRecoveryHint() {
        let failed = NSHostingView(rootView: RecordingFeedbackView(presentation:
            .init(phase: .failed, status: "识别失败", target: "测试窗口")).frame(width: 180))
        let recording = NSHostingView(rootView: RecordingFeedbackView(presentation:
            .init(phase: .recording, status: "录音中", target: "测试窗口")).frame(width: 180))
        #expect(failed.fittingSize.height >= 56)
        #expect(recording.fittingSize.height == 44)
        #expect(failed.fittingSize.width == 180)
    }

    @Test func panelCannotTakeKeyboardOrMouseFocus() {
        let feedback = RecordingPanel()
        #expect(!feedback.panel.canBecomeKey)
        #expect(!feedback.panel.canBecomeMain)
        #expect(feedback.panel.styleMask.contains(.nonactivatingPanel))
        #expect(feedback.panel.ignoresMouseEvents)
        #expect(!feedback.panel.hidesOnDeactivate)
        #expect(feedback.panel.collectionBehavior.contains(.fullScreenAuxiliary))
        feedback.hide()
    }
}

@Test func processingFeedbackNamesPhaseAndKeepsAccessibleInputLevel() {
    let recording = RecordingFeedbackPresentation(phase: .recording, status: "录音中", target: "test", level: 0.5)
    #expect(recording.accessibilityStatus.contains("50%"))
    let recognizing = RecordingFeedbackPresentation(phase: .transcribing, status: "正在识别", target: "test")
    #expect(recognizing.phaseTitle == "识别中")
    #expect(recognizing.accessibilityStatus == "正在识别")
    let polishing = RecordingFeedbackPresentation(phase: .transcribing, status: "Arbitrary localized status", target: "test", isPolishing: true)
    #expect(polishing.phaseTitle == "润色中")
    let pasting = RecordingFeedbackPresentation(phase: .pasting, status: "正在写入", target: "test")
    #expect(pasting.phaseTitle == "写入中")
}

@Test @MainActor func hudReusesItsHostingViewAcrossPhases() {
    let feedback = RecordingPanel()
    defer { feedback.hide() }
    let content = feedback.panel.contentView
    for phase in [AppStore.Phase.recording, .transcribing, .pasting, .failed] {
        let presentation = RecordingFeedbackPresentation(phase: phase, status: "test", target: "test")
        feedback.showPreview(presentation)
        #expect(feedback.panel.contentView === content)
        #expect(feedback.panel.frame.height == presentation.panelHeight)
    }
    feedback.showPreview(.init(phase: .ready, status: "done", target: "test"))
    #expect(!feedback.panel.isVisible)
}
