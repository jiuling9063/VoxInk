import SwiftUI

struct SessionTranscript: Identifiable {
    let id = UUID()
    let text: String
    let date: Date
}

struct SessionHistoryView: View {
    @ObservedObject var store: AppStore
    let statistics: Bool
    @State private var copyStatus = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(statistics ? "本次使用统计" : "转录历史").font(.largeTitle.bold())
            Text("仅保留本次启动期间的识别结果，退出 App 后清除。").foregroundStyle(.secondary)
            if statistics {
                LabeledContent("成功识别", value: "\(store.sessionHistory.count) 次")
                LabeledContent("识别字符", value: "\(store.sessionHistory.reduce(0) { $0 + $1.text.count })")
                Text("每次非空识别计为一次，包含导入与重试；不代表已成功写入目标应用。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if store.sessionHistory.isEmpty {
                ContentUnavailableView("还没有转录记录", systemImage: "clock", description: Text("完成一次录音或导入后，结果会出现在这里。"))
            } else {
                Text(copyStatus).font(.caption).foregroundStyle(.secondary)
                LazyVStack(spacing: 12) {
                    ForEach(store.sessionHistory) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(entry.date, style: .time).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("复制") { copyStatus = store.copyHistory(entry) ? "已复制" : "复制失败，请重试" }
                                    .disabled(!store.canStart)
                            }
                            Text(entry.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(18).writingSurface()
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
