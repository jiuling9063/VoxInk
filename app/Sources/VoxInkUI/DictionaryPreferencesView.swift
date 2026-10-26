import SwiftUI
import UniformTypeIdentifiers
import VoxInkCore

struct DictionaryPreferencesView: View {
    @ObservedObject var controller: UserDictionaryController
    let canEdit: Bool
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focusedField: EditorField?
    private enum EditorField { case source, replacement, preview }
    @State private var editing = false
    @State private var editingID: UUID?
    @State private var source = ""
    @State private var replacement = ""
    @State private var testText = L("请打开雨落。")

    @State private var choosingImport = false
    @State private var importPreview: UserDictionaryController.ImportPreview?
    @State private var fileError: String?
    @State private var exporting = false
    @State private var exportDocument = DictionaryCSVDocument(data: Data())
    @State private var exportName = L("VoxInk-纠正词库")

    var body: some View {
        WorkspaceForm {
            Section(L("纠正专有词")) {
                Text(L("记住正确写法，例如：雨落 → 语落。下次识别时自动纠正。"))
                    .font(.callout).foregroundStyle(.secondary)
                DisclosureGroup(L("匹配规则")) {
                    Text(L("词条仅在本机保存，用于识别后的文字纠正。匹配完整词语，区分英文大小写；数字、网址、路径和代码保持原样。"))
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
                if let error = controller.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.orange)
                }
                if !controller.isReady {
                    Button(L("重新读取词典")) { Task { await controller.load() } }.disabled(controller.isUpdating)
                }
                HStack {
                    Text(L("\(controller.entries.count) / 100 条")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if controller.isUpdating { ProgressView().controlSize(.small) }
                    WorkspaceMenu(title: L("词库文件"), value: L("词库文件")) {
                        Button(L("导入 CSV…")) { choosingImport = true }
                            .disabled(!canEdit || !controller.isReady || controller.isUpdating)
                        Button(L("导出词库…")) {
                            exportDocument = DictionaryCSVDocument(data: UserDictionaryCSV.encode(controller.entries))
                            exportName = L("VoxInk-纠正词库"); exporting = true
                        }.disabled(!controller.isReady || controller.isUpdating)
                        Button(L("保存导入模板…")) {
                            let example = try? UserDictionaryEntry(source: L("雨落"), replacement: L("语落"))
                            exportDocument = DictionaryCSVDocument(data: UserDictionaryCSV.encode(example.map { [$0] } ?? []))
                            exportName = L("VoxInk-纠正词模板"); exporting = true
                        }
                    }.fixedSize()
                    Button(L("添加纠正词"), systemImage: "plus") { beginEditing(nil) }
                        .disabled(!canEdit || !controller.isReady || controller.isUpdating || controller.entries.count >= 100)
                }
                Divider()
                if controller.entries.isEmpty {
                    Text(L("还没有纠正词，遇到需要固定写法的姓名或产品名时再添加。"))
                        .font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                }
                ForEach(controller.entries) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 12) {
                                Text(entry.source).frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                                Text(entry.replacement).foregroundStyle(VoxInkTheme(scheme: scheme).accent)
                                    .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.source)
                                Label(entry.replacement, systemImage: "arrow.turn.down.right")
                                    .foregroundStyle(VoxInkTheme(scheme: scheme).accent)
                            }
                        }
                        Button(L("编辑")) { beginEditing(entry) }
                        Button(L("删除"), role: .destructive) { Task { await controller.remove(entry.id) } }
                    }.font(.callout).disabled(!canEdit || controller.isUpdating)
                    if entry.id != controller.entries.last?.id { Divider() }
                }
            }
            Section(L("文字预览")) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) { previewFields }
                    VStack(alignment: .leading, spacing: 16) { previewFields }
                }
                Text(L("预览最多 2000 个字符，只展示文字，不录音、不粘贴，也不保存这句话。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
            .sheet(isPresented: $editing) { editor }
            .sheet(item: $importPreview) { preview in
                DictionaryImportView(controller: controller, preview: preview, canEdit: canEdit)
            }
            .fileImporter(isPresented: $choosingImport, allowedContentTypes: [.commaSeparatedText]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: UserDictionaryCSV.maximumBytes + 1) ?? Data()
                    controller.clearEditingError()
                    importPreview = try controller.previewImport(data)
                } catch { fileError = error.localizedDescription }
            }
            .fileExporter(isPresented: $exporting, document: exportDocument,
                          contentType: .commaSeparatedText, defaultFilename: exportName) { result in
                if case .failure(let error) = result { fileError = error.localizedDescription }
            }
            .alert(L("词库文件"), isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
                Button(L("好"), role: .cancel) { fileError = nil }
            } message: { Text(fileError ?? "") }
    }

    @ViewBuilder private var previewFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("识别原文")).font(.caption).foregroundStyle(.secondary)
            TextField(L("试写一句包含纠正词的话"), text: $testText, axis: .vertical).lineLimit(3...6)
                .frame(minHeight: 64, alignment: .topLeading)
                .focused($focusedField, equals: .preview)
                .modifier(WorkspaceInputSurface(focused: focusedField == .preview))
                .onChange(of: testText) { _, text in
                    if text.count > 2000 { testText = String(text.prefix(2000)) }
                }
        }.frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)
        VStack(alignment: .leading, spacing: 8) {
            Text(L("纠正结果")).font(.caption).foregroundStyle(.secondary)
            Text(LanguageTextProcessor.process(String(testText.prefix(2000)), language: .automatic, output: .original, dictionary: controller.rules).text)
                .textSelection(.enabled).font(.callout)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading).padding(12)
                .background(VoxInkTheme(scheme: scheme).accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }.frame(minWidth: 190, maxWidth: .infinity, alignment: .leading)
    }

    private func beginEditing(_ entry: UserDictionaryEntry?) {
        controller.clearEditingError()
        editingID = entry?.id; source = entry?.source ?? ""; replacement = entry?.replacement ?? ""
        editing = true
    }

    private var editor: some View {
        let candidate = try? controller.candidate(source: source, replacement: replacement, id: editingID ?? UUID())
        return VStack(alignment: .leading, spacing: 16) {
            WorkspaceHeading(title: editingID == nil ? L("添加纠正词") : L("编辑纠正词"),
                             subtitle: L("为常用词设置准确的写法。"))
            Text(L("识别词")).font(.caption).foregroundStyle(.secondary)
            TextField(L("识别词，例如：雨落"), text: $source)
                .focused($focusedField, equals: .source)
                .modifier(WorkspaceInputSurface(focused: focusedField == .source))
            Text(L("正确写法")).font(.caption).foregroundStyle(.secondary)
            TextField(L("正确写法，例如：语落"), text: $replacement)
                .focused($focusedField, equals: .replacement)
                .modifier(WorkspaceInputSurface(focused: focusedField == .replacement))
            if let candidate {
                Text(L("保存为：\(candidate.source) → \(candidate.replacement)")).font(.callout).foregroundStyle(.secondary)
            } else if !source.isEmpty || !replacement.isEmpty {
                Text(validationMessage).font(.caption).foregroundStyle(.orange)
            } else {
                Text(L("请填写完整词语，每项最多 64 个字符。保存时保留原有字形。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = controller.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button(L("取消")) { editing = false }.keyboardShortcut(.cancelAction).disabled(controller.isUpdating)
                Button(controller.isUpdating ? L("正在保存…") : L("保存")) {
                    Task {
                        if await controller.save(source: source, replacement: replacement, id: editingID) { editing = false }
                    }
                }.keyboardShortcut(.defaultAction)
                    .buttonStyle(VoxInkButtonStyle(prominent: true))
                    .disabled(candidate == nil || !canEdit || controller.isUpdating)
            }
        }.padding(28).frame(width: 420)
            .background(VoxInkTheme(scheme: scheme).background)
            .onAppear { focusedField = .source }
    }

    private var validationMessage: String {
        do { _ = try controller.candidate(source: source, replacement: replacement); return "" }
        catch { return error.localizedDescription }
    }
}
