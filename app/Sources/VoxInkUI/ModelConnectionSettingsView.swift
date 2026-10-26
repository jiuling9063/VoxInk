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
                WorkspaceMenu(title: purpose == .transcription ? L("识别服务") : L("润色服务"), value: selectionTitle) {
                    if purpose == .polishing {
                        serviceOption(L("不润色"), selected: !enabled) { store.setPolishingEnabled(false) }
                    }
                    serviceOption(L("本地模型"), selected: enabled && store.modelServices.selectedID(for: purpose) == nil) { select(nil) }
                    if !saved.isEmpty {
                        Section(L("已配置")) {
                            ForEach(saved) { connection in
                                serviceOption(connection.name, selected: enabled && selected?.id == connection.id) {
                                    if (try? connection.validate()) == nil { editing = connection }
                                    else { select(connection.id) }
                                }
                            }
                        }
                    }
                    if let selected, enabled {
                        Section {
                            Button(L("设置…")) { editing = selected }
                            Button(purpose == .transcription ? L("选音频测试") : L("测试连接")) { test(selected) }
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
                }
                .disabled(!store.canEditModelServices)
            }
            if enabled, let selected {
                Divider()
                ModelIDSettingsField(store: store, connection: selected).id(selected.id)
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

    private var selectionTitle: String {
        !enabled ? L("不润色") : (selected?.name ?? (store.modelServices.selectedID(for: purpose) == nil
            ? L("本地模型") : L("连接配置不可用")))
    }

    private func serviceOption(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
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

private struct ModelIDSettingsField: View {
    @ObservedObject var store: AppStore
    let connection: ModelConnection
    @State private var draft: String
    @State private var error = ""

    init(store: AppStore, connection: ModelConnection) {
        self.store = store; self.connection = connection
        _draft = State(initialValue: connection.model)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            WorkspaceModelField(title: connection.purpose == .transcription ? L("识别模型 ID") : L("润色模型 ID"),
                                text: $draft, commit: save, cancel: { draft = connection.model; error = "" })
                .disabled(!store.canEditModelServices)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .onChange(of: connection.model) { _, model in draft = model }
    }

    private func save() {
        guard draft != connection.model else { return }
        do {
            try store.updateModelID(connection.id, model: draft)
            draft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            error = ""
        } catch {
            draft = connection.model
            self.error = error.localizedDescription
        }
    }
}
