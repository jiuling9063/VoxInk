import VoxInkCore
import SwiftUI

public struct PreferencesView: View {
    @Environment(\.colorScheme) private var scheme
    private var theme: VoxInkTheme { VoxInkTheme(scheme: scheme) }
    @ObservedObject private var store: AppStore
    @ObservedObject private var loginItem: LoginItemController
    private let showGuide: () -> Void
    @State private var tab = 0

    public init(store: AppStore, loginItem: LoginItemController, showGuide: @escaping () -> Void) {
        self.store = store
        self.loginItem = loginItem
        self.showGuide = showGuide
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                WorkspaceHeading(title: L("偏好设置"), subtitle: L("让语落贴合你的表达习惯。"))
                Spacer()
                Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(theme.accent)
                    .frame(width: 48, height: 48)
                    .background(theme.ceramicGradient, in: RoundedRectangle(cornerRadius: 14))
                    .overlay { RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.16), lineWidth: 1) }
                    .accessibilityHidden(true)
            }
            WorkspacePicker(L("设置分类"), value: [0: L("通用"), 1: L("系统权限"), 2: L("用户词典"), 3: L("识别与润色")][tab] ?? L("通用"), selection: $tab, options: [(L("通用"), 0), (L("系统权限"), 1), (L("识别与润色"), 3)] + (store.dictionary == nil ? [] : [(L("用户词典"), 2)]))
            ScrollView {
            Group {
            if tab == 0 {
            WorkspaceForm {
                Section(L("启动")) {
                    Toggle(L("登录时启动语落"), isOn: Binding(
                        get: { loginItem.state == .enabled || loginItem.state == .requiresApproval },
                        set: { enabled in Task { await loginItem.setEnabled(enabled) } }
                    )).disabled(loginItem.isUpdating)
                    HStack {
                        StatusBadge(title: loginItem.state.title, tone: loginItem.state == .enabled ? .good : .quiet)
                        if loginItem.isUpdating { ProgressView().controlSize(.mini) }
                        Spacer()
                        if loginItem.state == .requiresApproval || loginItem.errorMessage != nil {
                            Button(L("打开登录项设置")) { loginItem.openSettings() }
                        }
                    }
                    if let error = loginItem.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                }
                Section(L("语言")) { LanguageSettingsContent(store: store) }
                Section(L("语音输入")) { InputSettingsContent(store: store) }
                Section(L("文字处理")) { TextProcessingContent(store: store) }
                Section(L("隐私与帮助")) {
                    PrivacySettingsContent()
                    Button(L("查看使用引导")) { store.showSetup(); showGuide() }
                }
            }
            } else if tab == 1 {
            WorkspaceForm {
                Section(L("系统权限")) { PermissionSettingsContent(store: store) }
            }
            } else if tab == 3 {
                ModelSettingsCards(store: store)
            } else if let dictionary = store.dictionary {
                DictionaryPreferencesView(controller: dictionary, canEdit: store.canStart)
            }
            }.id(tab)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24).frame(width: 620, height: 660)
        .background(theme.background).tint(theme.accent)
        .buttonStyle(VoxInkButtonStyle())
        .onAppear { store.refreshPermissions(); loginItem.refresh() }
    }
}

struct StatusBadge: View {
    enum Tone { case good, warning, quiet }
    let title: String
    let tone: Tone
    @Environment(\.colorScheme) private var scheme

    private var color: Color {
        switch tone {
        case .good: VoxInkTheme(scheme: scheme).accent
        case .warning: VoxInkTheme(scheme: scheme).caution
        case .quiet: .secondary
        }
    }

    var body: some View {
        Text(title).font(.caption).foregroundStyle(color)
    }
}
