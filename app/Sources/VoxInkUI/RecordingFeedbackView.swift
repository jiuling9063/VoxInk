import SwiftUI

public struct RecordingFeedbackPresentation {
    public let phase: AppStore.Phase
    public let status: String
    public let target: String
    public let elapsed: TimeInterval
    public let level: Float
    public let cancellationAvailable: Bool

    public init(phase: AppStore.Phase, status: String, target: String, elapsed: TimeInterval = 0,
                level: Float = 0, cancellationAvailable: Bool = false) {
        self.phase = phase; self.status = status; self.target = target
        self.elapsed = elapsed; self.level = level; self.cancellationAvailable = cancellationAvailable
    }

    @MainActor init(store: AppStore) {
        self.init(phase: store.phase, status: store.status, target: store.shortcutTargetName ?? "语落",
                  elapsed: store.elapsed, level: store.level,
                  cancellationAvailable: store.cancellationShortcutAvailable)
    }

    var busy: Bool { phase != .ready && phase != .failed }
    var dismissAfter: Duration? { busy ? nil : .seconds(phase == .failed ? 8 : 3) }
    var hint: String {
        switch phase {
        case .loading, .recording, .transcribing:
            cancellationAvailable ? "Esc 取消" : "打开语落窗口可取消"
        case .pasting:
            cancellationAvailable ? "Esc 停止后续操作 · 已写入文字不会撤回" : "打开语落可停止后续操作 · 已写入文字不会撤回"
        case .cancelling: "正在结束处理，请稍候"
        case .failed: "打开语落查看处理方法"
        case .ready: ""
        }
    }
    var symbol: String {
        switch phase {
        case .recording: "mic.fill"
        case .failed: "exclamationmark.circle.fill"
        default: "waveform"
        }
    }
    var safeElapsed: Int { elapsed.isFinite ? Int(min(max(elapsed, 0), 60)) : 0 }
    var safeLevel: Double { level.isFinite ? Double(min(max(level, 0), 1)) : 0 }
}

public struct RecordingFeedbackView: View {
    private let presentation: RecordingFeedbackPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(presentation: RecordingFeedbackPresentation) { self.presentation = presentation }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: presentation.symbol)
                    .foregroundStyle(presentation.phase == .failed ? Color.orange : Color(red: 0.33, green: 0.49, blue: 0.52))
                    .accessibilityHidden(true)
                Text(presentation.target).fontWeight(.semibold).lineLimit(2)
                Spacer(minLength: 8)
                if presentation.phase == .recording {
                    Text("\(presentation.safeElapsed) / 60 秒").monospacedDigit().fixedSize()
                }
            }
            Text(presentation.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("feedbackStatus")
            if presentation.phase == .recording {
                ProgressView(value: presentation.safeLevel).tint(Color(red: 0.43, green: 0.64, blue: 0.65))
                    .accessibilityLabel("麦克风音量")
            } else if presentation.busy {
                ProgressView().controlSize(.small).accessibilityLabel("正在处理")
            }
            if !presentation.hint.isEmpty {
                Text(presentation.hint).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.38), lineWidth: 0.8)
        }
        .shadow(color: Color(red: 0.20, green: 0.34, blue: 0.35).opacity(0.16), radius: 14, y: 7)
        .overlay {
            if presentation.phase == .ready && !reduceMotion {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(red: 0.49, green: 0.68, blue: 0.61).opacity(0.55), lineWidth: 1.2)
            }
        }
    }
}
