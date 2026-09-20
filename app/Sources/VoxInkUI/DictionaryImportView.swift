import SwiftUI
import UniformTypeIdentifiers
import VoxInkCore

struct DictionaryCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw UserDictionaryCSV.FormatError.invalid }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct DictionaryImportView: View {
    @ObservedObject var controller: UserDictionaryController
    let preview: UserDictionaryController.ImportPreview
    let canEdit: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入预览").font(.title2.bold())
            Text("新增 \(preview.additions.count) · 重复 \(preview.duplicates) · 冲突 \(preview.conflicts) · 无效 \(preview.invalid)")
                .font(.callout).foregroundStyle(.secondary)
            Text("仅合并下方新增词条；重复、冲突和无效项跳过，已有词条保持原样。")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(preview.additions) { entry in
                        HStack { Text(entry.source); Image(systemName: "arrow.right").foregroundStyle(.secondary); Text(entry.replacement); Spacer() }
                    }
                    ForEach(Array(preview.notices.enumerated()), id: \.offset) { _, notice in
                        Text(notice).font(.caption).foregroundStyle(.orange)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 260)
            if let error = preview.blockingError ?? controller.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).disabled(controller.isUpdating)
                Button(controller.isUpdating ? "正在导入…" : "导入 \(preview.additions.count) 条") {
                    Task { if await controller.importConfirmed(preview) { dismiss() } }
                }.keyboardShortcut(.defaultAction)
                    .disabled(!canEdit || controller.isUpdating || preview.additions.isEmpty || preview.blockingError != nil)
            }
        }.padding(24).frame(width: 520)
    }
}
