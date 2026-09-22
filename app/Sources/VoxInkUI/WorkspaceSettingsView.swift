import SwiftUI
import VoxInkCore

enum WorkspacePage: String {
    case input, history, statistics, result, engine, shortcut, postprocess, polish, help

    var title: String {
        switch self {
        case .input: L("语音工作台")
        case .history: L("转录历史")
        case .statistics: L("统计")
        case .result: L("本次结果")
        case .engine: L("转录引擎")
        case .shortcut: L("快捷键与输入")
        case .postprocess: L("文字与词典")
        case .polish: L("润色模型")
        case .help: L("使用方法")
        }
    }
}

struct WorkspaceSettingsView: View {
    @ObservedObject var store: AppStore
    let page: WorkspacePage
    let showDashboard: () -> Void

    private var subtitle: String {
        switch page {
        case .engine: L("管理本地识别模型与系统权限。")
        case .shortcut: L("选择顺手的快捷键，让文字落在需要的地方。")
        case .postprocess: L("整理文字，记住姓名与专有词的正确写法。")
        case .polish: L("在本机整理表达，始终保留识别原文。")
        case .help: L("从第一句话开始，了解语落的使用方式。")
        default: ""
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WorkspaceHeading(title: page.title, subtitle: subtitle)
                switch page {
                case .engine:
                    WorkspaceForm {
                        Section(L("语音识别")) { ModelSettingsContent(store: store) }
                        Section(L("麦克风与文字写入")) { PermissionSettingsContent(store: store) }
                    }
                case .shortcut:
                    WorkspaceForm {
                        Section(L("语音输入")) { InputSettingsContent(store: store) }
                        Section(L("系统权限")) { PermissionSettingsContent(store: store) }
                    }
                case .postprocess:
                    WorkspaceForm { Section(L("语言")) { LanguageSettingsContent(store: store) } }
                    VStack(alignment: .leading, spacing: 8) { TextProcessingContent(store: store) }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(18).writingSurface()
                    if let dictionary = store.dictionary {
                        DictionaryPreferencesView(controller: dictionary, canEdit: store.canStart)
                    } else {
                        Text(L("用户词典暂不可用，请重新打开语落后再试。"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                case .polish:
                    WorkspaceForm {
                        Section(L("可选本地润色")) { PolishSettingsContent(store: store) }
                    }
                case .help:
                    WorkspaceHelpView(store: store, showDashboard: showDashboard)
                case .input, .history, .statistics, .result:
                    EmptyView()
                }
            }
            .workspacePageMargins()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { store.refreshPermissions() }
    }
}

struct InputSettingsContent: View {
    @ObservedObject var store: AppStore
    var body: some View {
        ShortcutSettingsControl(store: store)
        WorkspacePicker(L("操作方式"), selection: Binding(get: { store.shortcutMode }, set: { store.setShortcutMode($0) })) {
            ForEach(ShortcutMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }.disabled(!store.canChangeShortcut)
        Text(store.shortcutInstruction).font(.callout).foregroundStyle(.secondary)
        LabeledContent(L("单次录音"), value: L("最长 60 秒 · Esc 取消"))
        RemoteInputSettingsView(store: store)
    }
}

struct TextProcessingContent: View {
    @ObservedObject var store: AppStore
    var body: some View {
        LabeledContent(L("中文输出"), value: store.chineseOutput.title)
        Text(L("中文按所选字形整理，其他语言保留原样。数字、网址、路径和代码保持原样；结果下方可查看识别原文。"))
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct PolishSettingsContent: View {
    @ObservedObject var store: AppStore
    private var installed: Bool { store.installedPolishModels.contains(store.polishDownloadTarget) }
    var body: some View {
        Toggle(L("自动润色后写入"), isOn: Binding(get: { store.polishingEnabled }, set: { store.setPolishingEnabled($0) }))
            .disabled(!store.canStart || store.isInstallingPolishModel)
        WorkspacePicker(L("模型选择"), selection: Binding(get: { store.automaticPolishModel ? "auto" : store.polishModel.rawValue }, set: {
            if $0 == "auto" { store.setAutomaticPolishModel(true) }
            else if let model = PolishModel(rawValue: $0) { store.setPolishModel(model) }
        })) {
            Text(L("自动（推荐）")).tag("auto")
            ForEach(PolishModel.allCases, id: \.self) { model in
                Text(model.title).tag(model.rawValue)
            }
        }.disabled(!store.canStart || store.isInstallingPolishModel)
        WorkspacePicker(L("使用偏好"), selection: Binding(get: { store.polishPreference }, set: { store.setPolishPreference($0) })) {
            ForEach(PolishPreference.allCases, id: \.self) { Text($0.title).tag($0) }
        }.disabled(!store.canStart || store.isInstallingPolishModel)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.polishDownloadTarget.title).font(.headline)
                    Text(store.polishDownloadTarget.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                StatusBadge(title: installed ? L("已安装") : L("未下载"), tone: installed ? .good : .quiet)
            }
            if store.isInstallingPolishModel {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(store.polishInstallationMessage).font(.callout)
                    Spacer()
                    Button(L("取消")) { store.cancelPolishInstallation() }
                }
            } else {
                HStack {
                    if installed {
                        Text(L("当前使用：\(store.effectivePolishModel?.title ?? L("暂不可用"))"))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(L("首次下载后即可使用")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(installed ? L("检查与修复") : L("下载并启用")) {
                        store.installSelectedPolishModel(enableAfterInstall: !installed)
                    }.disabled(!store.canStart)
                }
            }
            if !store.isInstallingPolishModel && !store.polishInstallationMessage.isEmpty {
                Text(store.polishInstallationMessage).font(.caption).foregroundStyle(.secondary)
            }
        }.onAppear { store.refreshPolishModels() }
        Text(L("在本机整理表达，失败时保留原文。"))
            .font(.caption).foregroundStyle(.secondary)
        DisclosureGroup(L("模型与运行详情")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.polishDevice.summary)
                Text(store.polishRecommendationText)
                LabeledContent(L("完整模型名称"), value: store.polishDownloadTarget.modelName)
                Text(store.polishWarmMessage)
                if !store.polishPerformanceMessage.isEmpty { Text(store.polishPerformanceMessage) }
            }.font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }
        DisclosureGroup(L("使用说明")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("开启后先识别、再润色，最后写入一次。识别原文始终保留；Esc 取消整次输入。"))
                Text(L("运行组件已内置，无需配置。模型按需下载，下载完成后可离线使用；高档位需要更多内存和等待时间。"))
                Text(L("自动模式只选择已安装的模型。响应更快、兼顾、效果优先分别最多等待 6、12、30 秒；超时或结果不合格时使用未润色文字。"))
                Text(L("运行耗时只保存在本机，不包含输入文字。"))
            }.font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }

    }
}

struct PermissionSettingsContent: View {
    @ObservedObject var store: AppStore
    var body: some View {
        HStack {
            Text(L("麦克风"))
            Spacer()
            StatusBadge(title: store.microphoneAuthorization.title,
                        tone: store.microphoneAuthorization == .authorized ? .good : .warning)
        }
        HStack {
            Text(L("文字写入"))
            Spacer()
            StatusBadge(title: store.pastePermissionGranted ? L("已允许") : L("尚未允许"),
                        tone: store.pastePermissionGranted ? .good : .warning)
        }
        ViewThatFits(in: .horizontal) {
            HStack { permissionButtons }
            VStack(alignment: .leading) { permissionButtons }
        }
        DisclosureGroup(L("权限说明")) {
            Text(L("麦克风用于录音，辅助功能用于写入文字。在系统设置的“隐私与安全”中管理；返回语落后会自动刷新。"))
                .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
        }
        Button(L("刷新权限状态")) { store.refreshPermissions() }
    }

