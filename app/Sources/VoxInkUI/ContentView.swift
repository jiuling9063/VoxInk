import VoxInkCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @Environment(\.colorScheme) private var scheme
    private var theme: VoxInkTheme { VoxInkTheme(scheme: scheme) }
    @ObservedObject private var store: AppStore
    @State private var showingReadiness = false
    @State private var importing = false
    @State private var showingOriginal = false
    @State private var originalHeight: CGFloat = 0
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
                        Text(L("工作空间")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.bottom, 12)
                        navigation(L("语音工作台"), icon: "rectangle.grid.2x2", destination: .input)
                        navigation(L("转录历史"), icon: "clock", destination: .history)
                        navigation(L("统计"), icon: "chart.bar", destination: .statistics)
                        Text(L("设置")).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.top, 22)
                        navigation(L("转录引擎"), icon: "waveform", destination: .engine)
                        navigation(L("快捷键与输入"), icon: "command", destination: .shortcut)
                        navigation(L("文字与词典"), icon: "text.badge.checkmark", destination: .postprocess)
                        navigation(L("润色模型"), icon: "wand.and.stars", destination: .polish)
                        navigation(L("使用方法"), icon: "questionmark.circle", destination: .help)
                        if !store.setupCompleted {
                            Button { store.showSetup(); page = .input } label: {
                                Label(L("首次准备"), systemImage: "checklist")
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            }
                        }
                    }.buttonStyle(.plain).padding(12).padding(.top, 24)
                    }.scrollIndicators(.hidden)
                    VStack(alignment: .leading, spacing: 6) {
                        Divider().padding(.bottom, 8)
                        Label(L("本机处理 · 安心表达"), systemImage: "lock.shield")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Text("VoxInk \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("开发版"))")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.bottom, 20).padding(.top, 12)
                    }.frame(width: 192).workspaceChrome()
                    Divider()
                switch page {
                case .engine, .shortcut, .postprocess, .polish, .help:
                    WorkspaceSettingsView(store: store, page: page) { page = .input }
                case .input, .history, .statistics, .result:
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if page == .history || page == .statistics {
                            SessionHistoryView(store: store, statistics: page == .statistics)
                        } else if page == .result {
                            WorkspaceHeading(title: L("本次结果"), subtitle: L("查看原文，整理表达，随时复制。"))
                            result.padding(22).writingSurface()
                        } else {
                        if store.isShowingSetup { SetupView(store: store).id("setup") }
                        else {
                            statusHero
                            Label(L("音频在本机处理，文字只留在当前会话。"), systemImage: "lock.shield")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if store.isShowingSetup && store.setupProgress.step == .speech { recordingControls.padding(22).writingSurface().id("activity") }
                        retainedRecording
                        if !store.isShowingSetup || store.setupProgress.step == .speech || !store.transcript.isEmpty {
                            result.padding(18).writingSurface().id("result")
                        }
                        #if DEBUG
                        if !store.isShowingSetup { diagnostics }
                        #endif
                        }
                    }.workspacePageMargins()
                }
                .onChange(of: store.setupProgress.step) { _, _ in
                    if store.isShowingSetup { scroll.scrollTo("setup", anchor: .top) }
                }
                .onChange(of: store.transcript) { _, text in
                    if !text.isEmpty { scroll.scrollTo(store.isShowingSetup ? "setup" : "activity", anchor: .top) }
                }
                .onChange(of: store.retainedAudio?.id) { _, id in
                    if id != nil { scroll.scrollTo("activity", anchor: .top) }
                }
                .onChange(of: originalHeight) { _, _ in
                    if showingOriginal { scroll.scrollTo("original", anchor: .bottom) }
                }
                }
                }
            }
        }
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

    private func navigation(_ title: String, icon: String, destination: WorkspacePage) -> some View {
        Button {
            page = destination
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: page == destination ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10)
                .foregroundStyle(page == destination ? theme.accent : theme.ink.opacity(0.7))
                .background(page == destination ? theme.accent.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
        }.accessibilityAddTraits(page == destination ? .isSelected : [])
            .help(title)
    }

    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(L("语音工作台"), systemImage: "waveform").font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                Spacer()
                Text(store.shortcutCombination.title).font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            dailyInstruction
            recordingControls
            Divider().padding(.vertical, 4)
            DisclosureGroup(isExpanded: $showingReadiness) {
                dashboardReadiness.padding(.top, 10)
            } label: {
                Label(store.inputReady ? L("权限与模型已就绪") : (store.canStart ? L("检查权限与模型") : L("权限与模型")),
                      systemImage: store.inputReady ? "checkmark.shield" : (store.canStart ? "exclamationmark.circle" : "shield"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(store.inputReady ? theme.accent : (store.canStart ? .orange : .secondary))
            }
        }.padding(24).writingSurface().id("activity")
    }

    private var dashboardReadiness: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("准备状态")).font(.headline)
                Spacer()
                if store.canRecord {
                    Label(L("可以开始说话"), systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium)).foregroundStyle(.green)
                } else {
                    Text(store.canStart ? L("点击即可处理") : L("正在处理，请稍候")).font(.caption).foregroundStyle(.secondary)
                }
            }
            dashboardRow(icon: "mic.fill", title: L("麦克风"),
                         detail: store.microphoneAuthorization == .authorized ? L("已允许") : L("需要允许录音"),
                         ready: store.microphoneAuthorization == .authorized) {
                if store.microphoneAuthorization == .notDetermined { store.requestMicrophonePermission() }
                else { store.openSystemSettings() }
            }
            dashboardRow(icon: "cursorarrow.and.square.on.square.dashed", title: L("文字写入"),
                         detail: store.pastePermissionGranted ? L("已允许自动写入") : L("需要辅助功能权限"),
                         ready: store.pastePermissionGranted) { store.requestPastePermission() }
            dashboardRow(icon: "internaldrive.fill", title: L("本地模型"),
                         detail: store.modelState.title, ready: store.modelState == .ready) {
                if store.modelState == .needsDownload { store.installModel() } else { store.warmUp() }
            }
        }
        .padding(14)
        .background(theme.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.ink.opacity(0.06), lineWidth: 1) }
    }

    private func dashboardRow(icon: String, title: String, detail: String, ready: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.caption.weight(.semibold))
                    .foregroundStyle(ready ? Color.green : theme.accent)
                    .frame(width: 26, height: 26)
                    .background((ready ? Color.green : theme.accent).opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: ready ? "checkmark.circle.fill" : "chevron.right")
                    .font(.caption.weight(.bold)).foregroundStyle(ready ? Color.green : .secondary)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(ready || !store.canStart)
        .accessibilityHint(ready ? L("已完成") : L("点击处理"))
    }

    private var dailyInstruction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.shortcutMode == .holdToTalk ? L("按住说话，松开写入。") : L("按一下说话，再按一下写入。"))
                .font(.system(size: 27, weight: .semibold)).tracking(-0.6).foregroundStyle(theme.ink)
            Text(L("先点选输入框，再使用 \(store.shortcutCombination.title)。识别完成后，文字会自动写入。"))
                .foregroundStyle(.secondary)

        }
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                if !store.canStart && store.phase != .recording { ProgressView().controlSize(.small) }
                else {
                    Image(systemName: store.phase == .failed ? "exclamationmark.circle" : "waveform")
                        .foregroundStyle(store.phase == .failed ? Color.orange : theme.accent)
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
            HStack {
                Button(store.phase == .recording ? L("停止并识别") : L("开始录音"),
                    systemImage: store.phase == .recording ? "stop.fill" : "mic.fill") {
                    if store.phase == .recording { store.finishRecording() } else { store.beginRecording() }
                }.buttonStyle(VoxInkButtonStyle(prominent: true)).disabled(!store.canStart && store.phase != .recording)
                Button(L("导入音频…"), systemImage: "doc.badge.plus") { importing = true }.disabled(!store.canStart)
                if store.canCancel { Button(L("取消")) { Task { await store.cancel() } } }
                Spacer()
            }
            Text(L("窗口内试录与导入只展示结果；使用快捷键录音才会自动写入目标应用。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func recoveryButton(_ recovery: RecoveryAction) -> some View {
        switch recovery {
        case .installModel: Button(L("下载或继续安装")) { store.installModel() }.disabled(!store.canStart)
        case .reloadModel: Button(L("重新加载模型")) { store.warmUp() }.disabled(!store.canStart)
        case .microphone: Button(L("打开系统设置")) { store.openSystemSettings() }
        case .pastePermission: Button(L("允许文字写入")) { store.requestPastePermission() }.disabled(!store.canStart)
        case .chooseAudio: Button(L("选择音频…")) { importing = true }.disabled(!store.canStart)
        case .recordAgain, .checkTarget, .inspectClipboard, .checkInstallation: EmptyView()
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
                .font(.caption).foregroundStyle(.orange)
        }
    }

    private var result: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let warning = store.conversionWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(L("识别结果")).font(.headline)
                Spacer()
                if store.canPasteAgain {
                    Button(L("重新粘贴")) { store.pasteAgain() }
                        .help(L("重新粘贴到 \(store.repasteTargetName ?? L("原目标应用"))，请先确认没有重复文字。"))
                }
                Button(L("复制"), systemImage: "doc.on.doc") { store.copyResult() }
                    .disabled(store.transcript.isEmpty || !store.canStart)
            }
            if let target = store.repasteTargetName {
                Text(L("上次写入目标：\(target)")).font(.caption).foregroundStyle(.secondary)
            }
            if store.transcript.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.alignleft").font(.title2).foregroundStyle(.tertiary)
                    Text(L("你的文字将在这里出现")).foregroundStyle(.secondary)
                    Text(L("试着说一句话，或导入不超过 60 秒的音频。"))
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 120)
            } else {
                if !store.polishMessage.isEmpty {
                    Text(store.polishMessage).font(.caption).foregroundStyle(.secondary)
                }
                Text(store.transcript).font(.body).lineSpacing(5).textSelection(.enabled)
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading).padding(16)
                    .background(theme.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(theme.accent.opacity(0.45))
                            .frame(width: 2).padding(.vertical, 18).padding(.leading, 6)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                if !store.rawTranscript.isEmpty {
                    DisclosureGroup(L("查看识别原文"), isExpanded: $showingOriginal) {
                        if store.rawTranscript == store.transcript {
                            Text(L("本次原文无需调整。")).font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(store.rawTranscript).font(.callout).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }.font(.caption).foregroundStyle(.secondary).id("original")
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { originalHeight = $0 }
                }
            }
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
