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
                VStack(alignment: .leading, spacing: 6) {
                    Text("偏好设置").font(.system(size: 26, weight: .bold))
                    Text("让语落贴合你的表达习惯。").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(theme.accent)
                    .frame(width: 48, height: 48)
                    .background(theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }.padding(.horizontal, 8)
            Picker("设置分类", selection: $tab) {
                Text("通用").tag(0)
                Text("权限与模型").tag(1)
                if store.dictionary != nil { Text("用户词典").tag(2) }
            }.pickerStyle(.segmented).labelsHidden()
            Group {
            if tab == 0 {
            Form {
                Section("启动") {
                    Toggle("登录时启动语落", isOn: Binding(
                        get: { loginItem.state == .enabled || loginItem.state == .requiresApproval },
                        set: { enabled in Task { await loginItem.setEnabled(enabled) } }
                    )).disabled(loginItem.isUpdating)
                    HStack {
                        Text(loginItem.state.title).font(.caption).foregroundStyle(.secondary)
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
                Section("语音输入") {
                    Picker("快捷键", selection: Binding(get: { store.shortcutCombination }, set: { store.setShortcutCombination($0) })) {
                        ForEach(ShortcutCombination.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.disabled(!store.canChangeShortcut)
                    Text(store.shortcutStatus).font(.caption).foregroundStyle(.secondary)
                    Picker("操作方式", selection: Binding(get: { store.shortcutMode }, set: { store.setShortcutMode($0) })) {
                        ForEach(ShortcutMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.disabled(!store.canChangeShortcut)
                    Text(store.shortcutInstruction).font(.callout).foregroundStyle(.secondary)
                    LabeledContent("输出文字", value: "简体中文 · 英文保留原样")
                    Text("自动整理异常空格与明显重复标点，清理句首的“呃，”；数字、网址、路径和代码保持原样。结果下方可查看识别原文。")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("单次录音", value: "最长 60 秒 · Esc 取消")
                }
                Section("文字润色") {
                    Toggle("启用轻度润色预览", isOn: Binding(get: { store.polishingEnabled }, set: { store.setPolishingEnabled($0) }))
                    Text("默认关闭。需要安装本地润色模型。手动生成预览，最长等待 30 秒；可取消，不自动替换写入文字。润色可能改变含义，请核对原文。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("隐私与帮助") {
                    Text("音频仅在本机识别。完成写入、复制或取消后删除；未完成录音最多保留一条、有效期 24 小时，可随时删除。转录历史仅保留在本次启动期间，退出 App 后清除。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("查看使用引导") { store.showSetup(); showGuide() }
                }
            }.formStyle(.grouped)
            } else if tab == 1 {
            Form {
                Section("系统权限") {
                    LabeledContent("麦克风", value: store.microphoneAuthorization.title)
                    LabeledContent("文字写入", value: store.pastePermissionGranted ? "已允许" : "尚未允许")
                    HStack {
                        Button("允许麦克风") { store.requestMicrophonePermission() }
                            .disabled(!store.canStart || store.microphoneAuthorization != .notDetermined)
                        Button("允许文字写入") { store.requestPastePermission() }.disabled(!store.canStart)
                        Button("系统设置") { store.openSystemSettings() }
                    }
                    Text("在系统设置的「隐私与安全」中管理麦克风与辅助功能权限。返回语落时会刷新状态。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("本地模型") {
                    LabeledContent("状态", value: store.modelState.title)
                    Text("当前预览使用 Qwen 本地模型。首次下载约 713 MB；中断可继续，完成后校验文件。识别过程无需联网。")
                        .font(.callout).foregroundStyle(.secondary)
                    if let progress = store.modelInstallationProgress {
                        ProgressView(progress.title, value: progress.fraction)
                    }
                    if store.recovery == .installModel || store.recovery == .reloadModel || store.recovery == .checkInstallation {
                        Text(store.status).font(.caption).foregroundStyle(.orange)
                    }
                    if store.modelState == .loading && store.canCancel {
                        Button("取消准备") { Task { await store.cancel() } }
                    }
                    Button(store.modelState == .needsDownload ? "下载或继续安装" : "检查并修复模型") { store.installModel() }.disabled(!store.canStart)
                }
                Button("刷新权限状态") { store.refreshPermissions() }
            }.formStyle(.grouped)
            } else if let dictionary = store.dictionary {
                DictionaryPreferencesView(controller: dictionary, canEdit: store.canStart)
            }
            }.scrollContentBackground(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .writingSurface()
        }
        .padding(24).frame(width: 620, height: 660)
        .background(theme.background).tint(theme.accent)
        .buttonStyle(VoxInkButtonStyle())
        .onAppear { store.refreshPermissions(); loginItem.refresh() }
    }
}