    private var permissionButtons: some View {
        Group {
            Button(L("允许麦克风")) { store.requestMicrophonePermission() }
                .disabled(!store.canStart || store.microphoneAuthorization != .notDetermined)
            Button(L("允许文字写入")) { store.requestPastePermission() }.disabled(!store.canStart)
            Button(L("系统设置")) { store.openSystemSettings() }
        }
    }
}

struct ModelSettingsContent: View {
    @ObservedObject var store: AppStore
    var body: some View {
        HStack {
            Text(L("状态"))
            Spacer()
            StatusBadge(title: store.modelState.title,
                        tone: store.modelState == .ready ? .good : (store.modelState == .failed ? .warning : .quiet))
        }
        Text(L("识别在本机完成。首次下载约 713 MB，支持中断后继续。"))
            .font(.callout).foregroundStyle(.secondary)
        if let progress = store.modelInstallationProgress {
            ProgressView(progress.title, value: progress.fraction)
        }
        if store.recovery == .installModel || store.recovery == .reloadModel || store.recovery == .checkInstallation {
            Text(store.status).font(.caption).foregroundStyle(.orange)
        }
        if store.modelState == .loading && store.canCancel {
            Button(L("取消准备")) { Task { await store.cancel() } }
        }
        Button(store.modelState == .needsDownload ? L("下载或继续安装") : L("检查并修复模型")) { store.installModel() }
            .disabled(!store.canStart)
    }
}

struct PrivacySettingsContent: View {
    var body: some View {
        Text(L("音频仅在本机识别。完成写入、复制或取消后删除；未完成录音最多保留一条、有效期 24 小时，可随时删除。转录历史仅保留在本次启动期间，退出 App 后清除。"))
            .font(.callout).foregroundStyle(.secondary)
    }
}
