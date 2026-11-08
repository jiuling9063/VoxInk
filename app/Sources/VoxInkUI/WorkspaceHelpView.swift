import VoxInkCore
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceHelpView: View {
    @ObservedObject var store: AppStore
    @State private var exportMessage = ""
    let showDashboard: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(L("说话，变成文字"), systemImage: "waveform").font(.headline)
                    Spacer()
                    Text(store.shortcutCombination.title)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(VoxInkTheme(scheme: scheme).accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) { steps(horizontal: true) }
                    VStack(alignment: .leading, spacing: 14) { steps(horizontal: false) }
                }
                Divider()
                Label(L("Esc 随时取消 · 单次最长 60 秒"), systemImage: "keyboard")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { actions }
                VStack(alignment: .leading, spacing: 12) { actions }
            }
            WorkspaceForm {
                Section(L("遇到问题")) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("第一次使用，要准备什么？")).font(.subheadline.weight(.medium))
                        Text(L("允许麦克风，并选择本地模型或配置 API 连接。自动写入还需要辅助功能权限和可用的快捷键。"))
                            .helpText()
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("文字没有写入怎么办？")).font(.subheadline.weight(.medium))
                        Text(L("打开工作台查看结果和提示。先点选目标输入框，确认没有重复文字后再重新粘贴；也可复制结果。已写入的文字需在目标应用中撤销。"))
                            .helpText()
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("可以不用快捷键吗？")).font(.subheadline.weight(.medium))
                        Text(L("可以。在工作台点击录音，或导入不超过 60 秒的音频，完成后手动复制结果。"))
                            .helpText()
                    }
                    DisclosureGroup(L("录音和历史会保存多久？")) {
                        PrivacySettingsContent().helpText()
                    }
                }
            }
            Toggle(L("启动时检查更新"), isOn: Binding(get: { store.checksForUpdates }, set: { store.setChecksForUpdates($0) }))
            Button(store.availableVersion.map { L("更新到 \($0)…") } ?? L("检查更新…")) {
                store.requestUpdate()
            }.disabled(!store.canRequestUpdate)
            Button(L("导出诊断信息…")) {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.plainText]
                panel.nameFieldStringValue = "VoxInk-diagnostics.txt"
                if panel.runModal() == .OK, let url = panel.url {
                    do {
                        try store.diagnosticSummary().write(to: url, atomically: true, encoding: .utf8)
                        exportMessage = L("已导出诊断信息")
                    } catch { exportMessage = L("导出失败，请检查保存位置。") }
                }
            }
            if !exportMessage.isEmpty { Text(exportMessage).font(.caption) }
        }
    }

    @ViewBuilder private var actions: some View {
        Button(L("去工作台试试"), systemImage: "mic") { showDashboard() }
            .buttonStyle(VoxInkButtonStyle(prominent: true))
        Button(L("查看使用引导"), systemImage: "checklist") { store.showSetup(); showDashboard() }
        SettingsLink { Label(L("偏好设置"), systemImage: "slider.horizontal.3") }
    }

    @ViewBuilder private func steps(horizontal: Bool) -> some View {
        step("1", icon: "cursorarrow.click", title: L("点选输入框"), detail: L("把光标放在需要文字的位置。"), horizontal: horizontal)
        step("2", icon: "mic", title: L("使用快捷键说话"),
             detail: store.shortcutMode == .holdToTalk ? L("按住录音，松开后自动识别。") : L("按一次开始，再按一次结束。"), horizontal: horizontal)
        step("3", icon: "text.cursor", title: L("查看写入结果"), detail: L("文字自动写入，核对姓名与数字。"), horizontal: horizontal)
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
        }.frame(minWidth: horizontal ? 150 : nil, maxWidth: .infinity, alignment: .leading)
            .padding(18).writingSurface()
    }
}

private extension View {
    func helpText() -> some View {
        font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
    }
}
