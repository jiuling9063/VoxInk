import SwiftUI

struct ReadinessRow<Actions: View>: View {
    let icon: String
    let title: String
    let detail: String
    let ready: Bool
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title3).foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if ready { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("已就绪") }
                }
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            actions()
        }.padding(.vertical, 8)
    }
}

struct SetupView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("让想说的话，落成文字。").font(.title.bold())
                Text("完成下面的准备，就能直接在输入框中说话写入。\(store.shortcutInstruction)")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ReadinessRow(icon: "mic", title: "允许麦克风", detail: "\(store.microphoneAuthorization.title) · 仅在你开始录音后采集声音。",
                    ready: store.microphoneAuthorization == .authorized) {
                    if store.microphoneAuthorization == .notDetermined {
                        Button("允许麦克风") { store.requestMicrophonePermission() }.disabled(!store.canStart)
                    } else if store.microphoneAuthorization != .authorized {
                        Button("打开系统设置") { store.openSystemSettings() }
                    }
                }
                Divider()
                ReadinessRow(icon: "cursorarrow.and.square.on.square.dashed", title: "允许文字写入",
                    detail: store.pastePermissionGranted ? "已允许 · 识别后自动粘贴到目标输入框。" : "需要辅助功能权限，用于把识别结果写入目标输入框。",
                    ready: store.pastePermissionGranted) {
                    if !store.pastePermissionGranted {
                        Button("允许文字写入") { store.requestPastePermission() }.disabled(!store.canStart)
                    }
                }
                Divider()
                ReadinessRow(icon: "internaldrive", title: "准备本地模型", detail: "\(store.modelState.title) · 识别时音频不离开本机。",
                    ready: store.modelState == .ready) {
                    if store.modelState == .loading { ProgressView().controlSize(.small) }
                    else if store.modelState == .needsDownload {
                        Button("下载或继续安装") { store.installModel() }.disabled(!store.canStart)
                    }
                    else if store.modelState != .ready {
                        Button(store.modelState == .failed ? "重新加载" : "加载模型") { store.warmUp() }.disabled(!store.canStart)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            if let progress = store.modelInstallationProgress {
                ProgressView(progress.title, value: progress.fraction)
                    .accessibilityLabel("模型准备进度")
            }
            if store.modelState == .needsDownload {
                Text("首次下载约 713 MB，之后离线使用。仅模型下载会访问网络，录音不会上传。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("刷新状态", systemImage: "arrow.clockwise") { store.refreshPermissions() }
                Spacer()
                Button("开始使用", systemImage: "arrow.right") { store.completeSetup() }
                    .buttonStyle(.borderedProminent).disabled(!store.canCompleteSetup)
            }
            if !store.shortcutAvailable {
                Text(store.shortcutStatus).font(.callout).foregroundStyle(.orange)
            }
            Text("也可以先在下方试录，或导入一段音频。结果只保留在当前会话，关闭 App 后清除。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
