import SwiftUI
import VoxInkCore

struct ModelCatalogButton: View {
    let connection: ModelConnection
    var apiKey = ""
    var canLoad = true
    var sourceID: UUID?
    var fillsField = false
    let load: () async throws -> ModelCatalogResult
    let select: (String) -> Void
    @State private var presented = false
    @Environment(\.isEnabled) private var enabled

    @State private var hovering = false
    @FocusState private var focused: Bool

    private var modelTitle: String { connection.model.isEmpty ? L("选择模型") : connection.model }

    var body: some View {
        Button { presented = true } label: {
            if fillsField {
                let name = ModelProviderPreset.matching(connection).modelTitle(for: connection.model, purpose: connection.purpose)
                ServiceChoiceLabel(value: name ?? modelTitle, modelID: name == nil && !connection.model.isEmpty)
            } else {
                HStack(spacing: 8) {
                    Text(modelTitle)
                        .lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.caption2).accessibilityHidden(true)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .contentShape(Rectangle())
            }
        }
            .buttonStyle(.plain)
            .modifier(WorkspaceChoiceSurface(hovering: hovering, focused: focused, enabled: enabled))
            .onHover { hovering = $0 }.focused($focused)
            .accessibilityLabel(connection.purpose == .transcription ? L("识别模型 ID") : L("润色模型 ID"))
            .accessibilityValue(connection.model)
            .help(modelTitle)
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                ModelCatalogList(connection: connection, provider: .matching(connection), canLoad: canLoad, load: load) { model in
                    select(model)
                    presented = false
                }.onExitCommand { presented = false }
            }
            .onChange(of: connection.id) { presented = false }
            .onChange(of: connection.baseURL) { presented = false }
            .onChange(of: connection.polishingProtocol) { presented = false }
            .onChange(of: connection.purpose) { presented = false }
            .onChange(of: connection.timeoutSeconds) { presented = false }
            .onChange(of: apiKey) { presented = false }
            .onChange(of: canLoad) { presented = false }
            .onChange(of: sourceID) { presented = false }
            .onChange(of: enabled) { if !enabled { presented = false } }
    }
}

private struct ModelCatalogList: View {
    let connection: ModelConnection
    let provider: ModelProviderPreset
    let canLoad: Bool
    let load: () async throws -> ModelCatalogResult
    let select: (String) -> Void
    @State private var result = ModelCatalogResult()
    @State private var search = ""
    @State private var manual = false
    @State private var modelID = ""
    @State private var loading = true
    @State private var error = ""
    @State private var attempt = 0
    @State private var showUnclassified = false
    @FocusState private var searchFocused: Bool

    private func filtered(_ models: [String]) -> [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? models : models.filter { id in
            id.localizedCaseInsensitiveContains(query)
                || provider.modelTitle(for: id, purpose: connection.purpose)?.localizedCaseInsensitiveContains(query) == true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if manual {
                TextField(L("模型 ID"), text: $modelID)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onSubmit { useManualID() }
                Button(L("使用此 ID")) { useManualID() }
                    .disabled(!ModelCatalog.validID(trimmedID))
            } else if !canLoad {
                Text(L("请先填写连接信息以获取模型列表。")).font(.callout).foregroundStyle(.secondary)
            } else if loading {
                HStack { ProgressView().controlSize(.small); Text(L("正在获取模型…")) }
                    .frame(maxWidth: .infinity, minHeight: 55)
            } else if !error.isEmpty {
                Text(error).font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button(L("重试")) { attempt += 1 }
                    Spacer()
                    documentationLink
                }
            } else if result.isEmpty {
                Text(L("未找到适用模型，可直接输入模型 ID。"))
                    .font(.callout).foregroundStyle(.secondary)
                documentationLink
            } else {
                TextField(L("搜索模型"), text: $search).textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onChange(of: search) { if !search.isEmpty { showUnclassified = true } }
                let known = filtered(result.models)
                let unknown = filtered(result.unclassified)
                if known.isEmpty && unknown.isEmpty {
                    Text(L("没有匹配的模型")).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            rows(known)
                            if !unknown.isEmpty {
                                DisclosureGroup(L("用途未标注（\(unknown.count)）"), isExpanded: $showUnclassified) {
                                    rows(unknown)
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.frame(height: min(280, CGFloat(known.count + (showUnclassified ? unknown.count : 0)) * 46 + (unknown.isEmpty ? 0 : 28)))
                }
            }
            if !manual {
                Divider()
                Button(L("手动输入模型 ID…")) {
                    modelID = connection.model
                    manual = true
                    searchFocused = true
                }
                .buttonStyle(.link)
            }
        }
        .padding(16).frame(width: 380)
        .task(id: attempt) {
            guard canLoad else { return }
            loading = true; error = ""
            do {
                let result = try await load()
                try Task.checkCancellation()
                self.result = result
                showUnclassified = result.models.isEmpty
                loading = false
                if !manual { searchFocused = true }
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                if error as? ModelCatalogError == .unsupported,
                   ModelProviderPreset.matching(connection) == .volcengine {
                    self.error = L("此接口不支持直接列出模型。火山方舟的模型管理接口需要独立的 Access Key，可在官方文档中查看模型 ID。")
                } else {
                    self.error = error.localizedDescription
                }
                loading = false
            }
        }
    }

    private var trimmedID: String { modelID.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func useManualID() {
        guard ModelCatalog.validID(trimmedID) else { return }
        select(trimmedID)
    }

    @ViewBuilder private var documentationLink: some View {
        if let url = ModelCatalog.documentationURL(for: connection) {
            Link(L("查看服务商文档"), destination: url).font(.caption)
        }
    }

    private func rows(_ models: [String]) -> some View {
        ForEach(models, id: \.self) { model in
            Button { select(model) } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = provider.modelTitle(for: model, purpose: connection.purpose) {
                            Text(title).font(.body.weight(.medium))
                            Text(model).font(.caption.monospaced()).foregroundStyle(.secondary)
                        } else {
                            Text(model).font(.system(size: 12, design: .monospaced))
                        }
                    }.lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark").opacity(connection.model == model ? 1 : 0)
                }.padding(8).contentShape(Rectangle())
            }
            .buttonStyle(.borderless).help(model)
            .accessibilityValue(connection.model == model ? L("已选用") : "")
        }
    }
}
