import SwiftUI

struct WorkspaceHelpView: View {
    @ObservedObject var store: AppStore
    let showDashboard: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("说话，变成文字", systemImage: "waveform").font(.headline)
                    Spacer()
                    Text(store.shortcutCombination.title)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(VoxInkTheme(scheme: scheme).accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) { steps(horizontal: true) }
                    VStack(alignment: .leading, spacing: 20) { steps(horizontal: false) }
                }
                Divider()
                Label("Esc 随时取消 · 单次最长 60 秒", systemImage: "keyboard")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20).writingSurface()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions }
                VStack(alignment: .leading, spacing: 12) { actions }
            }
            WorkspaceForm {
                Section("遇到问题") {
                    DisclosureGroup("第一次使用，要准备什么？") {
                        Text("允许麦克风并下载识别模型。自动写入还需要辅助功能权限和可用的快捷键，可通过上方“首次准备”逐项完成。")
                            .helpText()
                    }
                    DisclosureGroup("文字没有写入怎么办？") {
                        Text("打开工作台查看结果和提示。先点选目标输入框，确认没有重复文字后再重新粘贴；也可复制结果。已写入的文字需在目标应用中撤销。")
                            .helpText()
                    }
                    DisclosureGroup("可以不用快捷键吗？") {
                        Text("可以。在工作台点击录音，或导入不超过 60 秒的音频，完成后手动复制结果。")
                            .helpText()
                    }
                    DisclosureGroup("录音和历史会保存多久？") {
                        PrivacySettingsContent().helpText()
                    }
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        Button("去工作台试试", systemImage: "mic") { showDashboard() }
            .buttonStyle(VoxInkButtonStyle(prominent: true))
        Button("首次准备", systemImage: "checklist") { store.showSetup(); showDashboard() }
        SettingsLink { Label("偏好设置", systemImage: "slider.horizontal.3") }
    }

    @ViewBuilder private func steps(horizontal: Bool) -> some View {
        step("1", icon: "cursorarrow.click", title: "点选输入框", detail: "把光标放在需要文字的位置。", horizontal: horizontal)
        step("2", icon: "mic", title: "使用快捷键说话",
             detail: store.shortcutMode == .holdToTalk ? "按住录音，松开后自动识别。" : "按一次开始，再按一次结束。", horizontal: horizontal)
        step("3", icon: "text.cursor", title: "查看写入结果", detail: "文字自动写入，核对姓名与数字。", horizontal: horizontal)
    }

    private func step(_ number: String, icon: String, title: String, detail: String, horizontal: Bool) -> some View {
        let layout = horizontal ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        return layout {
            Image(systemName: icon).font(.title2).foregroundStyle(VoxInkTheme(scheme: scheme).accent)
                .frame(width: 40, height: 40)
                .background(VoxInkTheme(scheme: scheme).accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text("\(number). \(title)").font(.subheadline.weight(.semibold))
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: horizontal ? 165 : nil, maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func helpText() -> some View {
        font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
    }
}
