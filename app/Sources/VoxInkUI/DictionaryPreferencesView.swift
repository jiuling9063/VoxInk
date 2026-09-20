import SwiftUI
import VoxInkCore

struct DictionaryPreferencesView: View {
    @ObservedObject var controller: UserDictionaryController
    let canEdit: Bool
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focusedField: EditorField?
    private enum EditorField { case source, replacement }
    @State private var editing = false
    @State private var editingID: UUID?
    @State private var source = ""
    @State private var replacement = ""
    @State private var testText = "请打开雨落。"

    var body: some View {
        WorkspaceForm {
            Section("纠正专有词") {
                Text("记住正确写法，例如：雨落 → 语落。下次识别时自动纠正。")
                    .font(.callout).foregroundStyle(.secondary)
                DisclosureGroup("匹配规则") {
                    Text("词条仅在本机保存，用于识别后的文字纠正。匹配完整词语，区分英文大小写；数字、网址、路径和代码保持原样。")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
                if let error = controller.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.orange)
                }
                if !controller.isReady {
                    Button("重新读取词典") { Task { await controller.load() } }.disabled(controller.isUpdating)
                }
                HStack {
                    Text("\(controller.entries.count) / 100 条").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if controller.isUpdating { ProgressView().controlSize(.small) }
                    Button("添加纠正词", systemImage: "plus") { beginEditing(nil) }
                        .disabled(!canEdit || !controller.isReady || controller.isUpdating || controller.entries.count >= 100)
                }
            }
            Section("已保存词条") {
                if controller.entries.isEmpty {
                    Text("还没有纠正词，遇到需要固定写法的姓名或产品名时再添加。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(controller.entries) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.source).font(.callout)
                            Label(entry.replacement, systemImage: "arrow.turn.down.right")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("编辑") { beginEditing(entry) }
                        Button("删除", role: .destructive) { Task { await controller.remove(entry.id) } }
                    }.disabled(!canEdit || controller.isUpdating)
                }
            }
            Section("文字预览") {
                TextField("试写一句包含纠正词的话", text: $testText, axis: .vertical).lineLimit(1...3)
                    .onChange(of: testText) { _, text in
                        if text.count > 2000 { testText = String(text.prefix(2000)) }
                    }
                Text(DeterministicTextProcessor.shared.process(String(testText.prefix(2000)), dictionary: controller.rules).text)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .font(.callout).padding(.vertical, 6)
                Text("预览最多 2000 个字符，只展示文字，不录音、不粘贴，也不保存这句话。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
            .sheet(isPresented: $editing) { editor }
    }

    private func beginEditing(_ entry: UserDictionaryEntry?) {
        controller.clearEditingError()
        editingID = entry?.id; source = entry?.source ?? ""; replacement = entry?.replacement ?? ""
        editing = true
    }

    private var editor: some View {
        let candidate = try? controller.candidate(source: source, replacement: replacement, id: editingID ?? UUID())
        return VStack(alignment: .leading, spacing: 16) {
            WorkspaceHeading(title: editingID == nil ? "添加纠正词" : "编辑纠正词",
                             subtitle: "为常用词设置准确的写法。")
            Text("识别词").font(.caption).foregroundStyle(.secondary)
            TextField("识别词，例如：雨落", text: $source).textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .source)
            Text("正确写法").font(.caption).foregroundStyle(.secondary)
            TextField("正确写法，例如：语落", text: $replacement).textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .replacement)
            if let candidate {
                Text("保存为：\(candidate.source) → \(candidate.replacement)").font(.callout).foregroundStyle(.secondary)
            } else if !source.isEmpty || !replacement.isEmpty {
                Text(validationMessage).font(.caption).foregroundStyle(.orange)
            } else {
                Text("请填写完整词语，每项最多 64 个字符。保存时统一为简体写法。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = controller.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button("取消") { editing = false }.keyboardShortcut(.cancelAction).disabled(controller.isUpdating)
                Button("保存") {
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
