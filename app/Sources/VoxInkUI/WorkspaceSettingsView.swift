import SwiftUI
import VoxInkCore

enum WorkspacePage: String {
    case input, history, statistics, result, engine, shortcut, postprocess, polish, help

    var title: String {
        switch self {
        case .input: "语音工作台"
        case .history: "转录历史"
        case .statistics: "统计"
        case .result: "本次结果"
        case .engine: "转录引擎"
        case .shortcut: "快捷键与输入"
        case .postprocess: "文字与词典"
        case .polish: "润色模型"
        case .help: "使用方法"
        }
    }
}

struct WorkspaceSettingsView: View {
    @ObservedObject var store: AppStore
    let page: WorkspacePage
    let showDashboard: () -> Void

    private var subtitle: String {
        switch page {
        case .engine: "管理本地识别模型与系统权限。"
        case .shortcut: "选择顺手的快捷键，让文字落在需要的地方。"
        case .postprocess: "整理文字，记住姓名与专有词的正确写法。"
        case .polish: "在本机整理表达，始终保留识别原文。"
        case .help: "从第一句话开始，了解语落的使用方式。"
        default: ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkspaceHeading(title: page.title, subtitle: subtitle)
            switch page {
            case .engine:
                Form {
                    Section("语音识别") { ModelSettingsContent(store: store) }
                    Section("麦克风与文字写入") { PermissionSettingsContent(store: store) }
                }.formStyle(.grouped)
            case .shortcut:
                Form {
                    Section("语音输入") { InputSettingsContent(store: store) }
                    Section("系统权限") { PermissionSettingsContent(store: store) }
                }.formStyle(.grouped)
            case .postprocess:
                VStack(alignment: .leading, spacing: 8) { TextProcessingContent() }
                    .padding(16).writingSurface()
                if let dictionary = store.dictionary {
                    DictionaryPreferencesView(controller: dictionary, canEdit: store.canStart)
                } else {
                    Text("用户词典暂不可用，请重新打开语落后再试。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            case .polish:
                Form {
                    Section("可选本地润色") { PolishSettingsContent(store: store) }
                    Section("自动处理") {
                        Text("开启后，松开快捷键会先识别、再润色，最后只写入一次。未开启时直接写入识别文字，无需手动点击。识别原文始终保留，可在结果中查看。")
                        Text("模型按需下载，润色时不联网。组件缺失、超时或结果未通过检查时，自动使用未润色文字。切换档位不会自动开启润色。")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("返回工作台") { showDashboard() }
                    }
                }.formStyle(.grouped)
            case .help:
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("1. 完成准备").font(.headline)
                        Text("允许麦克风并下载识别模型。自动写入还需要辅助功能权限和可用的快捷键。")
                        Text("2. 开始说话").font(.headline)
                        Text(store.shortcutInstruction)
                        Text("先点选目标输入框，再使用快捷键。也可在工作台点击录音，完成后手动复制。单次最长 60 秒。")
                        Text("3. 检查结果").font(.headline)
                        Text("识别后核对姓名、数字和专有词。写入失败时打开工作台查看原因；再次粘贴前先确认目标中没有重复文字。已写入的文字需在目标应用中撤销。")
                        Text("隐私与保留").font(.headline)
                        PrivacySettingsContent()
                        Button("查看首次准备") { store.showSetup(); showDashboard() }
                        SettingsLink { Label("打开偏好设置", systemImage: "slider.horizontal.3") }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20).writingSurface()
                }
            case .input, .history, .statistics, .result:
                EmptyView()
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: 920, maxHeight: .infinity, alignment: .topLeading)
        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { store.refreshPermissions() }
    }
}

struct InputSettingsContent: View {
    @ObservedObject var store: AppStore
    var body: some View {
        Picker("快捷键", selection: Binding(get: { store.shortcutCombination }, set: { store.setShortcutCombination($0) })) {
            ForEach(ShortcutCombination.allCases, id: \.self) { Text($0.title).tag($0) }
        }.disabled(!store.canChangeShortcut)
        Text(store.shortcutStatus).font(.caption).foregroundStyle(.secondary)
        Picker("操作方式", selection: Binding(get: { store.shortcutMode }, set: { store.setShortcutMode($0) })) {
            ForEach(ShortcutMode.allCases, id: \.self) { Text($0.title).tag($0) }
        }.disabled(!store.canChangeShortcut)
        Text(store.shortcutInstruction).font(.callout).foregroundStyle(.secondary)
        LabeledContent("单次录音", value: "最长 60 秒 · Esc 取消")
        DisclosureGroup("远程输入（UU）") {
            TextField("UU Mac 设备名称", text: Binding(get: { store.uuMacDevices }, set: { store.setUUDevices(mac: $0, windows: store.uuWindowsDevices) }))
                .disabled(!store.canStart)
            TextField("UU Windows 设备名称", text: Binding(get: { store.uuWindowsDevices }, set: { store.setUUDevices(mac: store.uuMacDevices, windows: $0) }))
                .disabled(!store.canStart)
            Text("填写 UU 窗口显示的完整设备名，多个名称用逗号分隔。窗口模式下自动匹配：Mac 用 Command+V，Windows 用 Ctrl+V。")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("未识别设备时使用 Windows 粘贴", isOn: Binding(get: { store.uuWindowsPaste }, set: { store.setUUWindowsPaste($0) }))
                .disabled(!store.canStart)
            Text("全屏、设备名未填写或名称重复时可能无法识别，届时使用此手动选择：打开为 Windows，关闭为 Mac。已匹配设备不受此开关影响。")
                .font(.caption).foregroundStyle(.secondary)
            Picker("UU 远程同步等待", selection: Binding(get: { store.remotePasteTiming }, set: { store.setRemotePasteTiming($0) })) {
                ForEach(RemotePasteTiming.allCases, id: \.self) { Text($0.title).tag($0) }
            }.disabled(!store.canStart)
            Text("仅用于 UU 远程。建议先用稳定档；较快档需在远端试用，若出现旧文字或未写入，请切回稳定。粘贴发出后会在后台恢复剪贴板。")
                .font(.caption).foregroundStyle(.secondary)
            if !store.clipboardCleanupWarning.isEmpty {
                Text(store.clipboardCleanupWarning).foregroundStyle(.orange)
            }
        }
    }
}

struct TextProcessingContent: View {
    var body: some View {
        LabeledContent("输出文字", value: "简体中文 · 英文保留原样")
        Text("自动整理异常空格与明显重复标点，清理句首的“呃，”；数字、网址、路径和代码保持原样。结果下方可查看识别原文。")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct PolishSettingsContent: View {
    @ObservedObject var store: AppStore
    var body: some View {
        Toggle("自动润色后写入", isOn: Binding(get: { store.polishingEnabled }, set: { store.setPolishingEnabled($0) }))
            .disabled(!store.canStart || store.isInstallingPolishModel)
        Picker("模型选择", selection: Binding(get: { store.automaticPolishModel ? "auto" : store.polishModel.rawValue }, set: {
            if $0 == "auto" { store.setAutomaticPolishModel(true) }
            else if let model = PolishModel(rawValue: $0) { store.setPolishModel(model) }
        })) {
            Text("自动（推荐）").tag("auto")
            ForEach(PolishModel.allCases, id: \.self) { model in
                Text(model.title).tag(model.rawValue)
            }
        }.disabled(!store.canStart || store.isInstallingPolishModel)
        Picker("使用偏好", selection: Binding(get: { store.polishPreference }, set: { store.setPolishPreference($0) })) {
            ForEach(PolishPreference.allCases, id: \.self) { Text($0.title).tag($0) }
        }.disabled(!store.canStart || store.isInstallingPolishModel)
        Text(store.polishDevice.summary).font(.caption).foregroundStyle(.secondary)
        Text(store.polishRecommendationText).font(.callout)
        LabeledContent("当前模型", value: store.effectivePolishModel?.modelName ?? "暂不使用")
        Text(store.polishWarmMessage).font(.caption).foregroundStyle(.secondary)
        if !store.polishPerformanceMessage.isEmpty {
            Text(store.polishPerformanceMessage).font(.caption).foregroundStyle(.secondary)
        }
        LabeledContent("下载或修复", value: store.polishDownloadTarget.title)
        Text(store.polishDownloadTarget.detail).font(.callout)
        LabeledContent("安装状态", value: store.installedPolishModels.contains(store.polishDownloadTarget) ? "已安装" : "未安装")
        if store.isInstallingPolishModel {
            HStack {
                ProgressView().controlSize(.small)
                Text(store.polishInstallationMessage).font(.callout)
                Spacer()
                Button("取消下载") { store.cancelPolishInstallation() }
            }
        } else {
            Button(store.installedPolishModels.contains(store.polishDownloadTarget) ? "检查并修复此模型" : "下载并启用") {
                store.installSelectedPolishModel(enableAfterInstall: !store.installedPolishModels.contains(store.polishDownloadTarget))
            }.disabled(!store.canStart)
        }
        if !store.isInstallingPolishModel && !store.polishInstallationMessage.isEmpty {
            Text(store.polishInstallationMessage).font(.caption).foregroundStyle(.secondary)
        }
        Text("运行组件已随 App 提供，无需安装 Python 或配置环境。上方大小为模型下载量。高档位占用更多内存、耗时更长；“最佳效果”是效果优先档，具体表现因文本和电脑而异。")
            .font(.caption).foregroundStyle(.secondary)
        Text("默认关闭。开启后先润色再写入。响应更快／兼顾／效果优先分别最多等待 6／12／30 秒，失败使用未润色文字；Esc 取消整次输入。自动模式只调整已安装模型，新模型须点击下载，不会切到云端。性能统计只保存在本机，不含输入文字。")
            .font(.caption).foregroundStyle(.secondary)
            .onAppear { store.refreshPolishModels() }
    }
}

struct PermissionSettingsContent: View {
    @ObservedObject var store: AppStore
    var body: some View {
        HStack {
            Text("麦克风")
            Spacer()
            StatusBadge(title: store.microphoneAuthorization.title,
                        tone: store.microphoneAuthorization == .authorized ? .good : .warning)
        }
        HStack {
            Text("文字写入")
            Spacer()
            StatusBadge(title: store.pastePermissionGranted ? "已允许" : "尚未允许",
                        tone: store.pastePermissionGranted ? .good : .warning)
        }
        ViewThatFits(in: .horizontal) {
            HStack { permissionButtons }
            VStack(alignment: .leading) { permissionButtons }
        }
        Text("在系统设置的「隐私与安全」中管理麦克风与辅助功能权限。返回语落时会刷新状态。")
            .font(.caption).foregroundStyle(.secondary)
        Button("刷新权限状态") { store.refreshPermissions() }
    }

    private var permissionButtons: some View {
        Group {
            Button("允许麦克风") { store.requestMicrophonePermission() }
                .disabled(!store.canStart || store.microphoneAuthorization != .notDetermined)
            Button("允许文字写入") { store.requestPastePermission() }.disabled(!store.canStart)
            Button("系统设置") { store.openSystemSettings() }
        }
    }
}

struct ModelSettingsContent: View {
    @ObservedObject var store: AppStore
    var body: some View {
        HStack {
            Text("状态")
            Spacer()
            StatusBadge(title: store.modelState.title,
                        tone: store.modelState == .ready ? .good : (store.modelState == .failed ? .warning : .quiet))
        }
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
        Button(store.modelState == .needsDownload ? "下载或继续安装" : "检查并修复模型") { store.installModel() }
            .disabled(!store.canStart)
    }
}

struct PrivacySettingsContent: View {
    var body: some View {
        Text("音频仅在本机识别。完成写入、复制或取消后删除；未完成录音最多保留一条、有效期 24 小时，可随时删除。转录历史仅保留在本次启动期间，退出 App 后清除。")
            .font(.callout).foregroundStyle(.secondary)
    }
}
