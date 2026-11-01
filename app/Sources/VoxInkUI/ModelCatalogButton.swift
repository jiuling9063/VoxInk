import SwiftUI
import VoxInkCore

struct ModelCatalogButton: View {
    let connection: ModelConnection
    var apiKey = ""
    var clearKey = false
    var sourceID: UUID?
    let load: () async throws -> ModelCatalogResult
    let select: (String) -> Void
    @State private var presented = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(L("获取模型")) { presented = true }
            .buttonStyle(.plain).foregroundStyle(.tint)
            .disabled(clearKey)
            .popover(isPresented: $presented, arrowEdge: .bottom) {
                ModelCatalogList(connection: connection, load: load) { model in
                    select(model)
                    presented = false
                }.onExitCommand { presented = false }
            }
            .onChange(of: connection.id) { presented = false }
            .onChange(of: connection.baseURL) { presented = false }
            .onChange(of: connection.purpose) { presented = false }
            .onChange(of: connection.timeoutSeconds) { presented = false }
            .onChange(of: apiKey) { presented = false }
            .onChange(of: clearKey) { presented = false }
            .onChange(of: sourceID) { presented = false }
            .onChange(of: enabled) { if !enabled { presented = false } }
    }
}

private struct ModelCatalogList: View {
    let connection: ModelConnection
    let load: () async throws -> ModelCatalogResult
    let select: (String) -> Void
    @State private var result = ModelCatalogResult()
    @State private var search = ""
    @State private var loading = true
    @State private var error = ""
    @State private var attempt = 0
    @State private var showUnclassified = false
    @FocusState private var searchFocused: Bool

    private func filtered(_ models: [String]) -> [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? models : models.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if loading {
                HStack { ProgressView().controlSize(.small); Text(L("正在获取模型…")) }
                    .frame(maxWidth: .infinity, minHeight: 80)
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
                    }.frame(height: min(280, CGFloat(known.count + (showUnclassified ? unknown.count : 0)) * 38 + (unknown.isEmpty ? 0 : 28)))
                }
            }
        }
        .padding(16).frame(width: 380)
        .task(id: attempt) {
            loading = true; error = ""
            do {
                let result = try await load()
                try Task.checkCancellation()
                self.result = result
                showUnclassified = result.models.isEmpty
                loading = false
                searchFocused = true
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

    @ViewBuilder private var documentationLink: some View {
        if let url = ModelCatalog.documentationURL(for: connection) {
            Link(L("查看服务商文档"), destination: url).font(.caption)
        }
    }

    private func rows(_ models: [String]) -> some View {
        ForEach(models, id: \.self) { model in
            Button { select(model) } label: {
                HStack(spacing: 8) {
                    Text(model).font(.system(size: 12, design: .monospaced))
                        .lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark").opacity(connection.model == model ? 1 : 0)
                }.padding(8).contentShape(Rectangle())
            }
            .buttonStyle(.borderless).help(model)
            .accessibilityValue(connection.model == model ? L("已选用") : "")
        }
    }
}
