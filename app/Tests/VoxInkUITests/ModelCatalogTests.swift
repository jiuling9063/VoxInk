import Foundation
import Testing
@testable import VoxInkUI

private actor CatalogTransport: ModelHTTPTransport {
    private(set) var requests: [URLRequest] = []
    private(set) var cancelled = false
    let body: String
    let status: Int
    let delay: Duration

    init(body: String = #"{"data":[{"id":"provider/model"}]}"#, status: Int = 200, delay: Duration = .zero) {
        self.body = body; self.status = status; self.delay = delay
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        do { try await Task.sleep(for: delay) }
        catch { cancelled = true; throw error }
        let url = try #require(request.url)
        return (Data(body.utf8), try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)))
    }
}

@MainActor private final class CatalogCredentials: ModelCredentialStorage {
    var values: [UUID: String] = [:]
    var reads: [UUID] = []
    var writes = 0
    func read(_ id: UUID) -> String? { reads.append(id); return values[id] }
    func write(_ value: String?, for id: UUID) { writes += 1; values[id] = value }
}

struct ModelCatalogTests {
    @Test(arguments: ModelServicePurpose.allCases)
    func filtersAtTheOfficialEndpointBeforeDisplaying(purpose: ModelServicePurpose) async throws {
        let transport = CatalogTransport()
        var connection = ModelProviderPreset.siliconFlow.makeConnection(for: purpose)
        // Fetching must work before a name, model or optional generation parameters are filled in.
        connection.name = ""; connection.model = ""; connection.extraBodyJSON = "unfinished"
        let result = try await CloudModelClient(connection: connection, apiKey: "fixture", transport: transport).fetchModels()
        #expect(result == ["provider/model"])
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
        #expect(request.url?.host == "api.siliconflow.cn")
        #expect(request.url?.path == "/v1/models")
        #expect(request.url?.query == "sub_type=\(purpose == .transcription ? "speech-to-text" : "chat")")
    }

    @Test func deduplicatesSortsAndRejectsMalformedIDs() async throws {
        let transport = CatalogTransport(body: #"{"data":[{"id":"z/model"},{"id":"a/model"},{"id":"a/model"},{"id":""},{"id":"  "},{"id":" padded"},{"id":"bad\nmodel"},{"id":"bad\u0000model"}]}"#)
        let result = try await CloudModelClient(connection: ModelProviderPreset.siliconFlow.makeConnection(for: .polishing),
                                               apiKey: "fixture", transport: transport).fetchModels()
        #expect(result == ["a/model", "z/model"])
    }

    @Test(arguments: ["https://api.siliconflow.cn.evil.example/v1", "http://api.siliconflow.cn/v1",
                      "https://api.siliconflow.cn/v2", "https://api.siliconflow.cn/v1?key=x",
                      "https://api.openai.com/v1", "https://api.siliconflow.cn:8443/v1"])
    func unsupportedEndpointsNeverReceiveCredentials(address: String) async {
        var connection = ModelProviderPreset.siliconFlow.makeConnection(for: .polishing)
        connection.baseURL = address
        let transport = CatalogTransport()
        #expect(!ModelCatalog.supports(connection))
        await #expect(throws: CloudServiceError.invalidConfiguration) {
            try await CloudModelClient(connection: connection, apiKey: "fixture", transport: transport).fetchModels()
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: ["", "   ", "one\nother", "one\rother"])
    func missingOrInvalidKeyDoesNotSend(key: String) async {
        let transport = CatalogTransport()
        await #expect(throws: CloudServiceError.authentication) {
            try await CloudModelClient(connection: ModelProviderPreset.siliconFlow.makeConnection(for: .polishing),
                                       apiKey: key, transport: transport).fetchModels()
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: [401, 403, 429, 500, 302])
    func reportsSafeErrors(status: Int) async {
        let transport = CatalogTransport(body: "secret provider body must not be shown", status: status)
        let expected: CloudServiceError = [401, 403].contains(status) ? .authentication : status == 429 ? .rateLimited : .http(status)
        await #expect(throws: expected) {
            try await CloudModelClient(connection: ModelProviderPreset.siliconFlow.makeConnection(for: .polishing),
                                       apiKey: "fixture", transport: transport).fetchModels()
        }
    }

