import SwiftUI

public struct PreferencesView: View {
    @Environment(\.colorScheme) private var scheme
    private var theme: VoxInkTheme { VoxInkTheme(scheme: scheme) }
    @ObservedObject private var store: AppStore
    @ObservedObject private var loginItem: LoginItemController
    private let showGuide: () -> Void
    @State private var tab = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: AppStore, loginItem: LoginItemController, showGuide: @escaping () -> Void) {
        self.store = store
        self.loginItem = loginItem
        self.showGuide = showGuide
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                WorkspaceHeading(title: "偏好设置", subtitle: "让语落贴合你的表达习惯。")
                Spacer()
                Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(theme.accent)
                    .frame(width: 48, height: 48)
                    .background(theme.ceramicGradient, in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.16), lineWidth: 1) }
                    .accessibilityHidden(true)
            }.padding(.horizontal, 8)
            Picker("设置分类", selection: $tab) {
                Text("通用").tag(0)
                Text("权限与模型").tag(1)
                if store.dictionary != nil { Text("用户词典").tag(2) }
            }.pickerStyle(.segmented).labelsHidden()
            ReadinessSummary(store: store)
            Group {
            if tab == 0 {
            Form {
                Section("启动") {
                    Toggle("登录时启动语落", isOn: Binding(
                        get: { loginItem.state == .enabled || loginItem.state == .requiresApproval },
                        set: { enabled in Task { await loginItem.setEnabled(enabled) } }
                    )).disabled(loginItem.isUpdating)
                    HStack {
                        StatusBadge(title: loginItem.state.title, tone: loginItem.state == .enabled ? .good : .quiet)
                        if loginItem.isUpdating { ProgressView().controlSize(.mini) }
                        Spacer()
                        if loginItem.state == .requiresApproval || loginItem.errorMessage != nil {
                            Button("打开登录项设置") { loginItem.openSettings() }
                        }
                    }
                    if let error = loginItem.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                }
                Section("语音输入") { InputSettingsContent(store: store) }
                Section("文字处理") { TextProcessingContent() }
                Section("文字润色") { PolishSettingsContent(store: store) }
                Section("隐私与帮助") {
                    PrivacySettingsContent()
                    Button("查看使用引导") { store.showSetup(); showGuide() }
                }
            }.formStyle(.grouped)
            } else if tab == 1 {
            Form {
                Section("系统权限") { PermissionSettingsContent(store: store) }
                Section("本地模型") { ModelSettingsContent(store: store) }
            }.formStyle(.grouped)
            } else if let dictionary = store.dictionary {
                DictionaryPreferencesView(controller: dictionary, canEdit: store.canStart)
            }
            }.id(tab).transition(.opacity).scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ceramicSurface()
        }
        .padding(24).frame(width: 620, height: 660)
        .background(theme.background).tint(theme.accent)
        .buttonStyle(VoxInkButtonStyle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: tab)
        .onAppear { store.refreshPermissions(); loginItem.refresh() }
    }
}

private struct ReadinessSummary: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var scheme

    private var ready: Bool {
        store.canCompleteSetup
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill((ready ? Color.green : Color.orange).opacity(0.12)).frame(width: 38, height: 38)
                Circle().fill(ready ? Color.green : Color.orange).frame(width: 8, height: 8)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(ready ? "语落已准备好" : (store.canStart ? "尚未完成准备" : "语落正在处理"))
                    .font(.subheadline.weight(.semibold))
                Text(ready ? "模型、权限和快捷键均已就绪" : (store.canStart ? "请检查权限、模型与快捷键状态" : "当前任务结束后可继续使用"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            StatusBadge(title: ready ? "已就绪" : (store.canStart ? "待处理" : "处理中"), tone: ready ? .good : .warning)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .writingSurface()
    }
}

struct StatusBadge: View {
    enum Tone { case good, warning, quiet }
    let title: String
    let tone: Tone

    private var color: Color {
        switch tone {
        case .good: .green
        case .warning: .orange
        case .quiet: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption.weight(.medium)).foregroundStyle(color)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(color.opacity(0.1), in: Capsule())
    }
}
