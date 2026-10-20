import Foundation
import Security
import VoxInkCore

public enum ModelServicePurpose: String, Codable, CaseIterable, Sendable {
    case transcription, polishing

    var title: String { self == .transcription ? L("语音识别") : L("文字润色") }
    var endpoint: String { self == .transcription ? "audio/transcriptions" : "chat/completions" }
}

public struct ModelConnection: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name = ""
    public var purpose: ModelServicePurpose = .polishing
    public var baseURL = ""
    public var model = ""
    public var timeoutSeconds: Double = 30
    public var extraBodyJSON = "{}"

    public init() {}

    func endpointURL() throws -> URL {
        guard let components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.scheme == "https" || (components.scheme == "http" && ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host)),
              let url = components.url else { throw CloudServiceError.invalidURL }
        // Accept a base URL including its API version, or the complete endpoint.
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path == purpose.endpoint || path.hasSuffix("/" + purpose.endpoint) { return url }
        return url.appendingPathComponent(purpose.endpoint)
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !model.contains("\r"), !model.contains("\n"),
              timeoutSeconds.isFinite, (1...120).contains(timeoutSeconds) else { throw CloudServiceError.invalidConfiguration }
        _ = try endpointURL()
        _ = try extraBody()
    }

    func extraBody() throws -> [String: Any] {
        guard purpose == .polishing else { return [:] }
        guard let data = extraBodyJSON.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(value.keys).isDisjoint(with: ["model", "messages", "stream", "n", "tools", "tool_choice", "api_key", "authorization"]) else {
            throw CloudServiceError.invalidParameters
        }
        return value
    }
}

public struct ModelServiceSettings: Codable, Equatable, Sendable {
    public var connections: [ModelConnection] = []
    public var transcriptionID: UUID?
    public var polishingID: UUID?

    public init() {}

    func selectedID(for purpose: ModelServicePurpose) -> UUID? {
        purpose == .transcription ? transcriptionID : polishingID
    }

    func connection(for purpose: ModelServicePurpose) throws -> ModelConnection? {
        guard let id = selectedID(for: purpose) else { return nil }
        guard let connection = connections.first(where: { $0.id == id && $0.purpose == purpose }) else {
            throw CloudServiceError.missingConnection
        }
        try connection.validate()
        return connection
    }
}

public enum CloudServiceError: Error, LocalizedError, Equatable {
    case invalidURL, invalidConfiguration, invalidParameters, missingConnection, keychain
    case busy, connectionInUse, addressChanged, authentication, rateLimited, timeout, network
    case http(Int), invalidResponse, emptyResponse, audioTooLarge, audioUnreadable

    public var errorDescription: String? {
        switch self {
        case .invalidURL: L("请填写 HTTPS 服务地址；本机 localhost 可使用 HTTP。地址不能包含密钥、查询参数或片段。")
        case .invalidConfiguration: L("请填写连接名称、模型 ID，并将超时设为 1–120 秒。")
        case .invalidParameters: L("额外参数必须是 JSON 对象，不能覆盖模型、消息、流式、工具或认证字段。")
        case .missingConnection: L("所选服务不可用，请在“语音与润色”中重新选择。")
        case .keychain: L("无法访问钥匙串，请检查权限后重试。")
        case .busy: L("当前任务结束后才能修改连接。")
        case .connectionInUse: L("该连接正在使用，请先切换服务后删除或更改用途。")
        case .addressChanged: L("服务地址已更改，请重新填写密钥，或选择清除已存密钥。")
        case .authentication: L("认证失败，请检查 API Key 和模型访问权限。")
        case .rateLimited: L("服务限流或额度不足，请检查账户后重试。")
        case .timeout: L("服务请求超时，请重试或调整连接的超时设置。")
        case .network: L("无法连接模型服务，请检查网络和服务地址。")
        case .http(let code): L("模型服务返回 HTTP \(code)，请检查接口类型、模型 ID 和服务状态。")
        case .invalidResponse: L("服务返回格式不兼容或内容不完整，请检查接口和模型。")
        case .emptyResponse: L("服务未返回有效文字。")
        case .audioTooLarge: L("音频文件超过 25 MB，请使用较短的录音。")
        case .audioUnreadable: L("无法读取音频文件。")
        }
    }
}

@MainActor public protocol ModelCredentialStorage {
    func read(_ id: UUID) throws -> String?
    func write(_ value: String?, for id: UUID) throws
}

@MainActor public struct KeychainModelCredentials: ModelCredentialStorage {
    public init() {}
    private func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.voxink.model-connections",
         kSecAttrAccount as String: id.uuidString]
    }

    public func read(_ id: UUID) throws -> String? {
        var request = query(id)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw CloudServiceError.keychain }
        return value
    }

    public func write(_ value: String?, for id: UUID) throws {
        let request = query(id)
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(request as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw CloudServiceError.keychain }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = request.merging(attributes) { _, new in new }
            insertion[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(insertion as CFDictionary, nil) == errSecSuccess else { throw CloudServiceError.keychain }
        } else if status != errSecSuccess { throw CloudServiceError.keychain }
    }
}