    @Test(arguments: ["not-json", "{}", #"{"data":[{"name":"not-an-id"}]}"#])
    func rejectsInvalidResponses(body: String) async {
        await #expect(throws: CloudServiceError.invalidResponse) {
            try await CloudModelClient(connection: ModelProviderPreset.siliconFlow.makeConnection(for: .polishing),
                                       apiKey: "fixture", transport: CatalogTransport(body: body)).fetchModels()
        }
    }

    @Test func emptyCatalogIsNotAnError() async throws {
        let result = try await CloudModelClient(connection: ModelProviderPreset.siliconFlow.makeConnection(for: .polishing),
                                               apiKey: "fixture", transport: CatalogTransport(body: #"{"data":[]}"#)).fetchModels()
        #expect(result.isEmpty)
    }

    @Test func dismissingCancelsTheUnderlyingRequest() async throws {
        let transport = CatalogTransport(delay: .seconds(30))
        let task = Task {
            try await CloudModelClient(connection: ModelProviderPreset.siliconFlow.makeConnection(for: .polishing),
                                       apiKey: "fixture", transport: transport).fetchModels()
        }
        while await transport.requests.isEmpty { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.cancelled)
    }

    @MainActor @Test(arguments: [200, 401])
    func fetchNeverChangesSavedSettingsOrKeys(status: Int) async throws {
        let keys = CatalogCredentials(), transport = CatalogTransport(status: status)
        let store = AppStore(preferences: nil, modelCredentials: keys, modelTransport: transport)
        let connection = ModelProviderPreset.siliconFlow.makeConnection(for: .polishing)
        try store.saveAndSelectModelConnection(connection, apiKey: "saved-fixture")
        let before = store.modelServices, writes = keys.writes
        if status == 200 { #expect(try await store.fetchModels(for: connection) == ["provider/model"]) }
        else { await #expect(throws: CloudServiceError.authentication) { try await store.fetchModels(for: connection) } }
        #expect(store.modelServices == before)
        #expect(keys.writes == writes)
        #expect(keys.values[connection.id] == "saved-fixture")
        #expect(await transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer saved-fixture")
    }

    @MainActor @Test func unsavedKeyAndReusedKeyWorkWithoutSaving() async throws {
        let keys = CatalogCredentials(), transport = CatalogTransport()
        let store = AppStore(preferences: nil, modelCredentials: keys, modelTransport: transport)
        let source = ModelProviderPreset.siliconFlow.makeConnection(for: .transcription)
        try store.saveModelConnection(source, apiKey: "reused-fixture")
        var draft = ModelProviderPreset.siliconFlow.makeConnection(for: .polishing)
        draft.model = ""
        let before = store.modelServices, writes = keys.writes
        _ = try await store.fetchModels(for: draft, apiKey: "new-fixture")
        _ = try await store.fetchModels(for: draft, reuseKeyFrom: source.id)
        #expect(store.modelServices == before)
        #expect(keys.writes == writes)
        #expect(await transport.requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer new-fixture", "Bearer reused-fixture"])
    }

    @MainActor @Test func selectionDropsOnlyTheOldModelsDefaultParameters() throws {
        let store = AppStore(preferences: nil, modelCredentials: CatalogCredentials())
        var connection = ModelProviderPreset.siliconFlow.makeConnection(for: .polishing)
        try store.saveModelConnection(connection, apiKey: "fixture")
        try store.updateModelID(connection.id, model: "  " + connection.model + "  ")
        #expect(store.modelServices.connections.first?.extraBodyJSON == connection.extraBodyJSON)
        try store.updateModelID(connection.id, model: "provider/another-model")
        #expect(store.modelServices.connections.first?.extraBodyJSON == "{}")
        connection.extraBodyJSON = #"{"temperature":0.5}"#
        try store.saveModelConnection(connection, apiKey: nil)
        try store.updateModelID(connection.id, model: "provider/another-model")
        #expect(store.modelServices.connections.first?.extraBodyJSON == connection.extraBodyJSON)
    }

    @MainActor @Test func rejectsCredentialReuseAcrossProvidersAndChangedEndpoints() async throws {
        let keys = CatalogCredentials(), transport = CatalogTransport()
        let store = AppStore(preferences: nil, modelCredentials: keys, modelTransport: transport)
        let source = ModelProviderPreset.openAI.makeConnection(for: .transcription)
        try store.saveModelConnection(source, apiKey: "other-provider-fixture")
        let draft = ModelProviderPreset.siliconFlow.makeConnection(for: .polishing)
        await #expect(throws: CloudServiceError.invalidConfiguration) { try await store.fetchModels(for: draft, reuseKeyFrom: source.id) }
        var changed = source
        changed.baseURL = ModelProviderPreset.siliconFlow.baseURL
        await #expect(throws: CloudServiceError.addressChanged) { try await store.fetchModels(for: changed) }
        await #expect(throws: CloudServiceError.invalidConfiguration) { try await store.fetchModels(for: draft, clearKey: true) }
        #expect(keys.reads.isEmpty)
        #expect(await transport.requests.isEmpty)
    }
}
