import Foundation
import VoxInkCore

/// Presets describe compatible endpoints, not account-specific model availability.
enum ModelProviderPreset: String, CaseIterable, Identifiable {
    case siliconFlow, openAI, deepSeek, dashScope, volcengine, zhipu, kimi, gemini, groq, openRouter, custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .siliconFlow: L("硅基流动")
        case .openAI: "OpenAI"
        case .deepSeek: "DeepSeek"
        case .dashScope: L("阿里云百炼")
        case .volcengine: L("火山方舟")
        case .zhipu: L("智谱")
        case .kimi: "Kimi"
        case .gemini: "Google Gemini"
        case .groq: "Groq"
        case .openRouter: "OpenRouter"
        case .custom: L("自定义接口")
        }
    }

    var baseURL: String {
        switch self {
        case .siliconFlow: "https://api.siliconflow.cn/v1"
        case .openAI: "https://api.openai.com/v1"
        case .deepSeek: "https://api.deepseek.com"
        case .dashScope: "https://dashscope.aliyuncs.com/compatible-mode/v1"
        case .volcengine: "https://ark.cn-beijing.volces.com/api/v3"
        case .zhipu: "https://open.bigmodel.cn/api/paas/v4"
        case .kimi: "https://api.moonshot.cn/v1"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
        case .groq: "https://api.groq.com/openai/v1"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .custom: ""
        }
    }

    var consoleURL: URL? {
        let address: String
        switch self {
        case .siliconFlow: address = "https://cloud.siliconflow.cn/me/account/ak"
        case .openAI: address = "https://platform.openai.com/api-keys"
        case .deepSeek: address = "https://platform.deepseek.com"
        case .dashScope: address = "https://bailian.console.aliyun.com"
        case .volcengine: address = "https://ark.volcengine.com/region:cn-beijing/apikey"
        case .zhipu: address = "https://bigmodel.cn"
        case .kimi: address = "https://platform.kimi.com"
        case .gemini: address = "https://aistudio.google.com/apikey"
        case .groq: address = "https://console.groq.com/keys"
        case .openRouter: address = "https://openrouter.ai/settings/keys"
        case .custom: return nil
        }
        return URL(string: address)
    }

    var documentationURL: URL? {
        let address: String
        switch self {
        case .siliconFlow: address = "https://docs.siliconflow.cn/docs/api/chat-completions-post"
        case .openAI: address = "https://developers.openai.com/api/docs"
        case .deepSeek: address = "https://api-docs.deepseek.com"
        case .dashScope: address = "https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope"
        case .volcengine: address = "https://docs.volcengine.com/docs/ark/quick-start?lang=zh"
        case .zhipu: address = "https://docs.bigmodel.cn/cn/guide/develop/openai/introduction"
        case .kimi: address = "https://platform.kimi.com/docs/get-api-key"
        case .gemini: address = "https://ai.google.dev/gemini-api/docs/openai"
        case .groq: address = "https://console.groq.com/docs"
        case .openRouter: address = "https://openrouter.ai/docs/quickstart"
        case .custom: return nil
        }
        return URL(string: address)
    }

    func documentationURL(for purpose: ModelServicePurpose) -> URL? {
        guard purpose == .transcription else { return documentationURL }
        switch self {
        case .siliconFlow: return URL(string: "https://docs.siliconflow.cn/docs/api/audio-transcriptions-post")
        case .openAI: return URL(string: "https://developers.openai.com/api/docs/guides/speech-to-text")
        case .groq: return URL(string: "https://console.groq.com/docs/speech-to-text")
        default: return documentationURL
        }
    }

    func supports(_ purpose: ModelServicePurpose) -> Bool {
        purpose == .polishing || [.siliconFlow, .openAI, .groq, .custom].contains(self)
    }

    static func available(for purpose: ModelServicePurpose) -> [Self] {
        allCases.filter { $0.supports(purpose) }
    }

    func model(for purpose: ModelServicePurpose) -> String {
        if purpose == .transcription {
            switch self {
            case .siliconFlow: return "FunAudioLLM/SenseVoiceSmall"
            case .openAI: return "gpt-4o-mini-transcribe"
            case .groq: return "whisper-large-v3-turbo"
            default: return ""
            }
        }
        switch self {
        case .siliconFlow: return "deepseek-ai/DeepSeek-V4-Flash"
        case .openAI: return "gpt-4.1-mini"
        case .deepSeek: return "deepseek-flash"
        case .dashScope: return "qwen-plus"
        case .zhipu: return "glm-5.3"
        case .kimi: return "kimi-k3"
        case .gemini: return "gemini-3.8-flash"
        // These catalogs or deployments vary by account; let the user choose a model.
        case .volcengine, .groq, .openRouter, .custom: return ""
        }
    }

    func parameters(for purpose: ModelServicePurpose) -> String {
        guard purpose == .polishing else { return "{}" }
        switch self {
        case .siliconFlow: return #"{"enable_thinking":false}"#
        case .deepSeek: return #"{"thinking":{"type":"disabled"}}"#
        case .kimi, .gemini: return #"{"reasoning_effort":"low"}"#
        default: return "{}"
        }
    }

    func makeConnection(for purpose: ModelServicePurpose) -> ModelConnection {
        var connection = ModelConnection()
        connection.purpose = purpose
        guard supports(purpose), self != .custom else { return connection }
        connection.name = "\(title) · \(purpose.title)"
        connection.baseURL = baseURL
        connection.model = model(for: purpose)
        connection.extraBodyJSON = parameters(for: purpose)
        return connection
    }

    static func matching(_ connection: ModelConnection) -> Self {
        guard let endpoint = try? connection.endpointURL() else { return .custom }
        return available(for: connection.purpose).first {
            $0 != .custom && (try? $0.makeConnection(for: connection.purpose).endpointURL()) == endpoint
        } ?? .custom
    }
}

