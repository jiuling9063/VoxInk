import AppKit
import SwiftUI
import VoxInkUI

private struct Example: Identifiable {
    let id: String
    let value: RecordingFeedbackPresentation
}

@MainActor private struct FeedbackGallery: View {
    @State private var dark = true
    @State private var input = ""
    @State private var panel = RecordingPanel()
    @State private var panelEvidence = "尚未显示独立浮层"
    private let examples: [Example] = [
        .init(id: "按住录音", value: .init(phase: .recording, status: "正在录音 · 松开快捷键后识别并写入", target: "微信 · 文件传输助手", elapsed: 12, level: 0.65, cancellationAvailable: true)),
        .init(id: "按两次录音", value: .init(phase: .recording, status: "正在录音 · 再按快捷键结束并写入", target: "备忘录", elapsed: 59, level: 0.2, cancellationAvailable: true)),
        .init(id: "加载", value: .init(phase: .loading, status: "正在检查麦克风权限…", target: "测试窗口", cancellationAvailable: true)),
        .init(id: "识别", value: .init(phase: .transcribing, status: "正在识别 · 首次使用可能需要加载模型…", target: "测试窗口", cancellationAvailable: true)),
        .init(id: "写入", value: .init(phase: .pasting, status: "正在写入测试窗口并清理剪贴板…", target: "测试窗口", cancellationAvailable: true)),
        .init(id: "取消", value: .init(phase: .cancelling, status: "正在取消…", target: "测试窗口")),
        .init(id: "失败和长文字", value: .init(phase: .failed, status: "文字已保留。原目标输入框已失去焦点，请重新点选输入框，确认没有重复内容后，再从语落窗口手动重新粘贴。", target: "一个名称较长的远程应用与文件传输助手测试窗口")),
        .init(id: "取消键不可用", value: .init(phase: .recording, status: "正在录音 · 松开快捷键后识别并写入", target: "测试窗口", elapsed: 8, level: 0.4)),
        .init(id: "已结束", value: .init(phase: .ready, status: "已取消 · 未发出粘贴", target: "测试窗口"))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("浮层状态检查 · 模拟数据").font(.title2.bold())
            Text("使用产品浮层组件；此程序不录音、不识别、不访问剪贴板，不注册全局快捷键。")
                .foregroundStyle(.secondary)
            HStack {
                Toggle("深色", isOn: $dark).onChange(of: dark) { _, value in
                    NSApp.appearance = NSAppearance(named: value ? .darkAqua : .aqua)
                }
                Button("3 秒后显示浮层") {
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        let keyWindow = NSApp.keyWindow
                        let responder = keyWindow?.firstResponder
                        panel.showPreview(examples[0].value)
                        let floating = NSApp.windows.first { $0.title == "语落语音输入状态" }
                        panelEvidence = "浮层可见：\(floating?.isVisible == true) · 尺寸：\(Int(floating?.frame.width ?? 0)) × \(Int(floating?.frame.height ?? 0)) · 键盘窗口保持：\(keyWindow === NSApp.keyWindow) · 输入焦点保持：\(responder === NSApp.keyWindow?.firstResponder)"
                    }
                }
                Button("隐藏浮层") { panel.hide(); panelEvidence = "浮层已隐藏" }
                TextField("焦点检查：显示前后在这里输入", text: $input)
            }
            Text(panelEvidence).font(.caption).accessibilityIdentifier("panelEvidence")
            ScrollView {
                LazyVGrid(columns: [GridItem(.fixed(430)), GridItem(.fixed(430))], alignment: .leading, spacing: 20) {
                    ForEach(examples) { example in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(example.id).font(.caption).foregroundStyle(.secondary)
                            RecordingFeedbackView(presentation: example.value)
                        }
                    }
                }.padding(8)
            }
        }.padding(20).frame(width: 920, height: 740)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { NSApp.appearance = NSAppearance(named: .darkAqua) }
    }
}

@main private struct FeedbackCheck: App {
    var body: some Scene {
        Window("VoxInk 浮层检查", id: "feedback-check") { FeedbackGallery() }
            .windowResizability(.contentSize)
    }
}
