import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @Environment(\.colorScheme) private var scheme
    private var theme: VoxInkTheme { VoxInkTheme(scheme: scheme) }
    @ObservedObject private var store: AppStore
    @State private var importing = false
    @State private var showingOriginal = false
    @State private var originalHeight: CGFloat = 0
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { scroll in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 22) {
                        Text("工作空间").font(.caption).foregroundStyle(.secondary)
                        Button { scroll.scrollTo("activity", anchor: .top) } label: {
                            Label("语音输入", systemImage: "waveform")
                        }
                        Button { scroll.scrollTo("result", anchor: .top) } label: {
                            Label("本次结果", systemImage: "text.alignleft")
                        }
                        Divider()
                        SettingsLink { Label("偏好设置", systemImage: "slider.horizontal.3") }
                        Spacer()
                        Label("本机识别", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.plain).padding(16).frame(width: 140).background(theme.paper)
                    Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !store.setupCompleted { SetupView(store: store) }
                        else {
                            statusHero
                            usageCards
                        }
                        if !store.setupCompleted { recordingControls.id("activity") }
                        retainedRecording
                        result.padding(18).writingSurface().id("result")
                        diagnostics
                    }.padding(24)
                }
                .onChange(of: store.transcript) { _, text in
                    if !text.isEmpty { scroll.scrollTo("activity", anchor: .top) }
                }
                .onChange(of: store.retainedAudio?.id) { _, id in
                    if id != nil { scroll.scrollTo("activity", anchor: .top) }
                }
                .onChange(of: originalHeight) { _, _ in
                    if showingOriginal { scroll.scrollTo("original", anchor: .bottom) }
                }
                }
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").accessibilityHidden(true)
                Text(store.conversionWarning ?? "本机识别 · 默认简体 · 网址、数字与代码原样保留")
                Spacer()
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
        }
        .tint(theme.accent)
        .background(theme.background)
        .frame(minWidth: 620, minHeight: 520)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { store.importAudio(url) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("logo-rain-impression-v2", bundle: .module)
                .resizable().scaledToFit().frame(width: 34, height: 34)
                .accessibilityLabel("语落 VoxInk")
            Text("语落").font(.title2.bold()).foregroundStyle(theme.ink)
            Text("VoxInk").foregroundStyle(.secondary)
            Spacer()
            Text(store.modelState.title).font(.caption.weight(.medium)).foregroundStyle(theme.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(theme.accent.opacity(0.1), in: Capsule())
            SettingsLink { Label("设置", systemImage: "gearshape") }
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("语音工作台", systemImage: "waveform").font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
            dailyInstruction
            recordingControls
        }.padding(24).writingSurface().id("activity")
    }

    private var usageCards: some View {
        HStack(spacing: 12) {
            usageCard(title: "麦克风", value: store.microphoneAuthorization == .authorized ? "已允许" : "待授权", detail: "开始录音后采集")
            usageCard(title: "识别方式", value: "本机处理", detail: "音频不离开设备")
            usageCard(title: "文字写入", value: store.pastePermissionGranted ? "已允许" : "待授权", detail: "辅助功能权限")
        }
    }

    private func usageCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).writingSurface()
    }

    private var dailyInstruction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.shortcutMode == .holdToTalk ? "按住说话，松开写入。" : "按一下说话，再按一下写入。")
                .font(.title.bold()).foregroundStyle(theme.ink)
            Text("先点选输入框，再使用 \(store.shortcutCombination.title)。识别完成后，文字会自动写入。")
                .foregroundStyle(.secondary)
            HStack {
                Label(store.modelState.title, systemImage: "internaldrive")
                Spacer()
                Text(store.shortcutStatus)
            }.font(.caption).foregroundStyle(.secondary)
            if store.microphoneAuthorization != .authorized || !store.pastePermissionGranted {
                HStack {
                    Label("输入权限需要检查", systemImage: "exclamationmark.circle")
                    Spacer()
                    Button("查看权限") { store.showSetup() }
                }.font(.callout)
            }
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
                if store.phase == .recording { Text("\(Int(store.elapsed)) / 60 秒").monospacedDigit() }
            }
            if store.phase == .recording { ProgressView(value: Double(store.level)).tint(theme.accent) }
            if let recovery = store.recovery {
                Text(recovery.guidance).font(.callout).foregroundStyle(.secondary)
                recoveryButton(recovery)
            }
            HStack {
                Button(store.phase == .recording ? "停止并识别" : "试录一段",
                    systemImage: store.phase == .recording ? "stop.fill" : "mic.fill") {
                    if store.phase == .recording { store.finishRecording() } else { store.beginRecording() }
                }.buttonStyle(.borderedProminent).disabled(!store.canStart && store.phase != .recording)
                Button("导入音频…", systemImage: "doc.badge.plus") { importing = true }.disabled(!store.canStart)
                if store.canCancel { Button("取消") { Task { await store.cancel() } } }
                Spacer()
            }
            Text("窗口内试录与导入只展示结果；使用快捷键录音才会自动写入目标应用。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).writingSurface()
    }

    @ViewBuilder private func recoveryButton(_ recovery: RecoveryAction) -> some View {
        switch recovery {
        case .installModel: Button("下载或继续安装") { store.installModel() }.disabled(!store.canStart)
        case .reloadModel: Button("重新加载模型") { store.warmUp() }.disabled(!store.canStart)
        case .microphone: Button("打开系统设置") { store.openSystemSettings() }
        case .pastePermission: Button("允许文字写入") { store.requestPastePermission() }.disabled(!store.canStart)
        case .chooseAudio: Button("选择音频…") { importing = true }.disabled(!store.canStart)
        case .recordAgain, .checkTarget, .inspectClipboard, .checkInstallation: EmptyView()
        }
    }

    @ViewBuilder private var retainedRecording: some View {
        if let record = store.retainedAudio {
            VStack(alignment: .leading, spacing: 10) {
                Label("有一条未完成录音", systemImage: "waveform.badge.exclamationmark")
                    .font(.headline)
                Text("保留至 \(record.expiresAt.formatted(date: .abbreviated, time: .shortened))。重试只展示文字，不会自动写入。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("重试识别") { store.retryRetainedAudio() }.disabled(!store.canRetryAudio)
                    Button("删除保留录音", role: .destructive) { store.deleteRetainedAudio() }
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
            HStack {
                Text("识别结果").font(.headline)
                Spacer()
                if store.canPasteAgain {
                    Button("重新粘贴") { store.pasteAgain() }
                        .help("重新粘贴到 \(store.repasteTargetName ?? "原目标应用")，请先确认没有重复文字。")
                }
                Button("复制", systemImage: "doc.on.doc") { store.copyResult() }
                    .disabled(store.transcript.isEmpty || !store.canStart)
            }
            if let target = store.repasteTargetName {
                Text("上次写入目标：\(target)").font(.caption).foregroundStyle(.secondary)
            }
            if store.transcript.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.alignleft").font(.title2).foregroundStyle(.tertiary)
                    Text("你的文字将在这里出现").foregroundStyle(.secondary)
                    Text("试着说一句话，或导入不超过 60 秒的音频。")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Text(store.transcript).font(.body).lineSpacing(5).textSelection(.enabled)
                    .foregroundStyle(theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading).padding(16)
                    .writingSurface()
                    .overlay(alignment: .leading) {
                        Capsule().fill(theme.accent.opacity(0.45))
                            .frame(width: 2).padding(.vertical, 18).padding(.leading, 6)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                if !store.rawTranscript.isEmpty {
                    DisclosureGroup("查看识别原文", isExpanded: $showingOriginal) {
                        if store.rawTranscript == store.transcript {
                            Text("本次原文无需调整。").font(.caption).foregroundStyle(.secondary)
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
        DisclosureGroup("开发验证工具") {
            VStack(alignment: .leading, spacing: 10) {
                Text("只用于可清空的测试输入框，固定文字不会经过语音识别。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("3 秒后测试写入") { store.scheduleFixedTextTest() }.disabled(!store.canStart)
                    Button(store.fixedTextTestArmed ? "关闭固定文字测试" : "准备固定文字测试") { store.armFixedTextTest() }
                        .disabled(!store.canStart)
                }
            }.padding(.top, 8)
        }.font(.callout).foregroundStyle(.secondary)
    }
}
