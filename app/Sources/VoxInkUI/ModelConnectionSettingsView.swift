import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoxInkCore

struct ModelServicePicker: View {
    @ObservedObject var store: AppStore
    let purpose: ModelServicePurpose
    @State private var error = ""
    @State private var editing: ModelConnection?

    private var selected: ModelConnection? {
        saved.first { $0.id == store.modelServices.selectedID(for: purpose) }
    }
    private var enabled: Bool { purpose == .transcription || store.polishingEnabled }
    private var saved: [ModelConnection] { store.modelServices.connections.filter { $0.purpose == purpose } }
    private var available: [ModelProviderPreset] {
        ModelProviderPreset.available(for: purpose).filter { provider in
            provider == .custom || !saved.contains { ModelProviderPreset.matching($0) == provider }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("处理方式"))
                Spacer()
                Menu {
                    if purpose == .polishing {
                        Button(L("不润色")) { store.setPolishingEnabled(false) }
                    }
                    Button(L("本地模型")) { select(nil) }
                    if !saved.isEmpty {
                        Section(L("已配置")) {
                            ForEach(saved) { connection in
                                Button(connection.name) {
                                    if (try? connection.validate()) == nil { editing = connection }
                                    else { select(connection.id) }
                                }
                            }
                        }
                    }
                    Section(L("服务商")) {
                        ForEach(available) { provider in
                            Button(provider.title) {
                                var connection = provider.makeConnection(for: purpose)
                                if connection.name.isEmpty { connection.name = "\(provider.title) · \(purpose.title)" }
                                editing = connection
                            }
                        }
                    }
                } label: {
                    Text(!enabled ? L("不润色") : (selected?.name ?? (store.modelServices.selectedID(for: purpose) == nil
                                           ? L("本地模型") : L("连接配置不可用"))))
                        .lineLimit(1)
                }
                .menuStyle(.borderedButton)
                .accessibilityLabel(purpose == .transcription ? L("识别服务") : L("润色服务"))
                .disabled(!store.canEditModelServices)
            }
            if !enabled {
                Text(L("直接使用识别结果，不做润色。")).font(.caption).foregroundStyle(.secondary)
            } else if let selected {
                HStack(alignment: .firstTextBaseline) {
                    Text(selected.model).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).textSelection(.enabled)
                    Spacer()
                    Button(L("设置…")) { editing = selected }.disabled(!store.canEditModelServices)
                    Button(purpose == .transcription ? L("选音频测试") : L("测试连接")) { test(selected) }
                        .disabled(!store.canEditModelServices)
                        .help(L("测试会发送示例文字或所选音频，可能产生 API 费用。"))
                }
                Text(purpose == .transcription ? L("音频由所选服务商处理。") : L("文字由所选服务商润色，失败时保留原文。"))
                    .font(.caption).foregroundStyle(.secondary)
                if store.connectionTestConnectionID == selected.id, !store.connectionTestMessage.isEmpty {
                    Text(store.connectionTestMessage).font(.caption).textSelection(.enabled)
                    if !store.canStart && store.canCancel {
                        Button(L("取消测试")) { Task { await store.cancel() } }
                    }
                }
            }
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .sheet(item: $editing) { ModelConnectionEditor(store: store, connection: $0) }
    }

    private func select(_ id: UUID?) {
        do {
            try store.selectModelService(id, for: purpose)
            if purpose == .polishing { store.setPolishingEnabled(true) }
            error = ""
        }
        catch { self.error = error.localizedDescription }
    }

    private func test(_ connection: ModelConnection) {
        if purpose == .polishing { store.testModelConnection(connection.id); return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("选择一段不超过 60 秒的音频，将发送到此连接进行转写测试。")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.testModelConnection(connection.id, audioURL: url)
    }
}