extension ModelServiceSettings {
    func credentialSource(for connection: ModelConnection) -> ModelConnection? {
        let provider = ModelProviderPreset.matching(connection)
        guard provider != .custom else { return nil }
        let candidates = connections.filter {
            $0.id != connection.id && $0.purpose != connection.purpose
                && ModelProviderPreset.matching($0) == provider
        }
        return candidates.first { selectedID(for: $0.purpose) == $0.id } ?? candidates.first
    }
}

struct ModelConnectionDraft {
    var connection: ModelConnection
    private(set) var provider: ModelProviderPreset
    var apiKey = ""
    var clearKey = false
    let original: ModelConnection?

    init(connection: ModelConnection, isExisting: Bool) {
        self.connection = connection
        provider = .matching(connection)
        original = isExisting ? connection : nil
    }

    mutating func selectProvider(_ provider: ModelProviderPreset) {
        guard provider != self.provider, provider.supports(connection.purpose) else { return }
        let previous = self.provider
        self.provider = provider
        guard provider != .custom else { return }
        let preset = provider.makeConnection(for: connection.purpose)
        if connection.name.isEmpty || connection.name == previous.makeConnection(for: connection.purpose).name {
            connection.name = preset.name
        }
        connection.baseURL = preset.baseURL
        connection.model = preset.model
        connection.extraBodyJSON = preset.extraBodyJSON
        // An unsaved key must never follow the user to a different provider.
        apiKey = ""
        clearKey = false
    }

    mutating func selectPurpose(_ purpose: ModelServicePurpose) {
        guard purpose != connection.purpose else { return }
        let previousName = provider.makeConnection(for: connection.purpose).name
        connection.purpose = purpose
        if !provider.supports(purpose) {
            provider = .custom
            connection.baseURL = ""
            if connection.name == previousName { connection.name = "" }
        }
        if provider != .custom {
            let preset = provider.makeConnection(for: purpose)
            connection.baseURL = preset.baseURL
            connection.model = preset.model
            connection.extraBodyJSON = preset.extraBodyJSON
            if connection.name == previousName { connection.name = preset.name }
        } else {
            connection.model = ""
            connection.extraBodyJSON = "{}"
        }
        apiKey = ""
        clearKey = false
    }

    mutating func updateModel(_ model: String) {
        if model != connection.model,
           connection.model == provider.model(for: connection.purpose),
           connection.extraBodyJSON == provider.parameters(for: connection.purpose) {
            connection.extraBodyJSON = "{}"
        }
        connection.model = model
    }

    var endpointChanged: Bool {
        guard let original else { return false }
        return (try? original.endpointURL()) != (try? connection.endpointURL())
    }

    var needsKey: Bool {
        provider != .custom && !clearKey && (original == nil || endpointChanged)
            && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canSave: Bool { (try? connection.validate()) != nil && !needsKey }
}
