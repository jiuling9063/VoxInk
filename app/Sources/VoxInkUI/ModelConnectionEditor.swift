import AppKit
import SwiftUI
import VoxInkCore

struct ModelConnectionEditor: View {
    @ObservedObject var store: AppStore
    @State private var draft: ModelConnectionDraft
    @State private var error = ""
    @State private var advanced = false
    @FocusState private var keyFocused: Bool
    @FocusState private var parametersFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: AppStore, connection: ModelConnection) {
        self.store = store
        _draft = State(initialValue: ModelConnectionDraft(
            connection: connection,
            isExisting: store.modelServices.connections.contains { $0.id == connection.id }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(draft.original == nil ? L("添加服务商") : L("编辑连接"))
                    .font(.title2.weight(.semibold))
                Text(L("选择服务商，填写模型和密钥，即可连接。"))
                    .foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    providerSection
                    keySection
                    connectionSection
                    advancedSection
                }.padding(24)
            }
            Divider()
            HStack {
                if !error.isEmpty {
                    Text(error).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if draft.needsKey {
                    Text(L("粘贴 API Key 后即可保存。")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button(L("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("保存")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.canEditModelServices || !draft.canSave)
            }.padding(20)
        }
        .frame(width: 620, height: 720)
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("服务商")).font(.headline)
                Spacer()
                Picker(L("用途"), selection: Binding(get: { draft.connection.purpose }, set: {
                    draft.selectPurpose($0); error = ""
                })) {
                    ForEach(ModelServicePurpose.allCases, id: \.self) {
                        Text($0.title).tag($0)
                    }
                }.fixedSize()
            }
            Picker(L("服务商"), selection: Binding(get: { draft.provider }, set: {
                draft.selectProvider($0); error = ""
            })) {
                ForEach(ModelProviderPreset.available(for: draft.connection.purpose)) {
                    Text($0.title).tag($0)
                }
            }
            .labelsHidden().pickerStyle(.menu).controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("connectionProviderPicker")
            HStack(spacing: 16) {
                if let url = draft.provider.consoleURL {
                    Link(destination: url) { Label(L("获取 API Key"), systemImage: "arrow.up.right.square") }
                }
                if let url = draft.provider.documentationURL(for: draft.connection.purpose) {
                    Link(L("接口文档"), destination: url)
                }
            }.font(.callout)
            Text(draft.connection.purpose == .transcription
                 ? L("此处列出支持通用文件转写接口的服务商。")
                 : L("预填官方接口与模型示例，也可以填写其他可用模型。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("API Key", systemImage: "key").font(.headline)
                Spacer()
                Button(L("粘贴密钥"), systemImage: "doc.on.clipboard") {
                    if let value = NSPasteboard.general.string(forType: .string) {
                        draft.apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        keyFocused = true
                    }
                }.disabled(draft.clearKey)
            }
            SecureField("API Key", text: $draft.apiKey, prompt: Text(keyPrompt))
                .focused($keyFocused)
                .modifier(WorkspaceInputSurface(focused: keyFocused))
                .contentShape(Rectangle())
                .onTapGesture { keyFocused = true }
                .disabled(draft.clearKey)
                .accessibilityLabel("API Key")
                .accessibilityIdentifier("connectionAPIKey")
            Text(draft.endpointChanged
                 ? L("接口地址已改变，请填写对应服务商的密钥。")
                 : L("密钥保存在 macOS 钥匙串。编辑时留空可保留已有密钥。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var keyPrompt: String {
        draft.original != nil && !draft.endpointChanged
            ? L("粘贴新密钥以替换，留空保留已有密钥")
            : L("在这里粘贴服务商的 API Key")
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            field(L("连接名称")) {
                WorkspaceTextField(title: L("连接名称"), text: $draft.connection.name,
                                   prompt: L("例如：日常润色"))
            }
            field(L("模型 ID")) {
                WorkspaceTextField(title: L("模型 ID"), text: Binding(
                    get: { draft.connection.model }, set: { draft.updateModel($0) }),
                                   prompt: L("填写服务商控制台中的模型 ID"))
                    .accessibilityIdentifier("connectionModel")
                if draft.provider == .volcengine {
                    Text(L("火山方舟可填写模型 ID 或已创建的推理接入点 ID。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            field(L("接口地址")) {
                WorkspaceTextField(title: L("接口地址"), text: $draft.connection.baseURL,
                                   prompt: "https://api.example.com/v1")
                    .accessibilityIdentifier("connectionBaseURL")
                Text(L("已预填的地址可直接使用；自建或其他地区服务可自行修改。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var advancedSection: some View {
        DisclosureGroup(L("高级设置"), isExpanded: $advanced) {
            VStack(alignment: .leading, spacing: 16) {
                field(L("超时（秒）")) {
                    TextField(L("超时（秒）"), value: $draft.connection.timeoutSeconds, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                }
                if draft.connection.purpose == .polishing {
                    field(L("额外请求参数")) {
                        TextEditor(text: $draft.connection.extraBodyJSON)
                            .font(.system(.callout, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .frame(height: 96)
                            .focused($parametersFocused)
                            .modifier(WorkspaceInputSurface(focused: parametersFocused))
                            .accessibilityLabel(L("额外请求参数"))
                        Text(L("可填写服务商支持的 JSON 参数，例如关闭思考模式。不要填写密钥。参数名称以服务商文档为准。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle(L("清除已存密钥"), isOn: $draft.clearKey)
                    .onChange(of: draft.clearKey) { _, clear in if clear { draft.apiKey = "" } }
                Text(L("填写包含 API 版本的基础地址，也可填写完整接口地址。仅支持 HTTPS；本机 localhost 可使用 HTTP。"))
                    .font(.caption).foregroundStyle(.secondary)
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
            try store.saveModelConnection(draft.connection, apiKey: draft.apiKey, clearKey: draft.clearKey)
            draft.apiKey = ""
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
