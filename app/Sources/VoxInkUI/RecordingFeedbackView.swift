import VoxInkCore
import SwiftUI

public struct RecordingFeedbackPresentation {
    public let phase: AppStore.Phase
    public let status: String
    public let target: String
    public let elapsed: TimeInterval
    public let level: Float
    public let cancellationAvailable: Bool
    public let isPolishing: Bool

    public init(phase: AppStore.Phase, status: String, target: String, elapsed: TimeInterval = 0,
                level: Float = 0, cancellationAvailable: Bool = false, isPolishing: Bool = false) {
        self.isPolishing = isPolishing
        self.phase = phase; self.status = status; self.target = target
        self.elapsed = elapsed; self.level = level; self.cancellationAvailable = cancellationAvailable
    }

    @MainActor init(store: AppStore) {
        self.init(phase: store.phase, status: store.status, target: store.shortcutTargetName ?? L("语落"),
                  elapsed: store.elapsed, level: store.level,
                  cancellationAvailable: store.cancellationShortcutAvailable, isPolishing: store.isPolishing)
    }

    var phaseTitle: String {
        if isPolishing { return L("润色中") }
        switch phase {
        case .loading: return L("准备中")
        case .recording: return L("录音中")
        case .transcribing: return L("识别中")
        case .pasting: return L("写入中")
        case .cancelling: return L("取消中")
        case .failed: return L("未完成")
        case .ready: return L("已就绪")
        }
    }
    var accessibilityStatus: String {
        phase == .recording ? L("\(status)，麦克风音量 \(Int(safeLevel * 100))%") : status
    }
    var panelHeight: CGFloat { phase == .failed ? 60 : 44 }
    var busy: Bool { phase != .ready && phase != .failed }
    var dismissAfter: Duration? { busy ? nil : .seconds(phase == .failed ? 8 : 0) }
    var hint: String {
        switch phase {
        case .loading, .recording, .transcribing:
            cancellationAvailable ? L("Esc 取消") : L("打开语落窗口可取消")
        case .pasting:
            cancellationAvailable ? L("Esc 停止后续操作 · 已写入文字不会撤回") : L("打开语落可停止后续操作 · 已写入文字不会撤回")
        case .cancelling: L("正在结束处理，请稍候")
        case .failed: L("打开语落查看处理方法")
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
        ZStack {
            if presentation.phase == .recording {
                OutwardPulse(level: presentation.safeLevel, reduceMotion: reduceMotion)
                    .accessibilityLabel(L("麦克风音量"))
                    .accessibilityValue("\(Int(presentation.safeLevel * 100))%")
            } else if presentation.busy {
                HStack(spacing: 10) {
                    ProcessingDots(reduceMotion: reduceMotion).accessibilityLabel(L("正在处理"))
                    Text(presentation.phaseTitle).font(.caption).foregroundStyle(Color.white)
                }
            } else if presentation.phase == .failed {
                VStack(spacing: 5) {
                    Label(L("未完成"), systemImage: presentation.symbol)
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Text(L("打开语落查看详情"))
                        .font(.system(size: 11)).foregroundStyle(Color.white)
                }
            } else {
                Image(systemName: presentation.symbol)
                    .foregroundStyle(presentation.phase == .failed ? Color.orange : Color.white.opacity(0.72))
                    .accessibilityLabel(presentation.status)
            }
        }
        .frame(height: presentation.panelHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityValue(presentation.accessibilityStatus)
        .accessibilityHint(presentation.hint)
        .background(Color(red: 0.10, green: 0.12, blue: 0.13), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 8, y: 4)
        .overlay {
            if presentation.phase == .ready && !reduceMotion {
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color(red: 0.49, green: 0.68, blue: 0.61).opacity(0.55), lineWidth: 1.2)
            }
        }
    }
}

private struct OutwardPulse: View {
    let level: Double
    let reduceMotion: Bool
    @State private var started = Date()
    @State private var smoothedLevel = 0.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            Canvas { graphics, size in
                for index in -14...14 {
                    let sample = RecordingPulse.sample(index: index,
                        time: context.date.timeIntervalSince(started), level: reduceMotion ? level : smoothedLevel,
                        reduceMotion: reduceMotion)
                    let x = size.width / 2 + Double(index) * 5.3 * size.width / 190
                    let height = sample.height * size.height / 44
                    let color = Color(red: (96 + 65 * sample.intensity) / 255,
                                      green: (224 + 25 * sample.intensity) / 255,
                                      blue: (202 + 29 * sample.intensity) / 255)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height / 2 - height / 2))
                    path.addLine(to: CGPoint(x: x, y: size.height / 2 + height / 2))
                    graphics.stroke(path, with: .color(color.opacity(sample.opacity)),
                                    style: StrokeStyle(lineWidth: 3 * size.width / 190, lineCap: .round))
                }
            }
            .onChange(of: context.date) { old, new in
                let delta = min(0.1, max(0, new.timeIntervalSince(old)))
                smoothedLevel += (level - smoothedLevel) * (1 - exp(-delta * 7))
            }
        }
        .frame(width: 156, height: 36)
        .onAppear { smoothedLevel = level }
    }
}

private struct ProcessingDots: View {
    let reduceMotion: Bool
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                Circle().fill(Color(red: 96 / 255, green: 224 / 255, blue: 202 / 255)
                    .opacity(reduceMotion ? 0.9 : 0.65 + Double(index) * 0.08))
                    .frame(width: 5, height: 5)
            }
        }
    }
}
