import Foundation

enum ModelCatalog {
    static func supports(_ connection: ModelConnection) -> Bool {
        ModelProviderPreset.matching(connection) == .siliconFlow
    }
}

extension CloudModelClient {
    func fetchModels() async throws -> [String] {
        guard ModelCatalog.supports(connection),
              connection.timeoutSeconds.isFinite, (1...120).contains(connection.timeoutSeconds) else {
            throw CloudServiceError.invalidConfiguration
        }
        guard let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty,
              !key.contains("\r"), !key.contains("\n") else { throw CloudServiceError.authentication }

        // The official subtype filter is capability evidence; model names are not.
        guard var components = URLComponents(string: ModelProviderPreset.siliconFlow.baseURL + "/models") else {
            throw CloudServiceError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "sub_type", value:
            connection.purpose == .transcription ? "speech-to-text" : "chat")]
        guard let url = components.url else { throw CloudServiceError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: connection.timeoutSeconds)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        let data = try await send(request)
        struct Response: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw CloudServiceError.invalidResponse
        }
        // Keep exact API IDs, but reject blank or malformed entries rather than silently rewriting them.
        let ids = response.data.map(\.id).filter {
            !$0.isEmpty && $0.count <= 512 && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines)
                && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
        }
        return Array(Set(ids)).sorted()
    }
}
