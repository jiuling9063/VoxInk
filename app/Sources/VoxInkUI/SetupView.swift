import VoxInkCore
import SwiftUI

struct ReadinessRow<Actions: View>: View {
    let icon: String
    let title: String
    let detail: String
    let ready: Bool
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                description
                Spacer(minLength: 12)
                actions().fixedSize()
            }
            VStack(alignment: .leading, spacing: 12) {
                description
                actions().padding(.leading, 52)
            }
        }.padding(.vertical, 12)
    }

    private var description: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3).foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if ready { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel(L("已就绪")) }
                }
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(minWidth: 160, alignment: .leading)
        }
    }
}

struct SetupView: View {
    @ObservedObject var store: AppStore
    @State private var showingTroubleshooting = false

    private var progress: SetupProgress { store.setupProgress }
    private var confirmed: Bool {
        progress.step == .text ? progress.textConfirmed : progress.speechConfirmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkspaceHeading(title: progress.step.title,
                             subtitle: L("第 \((progress.steps.firstIndex(of: progress.step) ?? 0) + 1) 步，共 \(progress.steps.count) 步 · 首次输入引导"))
            ProgressView(value: Double(progress.steps.firstIndex(of: progress.step) ?? 0),
                         total: Double(progress.steps.count))
                .accessibilityLabel(L("首次准备"))
            Group {
                switch progress.step {
                case .usage: usage
                case .preparation: preparation
                case .remote: remote
                case .text, .speech: trial
                }
            }
            if !store.canStart || progress.step == .text || progress.step == .speech {
                Text(store.status).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.canCancel {
                Button(L("取消")) { Task { await store.cancel() } }
            }
            ViewThatFits(in: .horizontal) {
                HStack { navigation }
                VStack(alignment: .leading, spacing: 12) { navigation }
            }
        }
        .onChange(of: progress.step) { _, _ in showingTroubleshooting = false }
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("你准备在哪里使用语音输入？")).font(.headline)
            Picker(L("使用场景"), selection: Binding(get: { progress.usage }, set: { store.setSetupUsage($0) })) {
                ForEach(SetupUsage.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.radioGroup).disabled(!store.canStart)
            Text(L("远程输入时，在本机说话并识别，再通过远程工具的剪贴板同步传递文字。"))
                .font(.callout).foregroundStyle(.secondary)
            Text(L("随时可以稍后设置；已完成的步骤会保存，可从“首次准备”继续。"))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).writingSurface()
    }

    private var preparation: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                ReadinessRow(icon: "mic", title: L("允许麦克风"), detail: L("\(store.microphoneAuthorization.title) · 仅在你开始录音后采集声音。"),
                    ready: store.microphoneAuthorization == .authorized) {
                    if store.microphoneAuthorization == .notDetermined {
                        Button(L("允许麦克风")) { store.requestMicrophonePermission() }.disabled(!store.canStart)
                    } else if store.microphoneAuthorization != .authorized {
                        Button(L("打开系统设置")) { store.openSystemSettings() }
                    }
                }
                Divider()
                ReadinessRow(icon: "cursorarrow.and.square.on.square.dashed", title: L("允许文字写入"),
                    detail: store.pastePermissionGranted ? L("已允许 · 识别后自动粘贴到目标输入框。") : L("需要辅助功能权限，用于把识别结果写入目标输入框。"),
                    ready: store.pastePermissionGranted) {
                    if !store.pastePermissionGranted {
                        Button(L("允许文字写入")) { store.requestPastePermission() }.disabled(!store.canStart)
                    }
                }
                Divider()
                ReadinessRow(icon: "internaldrive", title: L("准备本地模型"), detail: L("\(store.modelState.title) · 识别时音频不离开本机。"),
                    ready: store.modelState == .ready) {
                    if store.modelState == .loading { ProgressView().controlSize(.small) }
                    else if store.modelState == .needsDownload {
                        Button(L("下载或继续安装")) { store.installModel() }.disabled(!store.canStart)
                    }
                    else if store.modelState != .ready {
                        Button(store.modelState == .failed ? L("重新加载") : L("加载模型")) { store.warmUp() }.disabled(!store.canStart)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .writingSurface()
            if let progress = store.modelInstallationProgress {
                ProgressView(progress.title, value: progress.fraction)
                    .accessibilityLabel(L("模型准备进度"))
            }
            if store.modelState == .needsDownload {
                Text(L("首次下载约 713 MB，之后离线使用。仅模型下载会访问网络，录音不会上传。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ShortcutSettingsControl(store: store)
            Text(store.shortcutInstruction).font(.callout).foregroundStyle(.secondary)
            Button(L("刷新状态"), systemImage: "arrow.clockwise") { store.refreshPermissions() }
                .disabled(!store.canStart)
        }
    }

    private var remote: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("添加本机安装的远程工具，按远端电脑的系统选择粘贴方式。"))
                .font(.callout)
            RemoteInputSettingsView(store: store, initiallyExpanded: true)
            Divider()
            Text(L("连接远端后，在远程工具的设置或会话工具栏中开启“剪贴板同步”或“共享剪贴板”。如两端分别有开关，都需要检查。"))
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Text(L("语落无法读取或代开这个开关；下一步会实际测试文字能否传过去。"))
                .font(.caption).foregroundStyle(.secondary)
            Toggle(L("我已在远程工具中开启剪贴板同步"), isOn: Binding(
                get: { progress.clipboardSyncConfirmed }, set: { store.confirmSetupClipboardSync($0) }))
                .disabled(!store.canStart || store.remoteApplications.isEmpty)
        }.padding(18).writingSurface()
    }

    private var trial: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(progress.usage.needsRemote
                 ? L("请在已添加的远程工具内，打开远端记事本或其他可清空的输入框。")
                 : L("请在本机文本编辑器中打开一个可清空的输入框。"))
                .font(.callout)
            Text(L("测试期间保持同一输入位置，只检查文字是否出现，不发送消息。"))
                .font(.caption).foregroundStyle(.secondary)
            if progress.step == .text {
                Text(L("先点击“准备测试”，再切换到输入框，按一次当前快捷键。此次只写入固定文字，不会录音。"))
                    .font(.callout)
                Text(L("语落固定文字测试：中文、English、123。"))
                    .textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                Button(store.fixedTextTestArmed ? L("取消测试") : L("准备测试"), systemImage: "text.cursor") {
                    if store.fixedTextTestArmed { store.stopSetupTextTest() }
                    else { showingTroubleshooting = false; store.startSetupTextTest() }
                }.disabled(!store.canStart || !store.pastePermissionGranted || !store.shortcutAvailable)
            } else {
                Text(store.shortcutInstruction).font(.headline)
                Text(L("试着说：“明天下午开会。”结束录音后，等待文字出现在目标输入框。"))
                    .font(.callout)
            }
            Label(store.shortcutCombination.title, systemImage: "command").font(.headline)
            if confirmed {
                Label(L("已由你确认文字出现在目标输入框"), systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(.green)
            } else {
                Text(L("“已发送粘贴”不代表远端已收到，请查看目标输入框后确认。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { confirmationButtons }
                VStack(alignment: .leading, spacing: 10) { confirmationButtons }
            }
            if showingTroubleshooting || store.phase == .failed { troubleshooting }
            if progress.usage.needsRemote {
                Text(L("本次确认仅针对你测试的远程会话；更换工具、远端系统或设备后，请重新验证。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).writingSurface()
    }

    @ViewBuilder private var confirmationButtons: some View {
        Button(L("看到了正确文字")) { store.confirmSetupTrial(true); showingTroubleshooting = false }
            .disabled(!store.canStart || !store.setupTrialCanConfirm || store.fixedTextTestArmed)
        Button(L("没有出现或文字不对")) { store.confirmSetupTrial(false); showingTroubleshooting = true }
            .disabled(!store.canStart || store.fixedTextTestArmed)
    }

    private var troubleshooting: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(L("按顺序排查")).font(.headline)
            Text(L("1. 复制测试文字，切换到同一个输入框，手动粘贴。此操作会替换当前剪贴板。"))
            Button(L("复制测试文字")) { store.copySetupTestText() }.disabled(!store.canStart)
            if progress.usage.needsRemote {
                Text(L("2. 手动粘贴也失败：检查远程连接与两端剪贴板同步；出现旧文字时，尝试更长的同步等待。"))
            }
            Text(L("3. 手动粘贴成功但自动写入失败：检查辅助功能权限、远端粘贴方式、输入框焦点和快捷键冲突。可返回前面步骤修改。"))
            if progress.step == .speech {
                Text(L("4. 没有录到声音或识别不对：在下方工作台试录，检查麦克风、模型和语音语言。工作台录音只展示结果，不自动写入。"))
            }
            Text(L("确认目标没有重复文字后再重试；仍不成功，可稍后设置，在工作台录音并手动复制。"))
        }.font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var navigation: some View {
        if progress.step != .usage {
            Button(L("上一步")) { store.previousSetupStep() }.disabled(!store.canStart)
        }
        Button(L("稍后设置")) { store.deferSetup() }.disabled(!store.canStart)
        Spacer(minLength: 0)
        Button(progress.step == .speech ? L("完成引导") : L("下一步"), systemImage: "arrow.right") {
            store.advanceSetup()
        }.buttonStyle(VoxInkButtonStyle(prominent: true)).disabled(!store.canAdvanceSetup)
    }
}
