import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoxInkCore

struct ModelServicePicker: View {
    @ObservedObject var store: AppStore
    let purpose: ModelServicePurpose
    @State private var error = ""
    @State private var editing: ModelConnection?
    @State private var choosingProvider = false
    @State private var pendingProvider: ModelProviderPreset?

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
            WorkspaceRow(L("处理方式")) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { serviceMenu; testButton }
                    VStack(alignment: .leading, spacing: 8) { serviceMenu; testButton }
                }
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
        .sheet(isPresented: $choosingProvider, onDismiss: { openPendingProvider() }) {
            ProviderPickerSheet(purpose: purpose, providers: available) { provider in
                pendingProvider = provider
                choosingProvider = false
            }
        }
    }

    @ViewBuilder private var testButton: some View {
        if let selected, enabled {
            Button(purpose == .transcription ? L("选音频测试") : L("测试连接")) { test(selected) }
                .disabled(!store.canEditModelServices)
        }
    }

    private var serviceMenu: some View {
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
            Divider()
            Button(L("添加服务…")) { choosingProvider = true }
        }
        .disabled(!store.canEditModelServices)
    }

    /// The editor opens only after the picker sheet is gone; two sheets can't share one presentation.
    private func openPendingProvider() {
        guard let provider = pendingProvider else { return }
        pendingProvider = nil
        var connection = provider.makeConnection(for: purpose)
        if connection.name.isEmpty { connection.name = "\(provider.title) · \(purpose.title)" }
        editing = connection
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
        guard let url = Self.chooseTestAudio() else { return }
        store.testModelConnection(connection.id, audioURL: url)
    }

    static func chooseTestAudio() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = L("选择一段不超过 60 秒的音频，将发送到此连接进行转写测试。")
        return panel.runModal() == .OK ? panel.url : nil
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
        VStack(alignment: .leading, spacing: 5) {
            WorkspaceModelField(title: connection.purpose == .transcription ? L("识别模型 ID") : L("润色模型 ID"),
                                text: $draft, commit: save, cancel: { draft = connection.model; error = "" }, accessory: {
                ModelCatalogButton(connection: connection, load: { try await store.fetchModels(for: connection) }) {
                    draft = $0
                    save()
                }
            })
                .disabled(!store.canEditModelServices)
            if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .onChange(of: connection.model) { _, model in draft = model }
        .onDisappear(perform: save)
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

/// Searchable grid of providers, replacing the long provider list that used to sit inside the menu.
struct ProviderPickerSheet: View {
    let purpose: ModelServicePurpose
    let providers: [ModelProviderPreset]
    let choose: (ModelProviderPreset) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var presets: [ModelProviderPreset] {
        let text = query.trimmingCharacters(in: .whitespaces)
        return providers.filter { provider in
            provider != .custom && (text.isEmpty
                || provider.title.localizedCaseInsensitiveContains(text)
                || provider.rawValue.localizedCaseInsensitiveContains(text))
        }
    }

    var body: some View {
        let theme = VoxInkTheme(scheme: scheme)
        VStack(alignment: .leading, spacing: 16) {
            Text(purpose == .transcription ? L("识别服务") : L("润色服务")).font(.title3.weight(.semibold))
            TextField(L("搜索服务商"), text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(presets) { provider in
                        Button { choose(provider) } label: { card(provider, theme: theme) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(provider.title)
                    }
                }
                if presets.isEmpty {
                    Text(L("没有匹配的服务商，可使用自定义接口。")).font(.callout).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                }
            }
            .frame(maxHeight: 300)
            Divider()
            HStack {
                if providers.contains(.custom) {
                    Button(L("自定义接口")) { choose(.custom) }
                }
                Spacer()
                Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .tint(theme.accent)
    }

    private func card(_ provider: ModelProviderPreset, theme: VoxInkTheme) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(provider.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.ink)
                .lineLimit(1)
            HStack(spacing: 4) {
                if provider.supports(.transcription) { tag(L("转写"), theme: theme) }
                if provider.supports(.polishing) { tag(L("润色"), theme: theme) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.fieldFill, in: RoundedRectangle(cornerRadius: VoxInkTheme.Radius.control + 2, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VoxInkTheme.Radius.control + 2, style: .continuous)
                .strokeBorder(theme.ink.opacity(0.08), lineWidth: 1)
        }
        .contentShape(Rectangle())
    }

    private func tag(_ title: String, theme: VoxInkTheme) -> some View {
        Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(theme.accent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(theme.accent.opacity(0.1), in: Capsule())
    }
}
