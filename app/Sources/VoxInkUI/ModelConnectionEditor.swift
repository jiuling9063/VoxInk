import AppKit
import SwiftUI
import VoxInkCore

struct ModelConnectionEditor: View {
    @ObservedObject var store: AppStore
    @State private var draft: ModelConnectionDraft
    @State private var error = ""
    @State private var advanced = false
    @State private var reuseKey: Bool
    @State private var confirmingDeletion = false
    @FocusState private var keyFocused: Bool
    @FocusState private var parametersFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: AppStore, connection: ModelConnection) {
        self.store = store
        let existing = store.modelServices.connections.contains { $0.id == connection.id }
        _draft = State(initialValue: ModelConnectionDraft(connection: connection, isExisting: existing))
        _reuseKey = State(initialValue: !existing && store.modelServices.credentialSource(for: connection) != nil)
    }

    private var credentialSource: ModelConnection? {
        draft.original == nil && !draft.clearKey ? store.modelServices.credentialSource(for: draft.connection) : nil
    }
    private var usesSavedKey: Bool { reuseKey && credentialSource != nil }
    private var canSave: Bool {
        (try? draft.connection.validate()) != nil && (!draft.needsKey || usesSavedKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.provider.title).font(.title2.weight(.semibold))
                Text(draft.connection.purpose.title).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    keySection
                    modelField
                    if draft.provider == .custom { addressField }
                    advancedSection
                    Text(L("保存后立即选用。使用时会向此服务发送音频或文字，并可能产生 API 费用。"))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }.frame(height: advanced ? 450 : (draft.provider == .custom ? 430 : 330))
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                if !error.isEmpty {
                    Text(error).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Spacer()
                    Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(L("保存并使用")) { save() }
                        .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                        .disabled(!store.canEditModelServices || !canSave)
                }
            }.padding(20)
        }.frame(width: 520)
        .onChange(of: usesSavedKey) { _, reuse in if reuse { draft.apiKey = "" } }
        .confirmationDialog(L("删除此连接？正在使用时会切换回本地模型。"), isPresented: $confirmingDeletion) {
            Button(L("删除连接"), role: .destructive) {
                do {
                    try store.deleteModelConnection(draft.connection.id, useLocalIfSelected: true)
                    dismiss()
                } catch { self.error = error.localizedDescription }
            }
        }
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let source = credentialSource {
                Toggle(L("复用已保存的密钥"), isOn: $reuseKey)
                    .onChange(of: reuseKey) { _, reuse in if reuse { draft.apiKey = "" } }
                if usesSavedKey {
                    Text(L("使用“\(source.name)”的密钥，无需再次填写。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !usesSavedKey {
                HStack {
                    Text("API Key").font(.subheadline.weight(.medium))
                    Spacer()
                    if let url = draft.provider.consoleURL { Link(L("获取密钥 ↗"), destination: url) }
                    Button(L("粘贴")) {
                        if let value = NSPasteboard.general.string(forType: .string) {
                            draft.apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
                            keyFocused = true
                        }
                    }.disabled(draft.clearKey)
                }
                SecureField("API Key", text: $draft.apiKey, prompt: Text(
                    draft.original != nil && !draft.endpointChanged
                    ? L("已保存密钥；留空不修改") : L("在这里粘贴服务商的 API Key")))
                    .focused($keyFocused)
                    .modifier(WorkspaceInputSurface(focused: keyFocused))
                    .contentShape(Rectangle()).onTapGesture { keyFocused = true }
                    .disabled(draft.clearKey).accessibilityIdentifier("connectionAPIKey")
                Text(draft.endpointChanged ? L("接口地址已改变，请填写对应服务商的密钥。") : L("密钥安全保存在本机钥匙串。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var modelField: some View {
        VStack(alignment: .leading, spacing: 7) {
            WorkspaceModelField(title: L("模型"), text: Binding(
                get: { draft.connection.model }, set: { draft.updateModel($0) }))
                .accessibilityIdentifier("connectionModel")
            if draft.provider == .volcengine {
                Text(L("火山方舟可填写模型 ID 或已创建的推理接入点 ID。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var addressField: some View {
        field(L("接口地址")) {
            WorkspaceTextField(title: L("接口地址"), text: $draft.connection.baseURL,
                               prompt: "https://api.example.com/v1")
                .accessibilityIdentifier("connectionBaseURL")
        }
    }

    private var advancedSection: some View {
        DisclosureGroup(L("高级设置"), isExpanded: $advanced) {
            VStack(alignment: .leading, spacing: 16) {
                if draft.provider != .custom { addressField }
                field(L("连接名称")) {
                    WorkspaceTextField(title: L("连接名称"), text: $draft.connection.name, prompt: L("例如：日常润色"))
                }
                field(L("超时（秒）")) {
                    TextField(L("超时（秒）"), value: $draft.connection.timeoutSeconds, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                }
                if draft.connection.purpose == .polishing {
                    field(L("额外请求参数")) {
                        TextEditor(text: $draft.connection.extraBodyJSON)
                            .font(.system(.callout, design: .monospaced))
                            .scrollContentBackground(.hidden).frame(height: 72)
                            .focused($parametersFocused)
                            .modifier(WorkspaceInputSurface(focused: parametersFocused))
                            .accessibilityLabel(L("额外请求参数"))
                    }
                }
                if let url = draft.provider.documentationURL(for: draft.connection.purpose) {
                    Link(L("接口文档"), destination: url)
                }
                if draft.original != nil {
                    Toggle(L("清除已存密钥"), isOn: $draft.clearKey)
                        .onChange(of: draft.clearKey) { _, clear in if clear { draft.apiKey = "" } }
                    Button(L("删除连接"), role: .destructive) { confirmingDeletion = true }
                        .disabled(!store.canEditModelServices)
                }
            }.padding(.top, 12)
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.subheadline.weight(.medium))
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        do {
            try store.saveAndSelectModelConnection(draft.connection, apiKey: usesSavedKey ? nil : draft.apiKey,
                                                  clearKey: draft.clearKey,
                                                  reuseKeyFrom: usesSavedKey ? credentialSource?.id : nil)
            draft.apiKey = ""
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
