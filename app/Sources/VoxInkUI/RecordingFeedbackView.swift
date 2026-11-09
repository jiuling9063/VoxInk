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
    /// The 60-second limit stopped this recording; the result stays in 语落 instead of being written.
    public let limitReached: Bool
    public let recovery: RecoveryAction?

    public init(phase: AppStore.Phase, status: String, target: String, elapsed: TimeInterval = 0,
                level: Float = 0, cancellationAvailable: Bool = false, isPolishing: Bool = false,
                limitReached: Bool = false, recovery: RecoveryAction? = nil) {
        self.isPolishing = isPolishing
        self.limitReached = limitReached; self.recovery = recovery
        self.phase = phase; self.status = status; self.target = target
        self.elapsed = elapsed; self.level = level; self.cancellationAvailable = cancellationAvailable
    }

    @MainActor init(store: AppStore) {
        self.init(phase: store.phase, status: store.status, target: store.shortcutTargetName ?? L("语落"),
                  elapsed: store.elapsed, level: store.level,
                  cancellationAvailable: store.cancellationShortcutAvailable, isPolishing: store.isPolishing,
                  limitReached: store.recordingLimitReached, recovery: store.recovery)
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
    var dismissAfter: Duration? {
        if busy { return nil }
        if phase == .failed { return .seconds(8) }
        return showsLimitNotice ? .seconds(5) : .zero
    }
    /// After the limit the HUD stays long enough to say the text was kept, not written.
    var showsLimitNotice: Bool { phase == .ready && limitReached }
    /// Seconds left, shown only in the last 10 seconds of a recording.
    var countdown: Int? {
        guard phase == .recording, safeElapsed >= 50 else { return nil }
        return max(1, 60 - safeElapsed)
    }
    /// One short line under "未写入" saying why, instead of a generic "see details".
    var failureTitle: String { recovery == .inspectClipboard ? L("已发送粘贴") : L("未写入") }

    var failureReason: String {
        switch recovery {
        case .checkTarget: L("请检查目标输入框")
        case .fieldUnavailable: L("无法检查输入框")
        case .pastePermission: L("需要辅助功能权限")
        case .microphone: L("需要麦克风权限")
        case .installModel, .reloadModel, .checkInstallation: L("模型未就绪")
        case .configureService: L("服务暂不可用")
        case .inspectClipboard: L("请检查剪贴板")
        case .deviceDisconnected: L("录音设备已断开")
        case .recordAgain, .chooseAudio: L("请重新录音")
        case nil: L("打开语落查看详情")
        }
    }
    var hint: String {
        switch phase {
        case .loading, .recording, .transcribing:
            cancellationAvailable ? L("Esc 取消") : L("打开语落窗口可取消")
        case .pasting:
            cancellationAvailable ? L("Esc 停止后续操作 · 已写入文字不会撤回") : L("打开语落可停止后续操作 · 已写入文字不会撤回")
        case .cancelling: L("正在结束处理，请稍候")
        case .failed: failureReason
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
    /// Amber that stays legible on the HUD's dark surface in both appearances.
    static let caution = Color(red: 0.902, green: 0.690, blue: 0.333)
    private let outline = RoundedRectangle(cornerRadius: 22)
    private let presentation: RecordingFeedbackPresentation
    private let copyUnwrittenText: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init(presentation: RecordingFeedbackPresentation, copyUnwrittenText: (() -> Void)? = nil) {
        self.presentation = presentation
        self.copyUnwrittenText = copyUnwrittenText
    }

    public var body: some View {
        ZStack {
            if presentation.phase == .recording {
                HStack(spacing: 6) {
                    OutwardPulse(level: presentation.safeLevel, reduceMotion: reduceMotion,
                                 width: presentation.countdown == nil ? 156 : 128)
                        .accessibilityLabel(L("麦克风音量"))
                        .accessibilityValue("\(Int(presentation.safeLevel * 100))%")
                    if let left = presentation.countdown {
                        Text(verbatim: "\(left)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(Self.caution)
                            .frame(minWidth: 20)
                            .accessibilityLabel(L("剩余 \(left) 秒"))
                    }
                }
            } else if presentation.showsLimitNotice {
                Text(L("已到 60 秒 · 未写入"))
                    .font(.caption.weight(.semibold)).foregroundStyle(Self.caution)
                    .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 12)
            } else if presentation.busy {
                HStack(spacing: 10) {
                    ProcessingDots(reduceMotion: reduceMotion).accessibilityLabel(L("正在处理"))
                    Text(presentation.phaseTitle).font(.caption).foregroundStyle(Color.white)
                }
            } else if presentation.phase == .failed {
                VStack(spacing: 5) {
                    Label(presentation.recovery == .fieldUnavailable && copyUnwrittenText != nil ? presentation.failureReason : presentation.failureTitle, systemImage: presentation.symbol)
                        .font(.caption.weight(.semibold)).foregroundStyle(Self.caution)
                    if presentation.recovery == .fieldUnavailable, let copyUnwrittenText {
                        Button(L("复制结果"), action: copyUnwrittenText)
                            .font(.callout.weight(.medium)).buttonStyle(.bordered)
                            .accessibilityHint(L("复制识别结果后，在目标输入框手动粘贴。"))
                    } else {
                        Text(presentation.failureReason)
                            .font(.system(size: 11)).foregroundStyle(Color.white)
                            .lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal, 12)
                    }
                }
            } else {
                Image(systemName: presentation.symbol)
                    .foregroundStyle(presentation.phase == .failed ? Color.orange : Color.white.opacity(0.72))
                    .accessibilityLabel(presentation.status)
            }
        }
        .frame(height: presentation.panelHeight)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: presentation.recovery == .fieldUnavailable && copyUnwrittenText != nil ? .contain : .combine)
        .accessibilityValue(presentation.accessibilityStatus)
        .accessibilityHint(presentation.hint)
        .background(Color(red: 0.106, green: 0.133, blue: 0.137), in: outline)
        .overlay {
            outline
                .strokeBorder(presentation.countdown != nil ? Self.caution.opacity(0.85)
                        : Color(red: 0.522, green: 0.808, blue: 0.780).opacity(0.3),
                        lineWidth: presentation.countdown != nil ? 1.5 : 1)
        }
        .overlay {
            if presentation.phase == .ready && !reduceMotion {
                outline.strokeBorder(Color(red: 0.49, green: 0.68, blue: 0.61).opacity(0.55), lineWidth: 1.2)
            }
        }
        .clipShape(outline)
    }
}

private struct OutwardPulse: View {
    let level: Double
    let reduceMotion: Bool
    var width: CGFloat = 156
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
        .frame(width: width, height: 36)
        .onAppear { smoothedLevel = level }
    }
}

private struct ProcessingDots: View {
    let reduceMotion: Bool
    var body: some View {
        if reduceMotion {
            dots(time: nil)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 24)) { context in
                dots(time: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func dots(time: TimeInterval?) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                let pulse = time.map { (1 + cos($0 * 5 - Double(index) * 0.8)) / 2 } ?? 1
                Circle().fill(Color(red: 96 / 255, green: 224 / 255, blue: 202 / 255)
                    .opacity(0.35 + 0.55 * pulse))
                    .frame(width: 5, height: 5)
            }
        }
    }
}
