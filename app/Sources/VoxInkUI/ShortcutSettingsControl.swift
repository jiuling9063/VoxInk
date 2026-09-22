import AppKit
import Carbon
import SwiftUI

struct ShortcutSettingsControl: View {
    @ObservedObject var store: AppStore
    @State private var showingRecorder = false

    var body: some View {
        WorkspacePicker("快捷键", selection: Binding(get: { store.shortcutCombination }, set: { store.setShortcutCombination($0) })) {
            ForEach(ShortcutCombination.allCases, id: \.self) { combination in
                Text(combination.title + (combination == .optionSpace ? "（推荐）" : "")).tag(combination)
            }
            if !ShortcutCombination.allCases.contains(store.shortcutCombination) {
                Text(store.shortcutCombination.title + "（自定义）").tag(store.shortcutCombination)
            }
        }.disabled(!store.canChangeShortcut)
        HStack(alignment: .firstTextBaseline) {
            Text(store.shortcutStatus).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Button("自定义…") {
                if store.beginShortcutRecording() { showingRecorder = true }
            }.disabled(!store.canChangeShortcut)
        }
        .sheet(isPresented: $showingRecorder, onDismiss: { store.finishShortcutRecording() }) {
            ShortcutRecorderSheet(store: store)
        }
    }
}

private struct ShortcutRecorderSheet: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var candidate: ShortcutCombination?
    @State private var message = "搭配 Control、Option 或 Command，再按一个键。"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("自定义快捷键").font(.title2.bold())
            Text("按下你想使用的组合键。保存前，原快捷键暂时停用。")
                .foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.5))
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.6))
                Text(candidate?.title ?? "请按下组合键")
                    .font(.title2.monospaced().weight(.medium)).allowsHitTesting(false)
                ShortcutKeyCapture { event in
                    if event.keyCode == UInt16(kVK_Escape) { cancel(); return }
                    guard !event.isARepeat else { return }
                    if event.keyCode == UInt16(kVK_Return), candidate != nil,
                       ShortcutCombination.carbonModifiers(event.modifierFlags) == 0 { save(); return }
                    let modifiers = ShortcutCombination.carbonModifiers(event.modifierFlags)
                    if let error = ShortcutCombination.validationMessage(keyCode: UInt32(event.keyCode), modifiers: modifiers) {
                        candidate = nil; message = error
                    } else {
                        candidate = ShortcutCombination(keyCode: UInt32(event.keyCode), modifiers: modifiers)
                        message = "可以继续按键修改；保存时会检查是否被其他应用占用。"
                    }
                }
            }.frame(height: 88)
            Text(message).font(.callout).foregroundStyle(.secondary).frame(height: 40, alignment: .topLeading)
            HStack {
                Text("Return 保存 · Esc 取消").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("取消", action: cancel).keyboardShortcut(.cancelAction)
                Button("保存", action: save).keyboardShortcut(.defaultAction).disabled(candidate == nil)
            }
        }
        .padding(24).frame(width: 440)
        .onDisappear { store.finishShortcutRecording() }
    }

    private func save() {
        guard let candidate else { return }
        store.finishShortcutRecording(candidate)
        dismiss()
    }

    private func cancel() {
        store.finishShortcutRecording()
        dismiss()
    }
}

/// Only the focused recorder handles keystrokes; no global event monitor is installed.
private struct ShortcutKeyCapture: NSViewRepresentable {
    let receive: (NSEvent) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.receive = receive
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.textField)
        view.setAccessibilityLabel("快捷键录制区域")
        view.setAccessibilityHelp("按组合键录制；按 Return 保存，按 Esc 取消。")
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) { nsView.receive = receive }

    final class CaptureView: NSView {
        var receive: ((NSEvent) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { window.makeFirstResponder(self) }
        }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == UInt16(kVK_Tab) {
                if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
                else { window?.selectNextKeyView(self) }
                return
            }
            receive?(event)
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
        override func cancelOperation(_ sender: Any?) {
            if let event = NSApp.currentEvent { receive?(event) }
        }
    }
}
