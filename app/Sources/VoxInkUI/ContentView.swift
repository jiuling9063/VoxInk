import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @Environment(\.colorScheme) private var scheme
    private var theme: VoxInkTheme { VoxInkTheme(scheme: scheme) }
    @ObservedObject private var store: AppStore
    @State private var importing = false
    @State private var showingOriginal = false
    @State private var originalHeight: CGFloat = 0
    @State private var page = "input"
    public init(store: AppStore) { self.store = store }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollViewReader { scroll in
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("工作空间").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.bottom, 12)
                        navigation("语音输入", icon: "waveform", destination: "input")
                        navigation("本次结果", icon: "text.alignleft", destination: "result")
                        navigation("转录历史", icon: "clock", destination: "history")
                        navigation("使用统计", icon: "chart.bar", destination: "statistics")
                        Spacer()
                        SettingsLink { Label("偏好设置", systemImage: "slider.horizontal.3")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                        Divider().padding(.vertical, 10)
                        Label("本机处理 · 安心表达", systemImage: "lock.shield")
                            .font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 8)
                    }.buttonStyle(.plain).padding(12).padding(.vertical, 12).frame(width: 156).background(theme.paper)
                    Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if page == "history" || page == "statistics" {
                            SessionHistoryView(store: store, statistics: page == "statistics")
                        } else if page == "result" {
                            Text("本次结果").font(.system(size: 26, weight: .bold))
                            Text("查看原文，整理表达，随时复制。") .foregroundStyle(.secondary)
                            result.padding(22).writingSurface()
                        } else {
                        if !store.setupCompleted { SetupView(store: store) }
                        else {
                            statusHero
                            usageCards
                        }
                        if !store.setupCompleted { recordingControls.padding(22).writingSurface().id("activity") }
                        retainedRecording
                        result.padding(18).writingSurface().id("result")
                        diagnostics
                        }
                    }.frame(maxWidth: 920, alignment: .leading).padding(24).frame(maxWidth: .infinity)
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
        }
        .tint(theme.accent)
        .buttonStyle(VoxInkButtonStyle())
        .background(theme.background)
        .frame(minWidth: 620, minHeight: 520)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result { store.importAudio(url) }
        }
    }

    private func navigation(_ title: String, icon: String, destination: String) -> some View {
        Button { page = destination } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: page == destination ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 12)
                .foregroundStyle(page == destination ? theme.accent : theme.ink.opacity(0.7))
                .background(page == destination ? theme.accent.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
        }.accessibilityAddTraits(page == destination ? .isSelected : [])
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let url = Bundle.module.url(forResource: "logo-rain-impression-v2", withExtension: "png"),
               let logo = NSImage(contentsOf: url) {
                Image(nsImage: logo).resizable().scaledToFit().frame(width: 34, height: 34)
                    .accessibilityLabel("语落 VoxInk")
            }
            Text("语落").font(.title2.bold()).foregroundStyle(theme.ink)
            Text("VoxInk").foregroundStyle(.secondary)
            Spacer()
            Text(store.modelState.title).font(.caption.weight(.medium)).foregroundStyle(theme.accent)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(theme.accent.opacity(0.1), in: Capsule())
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var statusHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("语音工作台", systemImage: "waveform").font(.caption.weight(.semibold)).foregroundStyle(theme.accent)
                Spacer()
                Text(store.shortcutCombination.title).font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            dailyInstruction
            Divider().padding(.vertical, 6)
            recordingControls
        }.padding(24).writingSurface().id("activity")
    }

    private var usageCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { readinessCards }
            VStack(spacing: 12) { readinessCards }
        }
    }

    private var readinessCards: some View {
        Group {
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
        }.frame(minWidth: 100, maxWidth: .infinity, alignment: .leading).padding(14).writingSurface()
    }

    private var dailyInstruction: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.shortcutMode == .holdToTalk ? "按住说话，松开写入。" : "按一下说话，再按一下写入。")
                .font(.system(size: 27, weight: .semibold)).tracking(-0.6).foregroundStyle(theme.ink)
            Text("先点选输入框，再使用 \(store.shortcutCombination.title)。识别完成后，文字会自动写入。")
                .foregroundStyle(.secondary)
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
                }.buttonStyle(VoxInkButtonStyle(prominent: true)).disabled(!store.canStart && store.phase != .recording)
                Button("导入音频…", systemImage: "doc.badge.plus") { importing = true }.disabled(!store.canStart)
                if store.canCancel { Button("取消") { Task { await store.cancel() } } }
                Spacer()
            }
            Text("窗口内试录与导入只展示结果；使用快捷键录音才会自动写入目标应用。")
                .font(.caption).foregroundStyle(.secondary)
        }
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
            if let warning = store.conversionWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
                if store.polishingEnabled {
                    Button("轻度润色预览", systemImage: "text.badge.checkmark") { store.previewPolish() }
                        .disabled(!store.canStart || store.isPolishing)
                    if store.isPolishing {
                        HStack {
                            ProgressView().controlSize(.small)
                            Button("取消润色") { store.discardPolish() }
                        }
                    }
                    Text(store.polishMessage).font(.caption).foregroundStyle(.secondary)
                    if let preview = store.polishedPreview {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("整理预览 · 原文保留在下方").font(.headline)
                            Text(preview).textSelection(.enabled)
                            Text(store.polishMessage).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("复制整理结果") { store.copyPolishedPreview() }.disabled(!store.canStart)
                                Button("恢复原文") { store.discardPolish() }
                            }
                        }.padding(16).writingSurface()
                    }
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
