import Foundation
import VoxInkCore

struct ModelCatalogResult: Equatable, Sendable {
    var models: [String] = []
    var unclassified: [String] = []
    var isEmpty: Bool { models.isEmpty && unclassified.isEmpty }
}

enum ModelCatalogError: Error, LocalizedError, Equatable {
    case unsupported, incomplete
    var errorDescription: String? {
        switch self {
        case .unsupported: L("此接口未提供兼容的模型列表。可查看服务商文档，或直接输入模型 ID。")
        case .incomplete: L("模型列表未能完整获取，请重试或直接输入模型 ID。")
        }
    }
}

enum ModelCatalog {
    enum Suitability { case suitable, unrelated, unknown }

    static func url(for connection: ModelConnection) throws -> URL {
        var base = try connection.endpointURL()
        for _ in connection.endpoint.split(separator: "/") { base.deleteLastPathComponent() }
        guard var components = URLComponents(url: base.appendingPathComponent("models"), resolvingAgainstBaseURL: false) else {
            throw CloudServiceError.invalidURL
        }
        switch ModelProviderPreset.matching(connection) {
        case .siliconFlow:
            components.queryItems = [.init(name: "sub_type", value: connection.purpose == .transcription ? "speech-to-text" : "chat")]
        case .openRouter where connection.purpose == .polishing:
            components.queryItems = [.init(name: "input_modalities", value: "text"), .init(name: "output_modalities", value: "text")]
        default: break
        }
        let host = base.host?.lowercased() ?? ""
        let path = base.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if (["dashscope.aliyuncs.com", "dashscope-intl.aliyuncs.com", "cn-hongkong.dashscope.aliyuncs.com"].contains(host)
            || host.hasSuffix(".maas.aliyuncs.com")), ["compatible-mode/v1", "api/v1"].contains(path) {
            components.path = "/api/v1/models"
            components.queryItems = [.init(name: "capabilities", value: connection.purpose == .transcription ? "ASR" : "TG"),
                                     .init(name: "page_no", value: "1"), .init(name: "page_size", value: "100")]
        }
        guard let url = components.url else { throw CloudServiceError.invalidURL }
        return url
    }

    static func documentationURL(for connection: ModelConnection) -> URL? {
        let provider = ModelProviderPreset.matching(connection)
        if provider == .volcengine {
            return URL(string: "https://console.volcengine.com/ark/region%3Acn-beijing/docs/model-list")
        }
        return provider.documentationURL(for: connection.purpose)
    }

    static func validID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 512 && id == id.trimmingCharacters(in: .whitespacesAndNewlines)
            && id.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    static func suitability(_ item: [String: Any], id: String, purpose: ModelServicePurpose,
                            serverFiltered: Bool) -> Suitability {
        if item["active"] as? Bool == false { return .unrelated }
        let nonTextDomains: Set<String> = ["3dgeneration", "imagegeneration", "videogeneration", "embedding"]
        if let domain = item["domain"] as? String, nonTextDomains.contains(domain.lowercased()) { return .unrelated }
        let capabilities = Set(((item["capabilities"] as? [String] ?? []) + (item["task_type"] as? [String] ?? [])
            + [item["sub_type"] as? String, item["type"] as? String].compactMap { $0 }).map { $0.lowercased() })
        let speech: Set<String> = ["speech-to-text", "asr", "transcription"]
        let chat: Set<String> = ["chat", "text-generation", "textgeneration", "tg"]
        let other: Set<String> = ["embedding", "embeddings", "rerank", "reranker", "text-to-speech", "tts", "textto3d", "imageto3d",
                                 "text-to-image", "image-to-image", "text-to-video", "image-to-video", "ig", "vg", "me"]
        let requested = purpose == .transcription ? speech : chat
        let architecture = item["architecture"] as? [String: Any] ?? [:]
        let inference = item["inference_metadata"] as? [String: Any] ?? [:]
        let modalities = item["modalities"] as? [String: Any] ?? [:]
        let inputs = (item["input_modalities"] as? [String] ?? modalities["input_modalities"] as? [String] ?? architecture["input_modalities"] as? [String]
            ?? inference["request_modality"] as? [String])?.map { $0.lowercased() }
        let outputs = (item["output_modalities"] as? [String] ?? modalities["output_modalities"] as? [String] ?? architecture["output_modalities"] as? [String]
            ?? inference["response_modality"] as? [String])?.map { $0.lowercased() }
        if let outputs, !outputs.isEmpty, !outputs.contains("text") { return .unrelated }
        let requiredInput = purpose == .polishing ? "text" : "audio"
        if let inputs, !inputs.isEmpty, !inputs.contains(requiredInput) { return .unrelated }
        if !capabilities.isDisjoint(with: requested) { return .suitable }
        if !capabilities.isDisjoint(with: speech.union(chat).union(other)) { return .unrelated }
        if purpose == .polishing, let inputs, let outputs {
            return inputs.contains("text") && outputs.contains("text") ? .suitable : .unrelated
        }
        // Audio input alone does not prove compatibility with audio/transcriptions.
        if serverFiltered { return .suitable }

        // ID hints only remove well-known specialized families; opaque IDs remain selectable.
        let name = id.lowercased()
        let irrelevant = #"(^|[/_-])(embedding|embeddings|rerank|reranker|tts|moderation|safeguard|prompt-guard|seed3d|seedream|seedance|hyper3d|hitem3d)([/_.-]|$)|(^|/)(dall-e|gpt-image|imagen-|veo-|sora-|flux[.-]|bge-)"#
        if name.range(of: irrelevant, options: .regularExpression) != nil { return .unrelated }
        let transcription = #"(^|[/_-])(whisper|asr|transcribe|sensevoice)([/_.-]|$)|sensevoicesmall"#
        if name.range(of: transcription, options: .regularExpression) != nil {
            return purpose == .transcription ? .suitable : .unrelated
        }
        return .unknown
    }

