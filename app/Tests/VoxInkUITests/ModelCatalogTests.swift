import Foundation
import Testing
@testable import VoxInkUI

private actor CatalogTransport: ModelHTTPTransport {
    private(set) var requests: [URLRequest] = []
    private(set) var cancelled = false
    let body: String
    let status: Int
    let delay: Duration
    let pages: [String]?

    init(body: String = #"{"data":[{"id":"provider/model"}]}"#, status: Int = 200, delay: Duration = .zero, pages: [String]? = nil) {
        self.body = body; self.status = status; self.delay = delay; self.pages = pages
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        do { try await Task.sleep(for: delay) }
        catch { cancelled = true; throw error }
        let url = try #require(request.url)
        let response = pages.map { $0[min(requests.count - 1, $0.count - 1)] } ?? body
        return (Data(response.utf8), try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)))
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
    @Test(arguments: ModelProviderPreset.allCases)
    func everyProviderCanFetchUsingItsConfiguredAddress(provider: ModelProviderPreset) async throws {
        var connection = provider.makeConnection(for: .polishing)
        if provider == .custom { connection.baseURL = "https://custom.example/company/v2" }
        let transport = CatalogTransport()
        let result = try await CloudModelClient(connection: connection, apiKey: "fixture", transport: transport).fetchModels()
        #expect(result.models + result.unclassified == ["provider/model"])
        let request = try #require(await transport.requests.first)
        #expect(request.url?.host == URL(string: connection.baseURL)?.host)
        #expect(request.url?.path.hasSuffix("/models") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
    }

    @Test(arguments: ["https://custom.example/prefix/v2", "https://custom.example/prefix/v2/",
                      "https://custom.example/prefix/v2/chat/completions", "https://custom.example/prefix/v2/chat/completions/"])
    func normalizesBaseAndCompleteChatEndpoints(address: String) throws {
        var connection = ModelConnection(); connection.baseURL = address
        #expect(try ModelCatalog.url(for: connection).absoluteString == "https://custom.example/prefix/v2/models")
    }

    @Test func completeTranscriptionURLAndAnonymousLocalServer() async throws {
        var connection = ModelConnection(); connection.purpose = .transcription
        connection.baseURL = "http://127.0.0.1:9876/custom/v1/audio/transcriptions"
        let transport = CatalogTransport()
        let result = try await CloudModelClient(connection: connection, apiKey: nil, transport: transport).fetchModels()
        #expect(result.unclassified == ["provider/model"])
        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "http://127.0.0.1:9876/custom/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func officialMetadataFiltersWithoutDroppingUnknownIDs() throws {
        let body = #"{"data":[{"id":"private-chat","input_modalities":["text","image"],"output_modalities":["text"]},{"id":"speech","sub_type":"speech-to-text"},{"id":"pictures","architecture":{"input_modalities":["text"],"output_modalities":["image"]}},{"id":"vectors","type":"embedding"},{"id":"rank","type":"reranker"},{"id":"voice","capabilities":["TTS"]},{"id":"disabled","type":"chat","active":false},{"id":"opaque-deployment"}]}"#
        let chat = try ModelCatalog.decode(Data(body.utf8), purpose: .polishing, serverFiltered: false).result
        #expect(chat.models == ["private-chat"])
        #expect(chat.unclassified == ["opaque-deployment"])
        let speech = try ModelCatalog.decode(Data(body.utf8), purpose: .transcription, serverFiltered: false).result
        #expect(speech.models == ["speech"])
        #expect(speech.unclassified == ["opaque-deployment"])
    }

    @Test func commonSpecializedIDsDoNotCrowdThePolishingList() throws {
        let ids = ["gpt-4.1-mini", "whisper-1", "gpt-4o-mini-transcribe", "Qwen/Qwen3-ASR-1.7B",
                   "FunAudioLLM/SenseVoiceSmall", "text-embedding-3-small", "tts-1", "dall-e-3", "bge-m3", "reranker-v1"]
        let data = try JSONSerialization.data(withJSONObject: ["data": ids.map { ["id": $0] }])
        let chat = try ModelCatalog.decode(data, purpose: .polishing, serverFiltered: false).result
        #expect(chat.models.isEmpty)
        #expect(chat.unclassified == ["gpt-4.1-mini"])
        let speech = try ModelCatalog.decode(data, purpose: .transcription, serverFiltered: false).result
        #expect(Set(speech.models) == Set(ids[1...4]))
    }

    @Test func dashScopeAdapterUsesNativePathAndFollowsAllPages() async throws {
        let transport = CatalogTransport(pages: [
            #"{"output":{"total":2,"models":[{"model":"one","capabilities":["TG"]}]}}"#,
            #"{"output":{"total":2,"models":[{"model":"two","inference_metadata":{"request_modality":["Text"],"response_modality":["Text"]}}]}}"#])
        let connection = ModelProviderPreset.dashScope.makeConnection(for: .polishing)
        let result = try await CloudModelClient(connection: connection, apiKey: "fixture", transport: transport).fetchModels()
        #expect(result.models == ["one", "two"])
        let requests = await transport.requests
        #expect(requests.count == 2)
        for (index, request) in requests.enumerated() {
            let url = try #require(request.url)
            #expect(url.host == "dashscope.aliyuncs.com")
            #expect(url.path == "/api/v1/models")
            let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            #expect(query.filter { $0.name == "page_no" }.map(\.value) == [String(index + 1)])
            #expect(query.contains(.init(name: "capabilities", value: "TG")))
        }
    }

    @Test func cursorPaginationNeverForwardsKeysToReturnedURLs() async throws {
        let transport = CatalogTransport(pages: [
            #"{"data":[{"id":"first","type":"chat"}],"has_more":true,"last_id":"first","next":"https://other.example/steal"}"#,
            #"{"data":[{"id":"second","type":"chat"}],"has_more":false}"#])
        var connection = ModelConnection(); connection.baseURL = "https://custom.example/v1"
        let result = try await CloudModelClient(connection: connection, apiKey: "fixture", transport: transport).fetchModels()
        #expect(result.models == ["first", "second"])
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.url?.host == "custom.example" })
        #expect(requests.last?.url?.query == "after=first")
    }

    @Test(arguments: [#"{"data":[{"id":"same"}],"has_more":true}"#,
                      #"{"output":{"total":3,"models":[{"model":"same"}]}}"#])
    func repeatedPagesFailInsteadOfReturningAPartialCatalog(body: String) async {
        let transport = CatalogTransport(body: body)
        await #expect(throws: ModelCatalogError.incomplete) {
            try await CloudModelClient(connection: ModelProviderPreset.deepSeek.makeConnection(for: .polishing),
                                       apiKey: "fixture", transport: transport).fetchModels()
        }
        #expect(await transport.requests.count == 2)
    }

    @Test(arguments: [404, 405, 501])
    func unavailableCatalogHasAnExplicitError(status: Int) async {
        await #expect(throws: ModelCatalogError.unsupported) {
            try await CloudModelClient(connection: ModelProviderPreset.volcengine.makeConnection(for: .polishing),
                                       apiKey: "fixture", transport: CatalogTransport(status: status)).fetchModels()
        }
    }

    @Test func boundsTheWholeFetchByTheConfiguredTimeout() async {
        var connection = ModelProviderPreset.deepSeek.makeConnection(for: .polishing); connection.timeoutSeconds = 1
        await #expect(throws: CloudServiceError.timeout) {
            try await CloudModelClient(connection: connection, apiKey: "fixture", transport: CatalogTransport(delay: .seconds(10))).fetchModels()
        }
    }

    @Test(arguments: ModelServicePurpose.allCases)
    func filtersAtTheOfficialEndpointBeforeDisplaying(purpose: ModelServicePurpose) async throws {
        let transport = CatalogTransport()
        var connection = ModelProviderPreset.siliconFlow.makeConnection(for: purpose)
        // Fetching must work before a name, model or optional generation parameters are filled in.
        connection.name = ""; connection.model = ""; connection.extraBodyJSON = "unfinished"
        let result = try await CloudModelClient(connection: connection, apiKey: "fixture", transport: transport).fetchModels()
        #expect(result.models == ["provider/model"])
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
        #expect(result.models == ["a/model", "z/model"])
    }

    @Test(arguments: ["http://api.siliconflow.cn/v1", "https://example.com/v1?key=x",
                      "https://user@example.com/v1", "file:///tmp/api"])
    func unsafeEndpointsNeverReceiveCredentials(address: String) async {
        var connection = ModelProviderPreset.siliconFlow.makeConnection(for: .polishing)
        connection.baseURL = address
        let transport = CatalogTransport()
        await #expect(throws: CloudServiceError.invalidURL) {
            try await CloudModelClient(connection: connection, apiKey: "fixture", transport: transport).fetchModels()
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: ["one\nother", "one\rother"])
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
        if status == 200 { #expect(try await store.fetchModels(for: connection).models == ["provider/model"]) }
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

    @MainActor @Test func customKeysStayAtTheirSavedAddressUnlessANewKeyIsProvided() async throws {
        let keys = CatalogCredentials(), transport = CatalogTransport()
        let store = AppStore(preferences: nil, modelCredentials: keys, modelTransport: transport)
        var first = ModelConnection(); first.name = "Custom"; first.model = "private-model"
        first.baseURL = "https://one.example/v1"
        try store.saveModelConnection(first, apiKey: "first-fixture")
        _ = try await store.fetchModels(for: first)
        var changed = first; changed.baseURL = "https://two.example/v1"
        await #expect(throws: CloudServiceError.addressChanged) { try await store.fetchModels(for: changed) }
        var second = first; second.id = UUID(); second.purpose = .transcription
        second.baseURL = "https://three.example/v1"
        try store.saveModelConnection(second, apiKey: "third-fixture")
        await #expect(throws: CloudServiceError.invalidConfiguration) { try await store.fetchModels(for: first, reuseKeyFrom: second.id) }
        #expect(keys.reads == [first.id])
        _ = try await store.fetchModels(for: changed, apiKey: "new-fixture")
        let requests = await transport.requests
        #expect(requests.map { $0.url?.host } == ["one.example", "two.example"])
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer first-fixture", "Bearer new-fixture"])
    }
}
