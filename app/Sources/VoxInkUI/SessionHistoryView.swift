import SwiftUI

struct SessionTranscript: Identifiable {
    let id = UUID()
    let text: String
    let date: Date
}

struct SessionHistoryView: View {
    @Environment(\.colorScheme) private var scheme
    private var theme: VoxInkTheme { VoxInkTheme(scheme: scheme) }
    @ObservedObject var store: AppStore
    let statistics: Bool
    @State private var copyStatus = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            WorkspaceHeading(title: statistics ? "使用统计" : "转录历史",
                             subtitle: statistics ? "查看本次使用的识别次数与文字量。" : "说过的话，随时拾起。")
                .padding(.bottom, 4)
            if statistics {
                HStack(spacing: 14) {
                    metric("成功识别", value: store.sessionHistory.count, unit: "次", icon: "waveform")
                    metric("识别字符", value: store.sessionHistory.reduce(0) { $0 + $1.text.count }, unit: "字符", icon: "textformat.abc")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Label("关于这些数字", systemImage: "chart.bar.xaxis").font(.headline)
                    Text("每次非空识别计为一次，包含导入与重试；不代表已成功写入目标应用。")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(22).writingSurface()
            } else if store.sessionHistory.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 30, weight: .light))
                        .foregroundStyle(theme.accent).frame(width: 70, height: 70)
                        .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                    Text("从第一句话开始").font(.title3.weight(.semibold))
                    Text("完成一次录音或导入后，\n识别结果会按时间保留在这里。")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, minHeight: 270).writingSurface()
            } else {
                HStack {
                    Text("\(store.sessionHistory.count) 条转录").font(.caption.weight(.medium))
                    Spacer()
                    Text(copyStatus).font(.caption).foregroundStyle(.secondary)
                }
                LazyVStack(spacing: 12) {
                    ForEach(store.sessionHistory) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(entry.date.formatted(date: .abbreviated, time: .shortened), systemImage: "waveform")
                                    .font(.caption).foregroundStyle(theme.accent)
                                Spacer()
                                Button("复制") { copyStatus = store.copyHistory(entry) ? "已复制" : "复制失败，请重试" }
                                    .disabled(!store.canStart)
                            }
                            Text(entry.text).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(18).writingSurface()
                    }
                }
            }
            Label("仅统计本次启动期间的结果，退出 App 后清除。", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ title: String, value: Int, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Label(title, systemImage: icon).font(.callout).foregroundStyle(theme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value.formatted()).font(.system(size: 36, weight: .semibold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22).writingSurface()
    }
}
