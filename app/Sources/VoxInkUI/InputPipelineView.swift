import VoxInkCore
import SwiftUI

/// The workbench's single source of readiness: microphone → transcription → cleanup → delivery.
/// Each node shows its state and is also the place to fix it.
struct InputPipelineView: View {
    @ObservedObject var store: AppStore
    let navigate: (WorkspacePage) -> Void
    @Environment(\.colorScheme) private var scheme
    private var theme: VoxInkTheme { VoxInkTheme(scheme: scheme) }

    enum NodeState { case ready, busy, attention, off }

    struct Node: Identifiable {
        let id: String
        let icon: String
        let title: String
        let detail: String
        let state: NodeState
        let hint: String
        let action: () -> Void
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                        if index > 0 { connector }
                        nodeView(node)
                    }
                }
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow { nodeView(nodes[0]); nodeView(nodes[1]) }
                    GridRow { nodeView(nodes[2]); nodeView(nodes[3]) }
                }
            }
            .padding(10)
            .background(theme.sunken, in: RoundedRectangle(cornerRadius: VoxInkTheme.Radius.card, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(L("输入通道"))

            Label(privacyText, systemImage: usesNetwork ? "network" : "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Nodes

    private var nodes: [Node] {
        [microphoneNode, transcriptionNode, polishingNode, deliveryNode]
    }

    private var microphoneNode: Node {
        let granted = store.microphoneAuthorization == .authorized
        return Node(id: "microphone", icon: "mic", title: L("麦克风"),
                    detail: granted ? store.inputDeviceName : L("需要允许录音"),
                    state: granted ? .ready : .attention,
                    hint: granted ? L("打开系统设置") : L("允许麦克风")) {
            if store.microphoneAuthorization == .notDetermined { store.requestMicrophonePermission() }
            else if granted { navigate(.shortcut) } else { store.openSystemSettings() }
        }
    }

    private var transcriptionNode: Node {
        if store.modelServices.transcriptionID != nil {
            let connection = try? store.modelServices.connection(for: .transcription)
            return Node(id: "transcription", icon: "waveform", title: L("识别"),
                        detail: connection?.name ?? L("连接配置不可用"),
                        state: connection == nil ? .attention : .ready,
                        hint: L("查看识别与润色设置")) { navigate(.engine) }
        }
        let state: NodeState = switch store.modelState {
        case .ready: .ready
        case .loading: .busy
        case .notLoaded, .failed, .needsDownload: .attention
        }
        return Node(id: "transcription", icon: "waveform", title: L("识别"),
                    detail: store.modelState == .ready ? L("本地模型") : store.modelState.title,
                    state: state,
                    hint: store.modelState == .needsDownload ? L("下载或继续安装") : L("查看识别与润色设置")) {
            switch store.modelState {
            case .needsDownload: store.installModel()
            case .failed, .notLoaded: store.warmUp()
            case .ready, .loading: navigate(.engine)
            }
        }
    }

    private var polishingNode: Node {
        guard store.polishingEnabled else {
            return Node(id: "polishing", icon: "text.redaction", title: L("润色"), detail: L("关闭"),
                        state: .off, hint: L("查看识别与润色设置")) { navigate(.polish) }
        }
        let detail: String
        if store.modelServices.polishingID != nil {
            detail = (try? store.modelServices.connection(for: .polishing))?.name ?? L("连接配置不可用")
        } else {
            detail = L("本地模型")
        }
        return Node(id: "polishing", icon: "text.redaction", title: L("润色"), detail: detail,
                    state: store.isPolishing ? .busy : .ready,
                    hint: L("查看识别与润色设置")) { navigate(.polish) }
    }

    private var deliveryNode: Node {
        let granted = store.pastePermissionGranted
        let detail: String
        if !granted {
            detail = L("需要辅助功能权限")
        } else if let remote = store.remoteApplications.first {
            detail = "\(remote.name) · \(store.remotePasteTiming.title)"
        } else {
            detail = L("自动写入当前应用")
        }
        return Node(id: "delivery", icon: "text.cursor", title: L("写入"), detail: detail,
                    state: granted ? .ready : .attention,
                    hint: granted ? L("输入与远程") : L("允许文字写入")) {
            if granted { navigate(.shortcut) } else { store.requestPastePermission() }
        }
    }

    // MARK: Views

    private func accessibleState(_ state: NodeState) -> String {
        switch state {
        case .ready: L("已就绪")
        case .busy: L("正在处理")
        case .attention: L("待处理")
        case .off: L("关闭")
        }
    }

    private func color(_ state: NodeState) -> Color {
        switch state {
        case .ready: theme.accent
        case .busy: .secondary
        case .attention: theme.caution
        case .off: .secondary
        }
    }

    private func nodeView(_ node: Node) -> some View {
        Button(action: node.action) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    if node.state == .busy {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: node.icon).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(color(node.state))
                    }
                }
                .frame(width: 26, height: 26)
                .background(color(node.state).opacity(node.state == .off ? 0.06 : 0.12),
                            in: RoundedRectangle(cornerRadius: VoxInkTheme.Radius.control, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(node.title).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(node.state == .off ? Color.secondary : theme.ink)
                        if node.state == .attention {
                            Circle().fill(theme.caution).frame(width: 5, height: 5)
                        }
                    }
                    Text(node.detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .frame(minWidth: 128, maxWidth: .infinity, alignment: .leading)
            .background(node.state == .off ? Color.clear : theme.paper,
                        in: RoundedRectangle(cornerRadius: VoxInkTheme.Radius.control + 2, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VoxInkTheme.Radius.control + 2, style: .continuous)
                    .strokeBorder(node.state == .attention ? theme.caution.opacity(0.55) : theme.ink.opacity(0.08),
                                  style: StrokeStyle(lineWidth: 1, dash: node.state == .off ? [3, 3] : []))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!store.canStart)
        .help("\(node.detail) — \(node.hint)")
        .accessibilityLabel("\(node.title)，\(node.detail)")
        .accessibilityValue(accessibleState(node.state))
        .accessibilitySortPriority(Double(4 - (nodes.firstIndex { $0.id == node.id } ?? 0)))
        .accessibilityHint(node.hint)
    }

    /// The "landing point" between nodes: a hairline with a small ink drop in the middle.
    private var connector: some View {
        ZStack {
            Rectangle().fill(theme.ink.opacity(0.14)).frame(height: 1)
            Circle().fill(theme.accent.opacity(0.7)).frame(width: 4, height: 4)
        }
        .frame(width: 18)
        .accessibilityHidden(true)
    }

    // MARK: Privacy

    private var usesNetwork: Bool {
        store.modelServices.transcriptionID != nil || (store.polishingEnabled && store.modelServices.polishingID != nil)
    }

    private var privacyText: String {
        if usesNetwork { return L("音频或文字会发送到所选服务。") }
        if !store.remoteApplications.isEmpty { return L("音频在本机处理；文字会经远程工具的剪贴板同步到远端。") }
        return L("音频和文字都在本机处理。")
    }
}

/// Keycap rendering for shortcuts — part of 语落's visual signature.
struct Keycap: View {
    let title: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = VoxInkTheme(scheme: scheme)
        Text(title)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(theme.paper, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(theme.ink.opacity(0.16), lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.ink.opacity(0.12)).frame(height: 2).padding(.horizontal, 2)
            }
            .fixedSize()
            .accessibilityLabel(title)
    }
}
