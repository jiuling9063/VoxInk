import SwiftUI
import VoxInkCore

struct ModelCatalogButton: View {
    let connection: ModelConnection
    var apiKey = ""
    var clearKey = false
    var sourceID: UUID?
    let load: () async throws -> [String]
    let select: (String) -> Void
    @State private var presented = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        if ModelCatalog.supports(connection) {
            Button(L("获取模型")) { presented = true }
                .buttonStyle(.plain).foregroundStyle(.tint)
                .disabled(clearKey)
                .popover(isPresented: $presented, arrowEdge: .bottom) {
                    ModelCatalogList(current: connection.model, load: load) { model in
                        select(model)
                        presented = false
                    }
                }
                .onChange(of: connection.baseURL) { presented = false }
                .onChange(of: connection.purpose) { presented = false }
                .onChange(of: connection.timeoutSeconds) { presented = false }
                .onChange(of: apiKey) { presented = false }
                .onChange(of: clearKey) { presented = false }
                .onChange(of: sourceID) { presented = false }
                .onChange(of: enabled) { if !enabled { presented = false } }
        }
    }
}

private struct ModelCatalogList: View {
    let current: String
    let load: () async throws -> [String]
    let select: (String) -> Void
    @State private var models: [String] = []
    @State private var search = ""
    @State private var loading = true
    @State private var error = ""
    @State private var attempt = 0
    @FocusState private var searchFocused: Bool

    private var filtered: [String] {
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
                Button(L("重试")) { attempt += 1 }
            } else if models.isEmpty {
                Text(L("未找到适用模型，可直接输入模型 ID。"))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                TextField(L("搜索模型"), text: $search).textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                if filtered.isEmpty {
                    Text(L("没有匹配的模型")).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filtered, id: \.self) { model in
                                Button { select(model) } label: {
                                    HStack(spacing: 8) {
                                        Text(model).font(.system(size: 12, design: .monospaced))
                                            .lineLimit(2).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                        Image(systemName: "checkmark").opacity(current == model ? 1 : 0)
                                    }.padding(8).contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless).help(model)
                                .accessibilityValue(current == model ? L("已选用") : "")
                            }
                        }
                    }.frame(height: min(260, CGFloat(filtered.count) * 48))
                }
            }
        }
        .padding(16).frame(width: 380)
        .task(id: attempt) {
            loading = true; error = ""
            do {
                let result = try await load()
                try Task.checkCancellation()
                models = result; loading = false; searchFocused = true
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.error = error.localizedDescription; loading = false
            }
        }
    }
}
