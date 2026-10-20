import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoxInkCore

struct ModelServicePicker: View {
    @ObservedObject var store: AppStore
    let purpose: ModelServicePurpose
    @State private var error = ""
    @State private var adding: ModelConnection?

    var body: some View {
        WorkspacePicker(L("处理服务"), selection: Binding(get: {
            store.modelServices.selectedID(for: purpose)?.uuidString ?? "local"
        }, set: { value in
            do { try store.selectModelService(UUID(uuidString: value), for: purpose); error = "" }
            catch { self.error = error.localizedDescription }
        })) {
            Text(L("本地模型")).tag("local")
            ForEach(store.modelServices.connections.filter { $0.purpose == purpose }) { connection in
                Text(connection.name).tag(connection.id.uuidString)
            }
            if let id = store.modelServices.selectedID(for: purpose),
               !store.modelServices.connections.contains(where: { $0.id == id && $0.purpose == purpose }) {
                Text(L("连接配置不可用")).tag(id.uuidString)
            }
        }.disabled(!store.canEditModelServices)
        Menu {
            ForEach(ModelProviderPreset.available(for: purpose)) { provider in
                Button(provider.title) { adding = provider.makeConnection(for: purpose) }
            }
        } label: {
            Label(L("添加服务商"), systemImage: "plus.circle")
        }
        .menuStyle(.borderlessButton).fixedSize()
        .disabled(!store.canEditModelServices)
        .sheet(item: $adding) { ModelConnectionEditor(store: store, connection: $0) }
        if let connection = try? store.modelServices.connection(for: purpose) {
            Text(purpose == .transcription
                 ? L("录音结束后，音频将发送到 \(connection.name)（\(connection.baseURL)）。")
                 : L("识别后的文字将发送到 \(connection.name)（\(connection.baseURL)），失败时保留原文。"))
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
        if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
    }
}

struct ModelConnectionsContent: View {
    @ObservedObject var store: AppStore
    var purpose: ModelServicePurpose? = nil
    @State private var editing: ModelConnection?
    @State private var error = ""

    private var connections: [ModelConnection] {
        store.modelServices.connections.filter { purpose == nil || $0.purpose == purpose }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("支持 OpenAI 兼容的文本润色和音频文件转写接口。转写与润色可分别选择连接；本版不含实时流式识别。"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(connections) { connection in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(connection.name).fontWeight(.medium)
                        Spacer()
                        Text(connection.purpose.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(connection.model).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(ModelProviderPreset.matching(connection).title)
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(L("编辑")) { editing = connection }
                        Button(connection.purpose == .transcription ? L("选音频测试") : L("测试连接")) { test(connection) }
                        Button(L("删除"), role: .destructive) {
                            do { try store.deleteModelConnection(connection.id); error = "" }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(!store.canEditModelServices)
                }
                Divider()
            }
            Menu {
                ForEach(ModelProviderPreset.available(for: purpose ?? .polishing)) { provider in
                    Button(provider.title) { editing = provider.makeConnection(for: purpose ?? .polishing) }
                }
            } label: {
                Label(L("添加服务商"), systemImage: "plus")
            }.fixedSize().disabled(!store.canEditModelServices)
            Text(L("测试会向所填地址发送示例文字或你选择的音频，可能产生 API 费用。密钥仅保存在 macOS 钥匙串。"))
                .font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            if !store.connectionTestMessage.isEmpty {
                Text(store.connectionTestMessage).font(.caption).textSelection(.enabled)
            }
            if !store.canStart && store.canCancel {
                Button(L("取消")) { Task { await store.cancel() } }
            }
        }
        .sheet(item: $editing) { connection in
            ModelConnectionEditor(store: store, connection: connection)
        }
    }

    private func test(_ connection: ModelConnection) {
        if connection.purpose == .polishing { store.testModelConnection(connection.id); return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("选择一段不超过 60 秒的音频，将发送到此连接进行转写测试。")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.testModelConnection(connection.id, audioURL: url)
    }
}
