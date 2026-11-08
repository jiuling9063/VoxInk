import VoxInkCore
import SwiftUI

struct SetupView: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @State private var troubleshooting = false
    @State private var providers = false
    @State private var shortcuts = false
    private var theme: VoxInkTheme { VoxInkTheme(scheme: scheme) }
    private var progress: SetupProgress { store.setupProgress }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let index = (progress.steps.firstIndex(of: progress.step) ?? 0) + 1
            Text("\(index) / \(progress.steps.count) · \(progress.step.title)").font(.caption)
            ProgressView(value: Double(index), total: Double(progress.steps.count))
            if let notice = store.setupNotice { Text(notice).foregroundStyle(theme.caution) }
            switch progress.step {
            case .usage:
                Text(L("你在哪台电脑上打字？")).font(.title2.bold())
                ViewThatFits(in: .horizontal) {
                    HStack { scenarioCards }
                    VStack { scenarioCards }
                }
                Button(L("两台都用")) { store.chooseSetupUsage(.remote) }.buttonStyle(.link)
                Text(L("随时可以稍后设置；已完成的步骤会保存，可从“首次准备”继续。")).font(.caption)
            case .preparation: preparation
            case .remote: remote
            case .trial: trial
            }
            if store.phase == .failed && store.setupBlockingHint != store.status {
                Text(store.status).font(.caption).foregroundStyle(theme.caution)
            }
        }
        .onChange(of: progress.step) { troubleshooting = false }
    }

    @ViewBuilder private var scenarioCards: some View {
        scenario(.local, L("就在这台 Mac 上"), L("说完，文字写进当前应用。"), "laptopcomputer")
        scenario(.remote, L("在远程桌面里的电脑上"), L("本机识别，经远程工具的剪贴板送到远端。"), "desktopcomputer")
    }

    private func scenario(_ usage: SetupUsage, _ title: String, _ detail: String, _ icon: String) -> some View {
        Button { store.chooseSetupUsage(usage) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).foregroundStyle(theme.accent)
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }.frame(minWidth: 155, maxWidth: .infinity, alignment: .leading).padding(14).writingSurface()
        }.buttonStyle(.plain).disabled(!store.canStart)
    }

    private func row<Actions: View>(_ title: String, _ detail: String, ready: Bool,
                                    @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(ready ? theme.accent : theme.caution).frame(width: 7, height: 7)
                Text(title).font(.headline)
            }
            Text(detail).font(.callout).foregroundStyle(.secondary)
            actions()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preparation: some View {
        VStack(alignment: .leading, spacing: 12) {
            row(L("麦克风"), store.microphoneAuthorization == .authorized
                ? L("已允许 · 只在你开始录音后采集声音") : store.microphoneAuthorization.title,
                ready: store.microphoneAuthorization == .authorized) {
                if store.microphoneAuthorization == .notDetermined {
                    Button(L("允许麦克风")) { store.requestMicrophonePermission() }
                } else if store.microphoneAuthorization != .authorized {
                    Button(L("打开系统设置")) { store.openSystemSettings() }
                }
            }
            Divider()
            row(L("文字写入"), store.pastePermissionGranted ? L("已允许") : L("需要辅助功能权限"), ready: store.pastePermissionGranted) {
                if !store.pastePermissionGranted { Button(L("允许文字写入")) { store.requestPastePermission() } }
            }
            Divider()
            row(L("快捷键"), store.shortcutAvailable ? store.shortcutMode.title : store.shortcutStatus, ready: store.shortcutAvailable) {
                HStack { Keycap(title: store.shortcutCombination.title); Button(L("更改")) { shortcuts = true } }
                    .popover(isPresented: $shortcuts) { ShortcutSettingsControl(store: store).padding(16) }
            }
            Divider()
            row(L("识别"), store.modelServices.transcriptionID == nil && !store.transcriptionReady
                ? L("本地 Qwen3-ASR · 约 713 MB，可断点续传") : store.transcriptionStatus, ready: store.transcriptionReady) {
                if let install = store.modelInstallationProgress {
                    ProgressView(store.setupDownloadSummary ?? install.title, value: install.fraction)
                }
                Button(L("改用在线服务…")) { providers = true }.buttonStyle(.link)
                    .popover(isPresented: $providers) { ModelServicePicker(store: store, purpose: .transcription).padding(16).frame(width: 400) }
            }
        }.padding(16).writingSurface()
    }

    private var remote: some View {
        VStack(alignment: .leading, spacing: 12) {
            RemoteInputSettingsView(store: store, initiallyExpanded: true)
            VStack(alignment: .leading, spacing: 10) {
                Text(L("剪贴板同步")).font(.headline)
                Text(L("连接远端后，确认本机复制的文字能手动粘贴到远端。有“剪贴板同步”或“共享剪贴板”开关时，请在两端开启；默认同步的工具可直接验证。"))
                Text(L("语落会临时替换剪贴板以发送文字。")).font(.caption)
                Toggle(L("我已确认本机复制的文字可以粘贴到远端"), isOn: Binding(
                    get: { progress.clipboardSyncConfirmed }, set: { store.confirmSetupClipboardSync($0) }))
                    .disabled(store.remoteApplications.isEmpty)
                DisclosureGroup(L("为什么需要确认")) {
                    Text(L("语落无法读取或代开这个开关；下一步会实际测试文字能否传过去。"))
                }
            }.padding(14).background(theme.caution.opacity(0.1), in: RoundedRectangle(cornerRadius: VoxInkTheme.Radius.card))
        }.font(.callout)
    }

    private var trial: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { channelNodes }
                VStack(alignment: .leading, spacing: 5) { channelNodes }
            }
            if store.transcriptionReady {
                Text(progress.usage.needsRemote ? L("切到远端的记事本，说“明天下午开会”。") : L("切到任意输入框，说“明天下午开会”。")).font(.title3)
                ViewThatFits(in: .horizontal) {
                    HStack { keyInstruction }
                    VStack(alignment: .leading) { keyInstruction }
                }
            } else {
                Text(store.setupDownloadSummary ?? store.transcriptionStatus)
                fixedTest
            }
            if store.setupTrialCanConfirm {
                Text(store.transcript).font(.transcriptBody(size: 17)).textSelection(.enabled)
                Text(L("已发送到 \(store.shortcutTargetName ?? L("目标应用"))")).font(.caption)
                Text(progress.usage.needsRemote ? L("远端出现这句话了吗？") : L("\(store.shortcutTargetName ?? L("目标应用"))里出现这句话了吗？"))
                Button(L("出现了")) { store.confirmSetupTrial(true); troubleshooting = false }
                    .buttonStyle(VoxInkButtonStyle(prominent: true))
            }
            Button(L("没有 / 不对")) { store.confirmSetupTrial(false); troubleshooting = true }
            if progress.usage.needsRemote {
                Text(L("“已发送粘贴”不代表远端已收到，请查看目标输入框后确认。")).font(.caption)
            }
            if troubleshooting || store.phase == .failed {
                Divider()
                if store.transcriptionReady { fixedTest }
                Text(L("1. 复制测试文字，切换到同一个输入框，手动粘贴。此操作会替换当前剪贴板。"))
                Button(L("复制测试文字")) { store.copySetupTestText() }
                if progress.usage.needsRemote {
                    Text(L("2. 手动粘贴也失败：检查远程连接与两端剪贴板同步；出现旧文字时，尝试更长的同步等待。"))
                }
                Text(L("手动成功、自动失败：检查文字写入权限、粘贴方式和输入框焦点。"))
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).writingSurface()
    }

    @ViewBuilder private var channelNodes: some View {
        channel(L("麦克风"), store.microphoneAuthorization == .authorized)
        channel(store.setupDownloadSummary ?? L("识别"), store.transcriptionReady)
        channel(L("文字写入"), store.pastePermissionGranted)
        if progress.usage.needsRemote {
            channel(store.remoteApplications.first?.name ?? L("远程工具"), progress.clipboardSyncConfirmed)
        }
    }

    private func channel(_ title: String, _ ready: Bool) -> some View {
        Label(title, systemImage: ready ? "checkmark.circle" : "circle")
            .font(.caption).foregroundStyle(ready ? theme.accent : theme.caution)
            .accessibilityValue(ready ? L("已就绪") : L("待处理"))
    }

    @ViewBuilder private var keyInstruction: some View {
        Keycap(title: store.shortcutCombination.title)
        Text(store.shortcutMode.title).font(.headline)
    }

    private var fixedTest: some View {
        Button(store.fixedTextTestArmed ? L("取消测试") : L("只测写入")) {
            if store.fixedTextTestArmed { store.stopSetupTextTest() } else { store.startSetupTextTest() }
        }.disabled(!store.canStart || !store.pastePermissionGranted || !store.shortcutAvailable)
    }
}

struct SetupNavigationView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let hint = store.setupBlockingHint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ViewThatFits(in: .horizontal) {
                HStack { navigation }
                VStack(alignment: .leading, spacing: 10) { navigation }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder private var navigation: some View {
        if store.setupProgress.step != .usage {
            Button(L("上一步")) { store.previousSetupStep() }.disabled(!store.canStart)
        }
        Button(L("稍后设置")) { store.deferSetup() }.disabled(!store.canStart)
        Spacer(minLength: 0)
        if store.setupProgress.step != .usage {
            Button(store.canStartSetupDownload ? L("下载并继续") : (store.setupProgress.step == .trial ? L("完成引导") : L("下一步")),
                   systemImage: "arrow.right") {
                store.prepareAndAdvanceSetup()
            }.buttonStyle(VoxInkButtonStyle(prominent: true)).disabled(!store.canAdvanceSetup && !store.canStartSetupDownload)
        }
    }
}