    struct Page {
        let result: ModelCatalogResult
        let count: Int
        let lastID: String?
        let hasMore: Bool
        let total: Int?
        let ids: Set<String>
    }

    static func decode(_ data: Data, purpose: ModelServicePurpose, serverFiltered: Bool) throws -> Page {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudServiceError.invalidResponse
        }
        let output = body["output"] as? [String: Any]
        guard let items = body["data"] as? [[String: Any]] ?? output?["models"] as? [[String: Any]] else {
            throw CloudServiceError.invalidResponse
        }
        if let output {
            guard let total = output["total"] as? Int, total >= 0 else { throw CloudServiceError.invalidResponse }
        }
        var known = Set<String>(), unknown = Set<String>()
        var ids = Set<String>()
        for item in items {
            guard let id = item["id"] as? String ?? item["model"] as? String else { throw CloudServiceError.invalidResponse }
            guard validID(id) else { continue }
            ids.insert(id)
            switch suitability(item, id: id, purpose: purpose, serverFiltered: serverFiltered) {
            case .suitable: known.insert(id)
            case .unknown: unknown.insert(id)
            case .unrelated: break
            }
        }
        return Page(result: .init(models: known.sorted(), unclassified: unknown.subtracting(known).sorted()),
                    count: items.count, lastID: body["last_id"] as? String ?? items.last?["id"] as? String,
                    hasMore: body["has_more"] as? Bool == true, total: output?["total"] as? Int, ids: ids)
    }
}

extension CloudModelClient {
    func fetchModels() async throws -> ModelCatalogResult {
        guard connection.timeoutSeconds.isFinite, (1...120).contains(connection.timeoutSeconds) else {
            throw CloudServiceError.invalidConfiguration
        }
        let url = try ModelCatalog.url(for: connection)
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key?.contains("\r") != true, key?.contains("\n") != true else { throw CloudServiceError.authentication }
        return try await withThrowingTaskGroup(of: ModelCatalogResult.self) { group in
            group.addTask { try await fetchModelPages(url: url, key: key) }
            group.addTask {
                try await Task.sleep(for: .seconds(connection.timeoutSeconds))
                throw CloudServiceError.timeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CloudServiceError.invalidResponse }
            return result
        }
    }

    private func fetchModelPages(url initialURL: URL, key: String?) async throws -> ModelCatalogResult {
        var url = initialURL, known = Set<String>(), unknown = Set<String>(), cursors = Set<String>()
        var fetched = 0, seenIDs = Set<String>()
        let serverFiltered = ModelProviderPreset.matching(connection) == .siliconFlow
        for pageNumber in 1...100 {
            try Task.checkCancellation()
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: connection.timeoutSeconds)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let key, !key.isEmpty { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
            let data: Data
            do { data = try await send(request) }
            catch CloudServiceError.http(let status) where [404, 405, 501].contains(status) { throw ModelCatalogError.unsupported }
            let page = try ModelCatalog.decode(data, purpose: connection.purpose, serverFiltered: serverFiltered)
            if pageNumber > 1, page.total != nil, page.ids.isSubset(of: seenIDs) { throw ModelCatalogError.incomplete }
            seenIDs.formUnion(page.ids)
            known.formUnion(page.result.models); unknown.formUnion(page.result.unclassified)
            fetched += page.count
            guard var components = URLComponents(url: initialURL, resolvingAgainstBaseURL: false) else { throw CloudServiceError.invalidURL }
            var query = components.queryItems ?? []
            if let total = page.total, fetched < total {
                guard page.count > 0 else { throw ModelCatalogError.incomplete }
                query.removeAll { $0.name == "page_no" }
                query += [.init(name: "page_no", value: String(pageNumber + 1))]
            } else if page.hasMore {
                guard let cursor = page.lastID, ModelCatalog.validID(cursor), cursors.insert(cursor).inserted else {
                    throw ModelCatalogError.incomplete
                }
                query += [.init(name: "after", value: cursor)]
            } else {
                return .init(models: known.sorted(), unclassified: unknown.subtracting(known).sorted())
            }
            // Rebuild pagination on the configured origin; never forward the key to a returned next-page URL.
            components.queryItems = query
            guard let next = components.url else { throw CloudServiceError.invalidURL }
            url = next
        }
        throw ModelCatalogError.incomplete
    }
}
