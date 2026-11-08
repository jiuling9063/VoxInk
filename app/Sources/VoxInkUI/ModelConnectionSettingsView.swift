import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoxInkCore

struct ModelServicePicker: View {
    @ObservedObject var store: AppStore
    let purpose: ModelServicePurpose
    @State private var error = ""
    @State private var editing: ModelConnection?
    private var enabled: Bool { purpose == .transcription || store.polishingEnabled }
    @State private var compact = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let options = store.modelServices.providerOptions(for: purpose)
        let selectedID = store.modelServices.selectedID(for: purpose)
        let current = selectedID.flatMap { id in options.first { $0.connection?.id == id } }
        VStack(alignment: .leading, spacing: 18) {
            header(connection: current?.connection)
            if enabled {
                let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                     : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                layout {
                    field(L("服务商")) { providerMenu(options, current: current, local: selectedID == nil) }
                        .frame(width: compact ? nil : 178)
                    field(L("模型")) { modelField(connection: current?.connection, local: selectedID == nil) }
                }
                if let id = current?.connection?.id, store.connectionTestConnectionID == id, !store.connectionTestMessage.isEmpty {
                    Text(store.connectionTestMessage).font(.callout).textSelection(.enabled)
                    if !store.canStart && store.canCancel {
                        Button(L("取消测试")) { Task { await store.cancel() } }
                    }
                }
                if !error.isEmpty { Text(error).font(.caption).foregroundStyle(.orange) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            let narrow = size.width < 440
            if compact != narrow { compact = narrow }
        }
        .sheet(item: $editing) { ModelConnectionEditor(store: store, connection: $0) }
    }

    private func header(connection: ModelConnection?) -> some View {
        HStack(spacing: 12) {
            WorkspaceSectionHeader(title: purpose.title, icon: purpose == .transcription ? "waveform" : "pencil.line")
                .font(.system(size: 17, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .fixedSize()
            if purpose == .polishing {
                Toggle(L("启用润色"), isOn: Binding(get: { store.polishingEnabled }, set: { store.setPolishingEnabled($0) }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .disabled(!store.canEditModelServices)
            }
            Spacer(minLength: 4)
            if enabled, let connection {
                let title = purpose == .transcription ? L("选音频测试") : L("测试连接")
                Button { test(connection) } label: {
                    ViewThatFits(in: .horizontal) {
                        Text(title).fixedSize()
                        Image(systemName: "play.circle")
                    }
                }
                .buttonStyle(.plain).font(.callout)
                .foregroundStyle(VoxInkTheme(scheme: scheme).accent)
                .accessibilityLabel(title).help(title)
                .disabled(!store.canEditModelServices)
                Button { editing = connection } label: {
                    Image(systemName: "gearshape").frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel(L("连接设置…")).help(L("连接设置…"))
                .disabled(!store.canEditModelServices)
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func providerMenu(_ options: [ModelServiceSettings.ProviderOption],
                              current: ModelServiceSettings.ProviderOption?, local: Bool) -> some View {
        let saved = options.filter { $0.connection != nil }
        let presets = options.filter { $0.connection == nil && $0.provider != .custom }
        let title = current?.title ?? (local ? L("本地模型") : L("连接配置不可用"))
        return ServiceFieldMenu(title: purpose == .transcription ? L("识别服务") : L("润色服务"), value: title) {
            optionButton(L("本地模型"), selected: local) { select(nil) }
            if !saved.isEmpty {
                Section(L("已配置")) {
                    ForEach(saved) { item in
                        optionButton(item.title, selected: current?.id == item.id) { choose(item) }
                    }
                }
            }
            if !presets.isEmpty {
                Section(L("添加服务商")) {
                    ForEach(presets) { item in Button(item.title) { choose(item) } }
                }
            }
            if let custom = options.first(where: { $0.provider == .custom && $0.connection == nil }) {
                Divider()
                Button(custom.title) { choose(custom) }
            }
        }.disabled(!store.canEditModelServices)
    }

    @ViewBuilder private func modelField(connection: ModelConnection?, local: Bool) -> some View {
        if let connection {
            ModelCatalogButton(connection: connection, fillsField: true, load: { try await store.fetchModels(for: connection) }) { model in
                do {
                    try store.updateModelID(connection.id, model: model)
                    error = ""
                } catch { self.error = error.localizedDescription }
            }
            .id(connection.id).disabled(!store.canEditModelServices)
        } else if local && purpose == .polishing {
            ServiceFieldMenu(title: L("模型选择"), value: store.automaticPolishModel ? L("自动（推荐）") : store.polishModel.title) {
                optionButton(L("自动（推荐）"), selected: store.automaticPolishModel) { store.setAutomaticPolishModel(true) }
                ForEach(PolishModel.allCases, id: \.self) { model in
                    optionButton(model.title, selected: !store.automaticPolishModel && store.polishModel == model) { store.setPolishModel(model) }
                }
            }.disabled(!store.canEditModelServices)
        } else if local {
            Text(verbatim: ModelPackage.repository.components(separatedBy: "/").last ?? ModelPackage.repository)
                .font(.system(size: 12.5, design: .monospaced))
                .lineLimit(1).truncationMode(.middle).frame(minHeight: 36)
        } else {
            Text(L("连接配置不可用")).foregroundStyle(.secondary).frame(minHeight: 36)
        }
    }

    private func optionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choose(_ option: ModelServiceSettings.ProviderOption) {
        error = ""
        if let saved = option.connection {
            if (try? saved.validate()) == nil { editing = saved } else { select(saved.id) }
        } else {
            var draft = option.provider.makeConnection(for: purpose)
            if draft.name.isEmpty { draft.name = option.provider.title }
            editing = draft
        }
    }

    private func select(_ id: UUID?) {
        guard !enabled || store.modelServices.selectedID(for: purpose) != id else { return }
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

private struct ServiceFieldMenu<Items: View>: View {
    let title: String
    let value: String
    @ViewBuilder var items: Items
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Menu { items } label: { ServiceChoiceLabel(value: value) }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .modifier(WorkspaceChoiceSurface(hovering: hovering, focused: focused, enabled: enabled))
            .onHover { hovering = $0 }.focused($focused)
            .accessibilityLabel(title).accessibilityValue(value).help(value)
    }
}
