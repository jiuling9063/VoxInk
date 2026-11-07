import VoxInkCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @Environment(\.colorScheme) private var scheme
    private var theme: VoxInkTheme { VoxInkTheme(scheme: scheme) }
    @ObservedObject private var store: AppStore
    @State private var preview: SessionTranscript?
    @State private var importing = false
    @State private var showingOriginal = false
    @StateObject private var navigation: WorkspaceNavigation
    private var page: WorkspacePage {
        get { navigation.page }
        nonmutating set { navigation.page = newValue }
    }

    public init(store: AppStore) {
        self.store = store
        _navigation = StateObject(wrappedValue: WorkspaceNavigation())
    }

    init(store: AppStore, navigation: WorkspaceNavigation) {
        self.store = store
        _navigation = StateObject(wrappedValue: navigation)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroll in
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                    ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        sidebarSection(L("工作空间"), top: 0)
                        navigation(L("工作台"), icon: "rectangle.grid.2x2", destination: .input)
                        navigation(L("历史"), icon: "clock", destination: .history)
                        sidebarSection(L("设置"), top: 22)
                        navigation(L("识别与润色"), icon: "waveform", destination: .engine, alsoSelectedOn: [.polish])
                        navigation(L("输入与远程"), icon: "command", destination: .shortcut)
                        navigation(L("文字与词典"), icon: "text.badge.checkmark", destination: .postprocess)
                    }.buttonStyle(.plain).padding(12).padding(.top, 18)
                    }.scrollIndicators(.hidden)
                    sidebarFooter
                    }.frame(width: 192).workspaceChrome()
                    Divider()
                switch page {
                case .engine, .shortcut, .postprocess, .polish, .help:
                    WorkspaceSettingsView(store: store, page: page) { page = .input }.id(page)
                case .input, .history, .result:
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if page == .history {
                            SessionHistoryView(store: store, statistics: $navigation.statistics)
                        } else if page == .result {
                            WorkspaceHeading(title: L("本次结果"), subtitle: "")
                            result.padding(22).writingSurface()
                        } else {
                        if store.isShowingSetup { SetupView(store: store).id("setup") }
                        else {
                            WorkspaceHeading(title: L("语音工作台"), subtitle: "")
                            statusHero
                        }
                        if store.isShowingSetup && store.setupProgress.step == .speech { recordingControls.padding(22).writingSurface().id("activity") }
                        retainedRecording
                        if !store.isShowingSetup || store.setupProgress.step == .speech || !store.transcript.isEmpty {
                            result.padding(22).writingSurface().id("result")
                        }
                        if !store.isShowingSetup { recentHistory }
                        #if DEBUG
                        if !store.isShowingSetup { diagnostics }
                        #endif
                        }
                    }.workspacePageMargins()
                }
                .id(page)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if page == .input && store.isShowingSetup { SetupNavigationView(store: store) }
                }
                .onChange(of: store.setupProgress.step) { _, _ in
                    if store.isShowingSetup { scroll.scrollTo("setup", anchor: .top) }
                }
                .onChange(of: store.transcript) { _, text in
                    showingOriginal = false
                    if !text.isEmpty { scroll.scrollTo(store.isShowingSetup ? "setup" : "activity", anchor: .top) }
                }
                .onChange(of: store.retainedAudio?.id) { _, id in
                    if id != nil { scroll.scrollTo("activity", anchor: .top) }
                }
                }
                }
            }
        }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "voxink" else { return }
            navigation.open(url.pathComponents.last(where: { $0 != "/" }) ?? url.host ?? "")
        }
        .onChange(of: store.sessionHistory.first?.id) { preview = nil }
        .tint(theme.accent)
        .buttonStyle(VoxInkButtonStyle())
        .background(theme.background)
        .frame(minWidth: 620, minHeight: 520)
        .onChange(of: store.phase) { _, phase in
            if phase == .failed { page = .input }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { store.importAudio(url) }
        }
    }

    private func sidebarSection(_ title: String, top: CGFloat) -> some View {
        Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.top, top).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private var appVersion: String {
        "VoxInk \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("开发版"))"
    }

    /// Setup progress (until finished), help and version — kept small and out of the main navigation.
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.setupCompleted { setupCard }
            HStack(spacing: 8) {
                Button { page = .help } label: {
                    Label(L("使用方法"), systemImage: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(page == .help ? theme.accent : Color.secondary)
                .accessibilityAddTraits(page == .help ? .isSelected : [])
                Spacer(minLength: 4)
                Text(appVersion).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .font(.system(size: 11))
            .padding(.horizontal, 4)
        }
        .padding(12)
    }

    private var setupCard: some View {
        let steps = store.setupProgress.steps
        let index = (steps.firstIndex(of: store.setupProgress.step) ?? 0) + 1
        return Button { store.showSetup(); page = .input } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(L("首次准备"), systemImage: "checklist").font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 4)
                    Text("\(index)/\(steps.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(index - 1), total: Double(max(steps.count, 1)))
                    .progressViewStyle(.linear).tint(theme.accent)
                Text(store.setupProgress.step.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: VoxInkTheme.Radius.icon))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func navigation(_ title: String, icon: String, destination: WorkspacePage,
                            alsoSelectedOn: [WorkspacePage] = []) -> some View {
        let selected = page == destination || alsoSelectedOn.contains(page)
        return Button {
            page = destination
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 8)
                .foregroundStyle(selected ? theme.accent : theme.ink.opacity(0.7))
                .background(selected ? theme.accent.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: VoxInkTheme.Radius.icon))
                .contentShape(Rectangle())
        }.accessibilityAddTraits(selected ? .isSelected : [])
            .help(title)
    }

    /// Keycap guidance, the trial controls and the input pipeline: the one place that shows readiness.
    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 18) {
            dailyInstruction
            recordingControls
            InputPipelineView(store: store) { page = $0 }
        }.padding(22)
            .background(theme.ceramicGradient, in: RoundedRectangle(cornerRadius: VoxInkTheme.Radius.card))
            .writingSurface().id("activity")
    }

    private var dailyInstruction: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) { Keycap(title: store.shortcutCombination.title); instructionTitle }
                VStack(alignment: .leading, spacing: 8) { Keycap(title: store.shortcutCombination.title); instructionTitle }
            }
            Text(L("先点选输入框，再使用 \(store.shortcutCombination.title)。识别完成后，文字会自动写入。"))
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        }
    }

    private var instructionTitle: some View {
        Text(store.shortcutMode == .holdToTalk ? L("按住说话，松开写入。") : L("按一下说话，再按一下写入。"))
            .font(.system(size: 20, weight: .semibold)).tracking(-0.3).foregroundStyle(theme.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                if !store.canStart && store.phase != .recording { ProgressView().controlSize(.small) }
                else {
                    Image(systemName: store.phase == .failed ? "exclamationmark.circle" : "waveform")
                        .foregroundStyle(store.phase == .failed ? theme.caution : theme.accent)
                }
                Text(store.status).accessibilityIdentifier("dictationStatus")
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if store.phase == .recording { Text(L("\(Int(store.elapsed)) / 60 秒")).monospacedDigit() }
            }
            if store.phase == .recording { ProgressView(value: Double(store.level)).tint(theme.accent) }
            if let recovery = store.recovery {
                Text(recovery.guidance).font(.callout).foregroundStyle(.secondary)
                recoveryButton(recovery)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { recordingButtons }
                VStack(alignment: .leading, spacing: 10) { recordingButtons }
            }
            Text(L("窗口内试录与导入只展示结果；使用快捷键录音才会自动写入目标应用。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var recordingButtons: some View {
        Button(store.phase == .recording ? L("停止并识别") : L("开始录音"),
            systemImage: store.phase == .recording ? "stop.fill" : "mic.fill") {
            if store.phase == .recording { store.finishRecording() } else { store.beginRecording() }
        }.buttonStyle(VoxInkButtonStyle(prominent: true)).disabled(!store.canStart && store.phase != .recording)
        Button(L("导入音频…"), systemImage: "doc.badge.plus") { importing = true }.disabled(!store.canStart)
        if store.canCancel { Button(L("取消")) { Task { await store.cancel() } } }
    }

    @ViewBuilder private func recoveryButton(_ recovery: RecoveryAction) -> some View {
        switch recovery {
        case .installModel: Button(L("下载或继续安装")) { store.installModel() }.disabled(!store.canStart)
        case .reloadModel: Button(L("重新加载模型")) { store.warmUp() }.disabled(!store.canStart)
        case .microphone: Button(L("打开系统设置")) { store.openSystemSettings() }
        case .pastePermission: Button(L("允许文字写入")) { store.requestPastePermission() }.disabled(!store.canStart)
        case .chooseAudio: Button(L("选择音频…")) { importing = true }.disabled(!store.canStart)
        case .recordAgain, .checkTarget, .inspectClipboard, .checkInstallation, .configureService: EmptyView()
        }
    }

    @ViewBuilder private var retainedRecording: some View {
        if let record = store.retainedAudio {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("有一条未完成录音"), systemImage: "waveform.badge.exclamationmark")
                    .font(.headline)
                Text(L("保留至 \(record.expiresAt.formatted(date: .abbreviated, time: .shortened))。重试只展示文字，不会自动写入。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L("重试识别")) { store.retryRetainedAudio() }.disabled(!store.canRetryAudio)
                    Button(L("删除保留录音"), role: .destructive) { store.deleteRetainedAudio() }
                        .disabled(!store.canStart)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .writingSurface()
        }
        if let warning = store.recoveryStorageWarning {
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(theme.caution)
        }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 12) {
            if preview == nil, let warning = store.conversionWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(theme.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { resultTitle; Spacer(minLength: 8); resultControls }
                VStack(alignment: .leading, spacing: 10) { resultTitle; HStack(spacing: 10) { resultControls } }
            }
            if preview == nil && store.transcript.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "text.alignleft").foregroundStyle(.tertiary).accessibilityHidden(true)
                    Text(L("按 \(store.shortcutCombination.title) 说一句话，文字会出现在这里。"))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            } else {
                if preview == nil && !store.polishMessage.isEmpty {
                    Text(store.polishMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text(preview?.text ?? (showingOriginal ? store.rawTranscript : store.transcript))
                    .font(.transcriptBody(size: 17)).lineSpacing(8).textSelection(.enabled)
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading).padding(.vertical, 6)
                if preview == nil && showingOriginal && store.rawTranscript == store.transcript {
                    Text(L("本次原文无需调整。")).font(.caption).foregroundStyle(.secondary)
                }
                if preview == nil && store.canPasteAgain {
                    Text(L("重新粘贴到 \(store.repasteTargetName ?? L("原目标应用"))，请先确认没有重复文字。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var resultTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L("识别结果")).font(.headline)
            if let entry = preview ?? store.sessionHistory.first, preview != nil || !store.transcript.isEmpty {
                Text(entry.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var resultControls: some View {
        if preview == nil && !store.rawTranscript.isEmpty && !store.transcript.isEmpty {
            Picker(L("本次结果"), selection: $showingOriginal) {
                Text(L("整理结果")).tag(false)
                Text(L("原文")).tag(true)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .accessibilityLabel(L("本次结果"))
        }
        if preview == nil && store.canPasteAgain {
            Button(L("重新粘贴")) { store.pasteAgain() }
                .help(L("上次写入目标：\(store.repasteTargetName ?? L("原目标应用"))"))
        }
        Button(L("复制"), systemImage: "doc.on.doc") {
            if let preview { _ = store.copyHistory(preview) } else { store.copyResult() }
        }
            .buttonStyle(VoxInkButtonStyle(prominent: true))
            .disabled((preview == nil && store.transcript.isEmpty) || !store.canStart)
            .help(L("复制结果"))
    }

    /// The last few results below the card, so the workbench doubles as a short history.
    @ViewBuilder private var recentHistory: some View {
        let recent = Array(store.sessionHistory.prefix(3))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(L("最近")).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("查看全部")) { page = .history }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(theme.accent)
                }
                .padding(.bottom, 6)
                ForEach(recent) { entry in
                    if entry.id != recent.first?.id { Divider() }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(entry.date.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.accent)
                            .frame(minWidth: 52, alignment: .leading)
                        Button { preview = entry; showingOriginal = false } label: {
                            Text(entry.text).lineLimit(1).truncationMode(.tail)
                            .foregroundStyle(theme.ink.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                        Button { _ = store.copyHistory(entry) } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                            .help(L("复制")).accessibilityLabel(L("复制"))
                            .disabled(!store.canStart)
                    }
                    .font(.callout).padding(.vertical, 8)
                    .help(entry.text)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var diagnostics: some View {
        DisclosureGroup(L("开发验证工具")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("只用于可清空的测试输入框，固定文字不会经过语音识别。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L("3 秒后测试写入")) { store.scheduleFixedTextTest() }.disabled(!store.canStart)
                    Button(store.fixedTextTestArmed ? L("关闭固定文字测试") : L("准备固定文字测试")) { store.armFixedTextTest() }
                        .disabled(!store.canStart)
                }
            }.padding(.top, 8)
        }.font(.callout).foregroundStyle(.secondary)
    }
}
