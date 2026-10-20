import AVFoundation
import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

private func connection(_ purpose: ModelServicePurpose = .polishing, host: String = "models.example") -> ModelConnection {
    var value = ModelConnection()
    value.name = purpose.rawValue
    value.purpose = purpose
    value.baseURL = "https://\(host)/v1"
    value.model = "test-model"
    return value
}

private actor MockModelTransport: ModelHTTPTransport {
    var requests: [URLRequest] = []
    let status: Int
    let text: String
    let finish: String
    let delay: Duration
    let malformed: Bool
    private(set) var cancelled = false

    init(status: Int = 200, text: String = "明天开会。", finish: String = "stop", delay: Duration = .zero, malformed: Bool = false) {
        self.status = status; self.text = text; self.finish = finish; self.delay = delay; self.malformed = malformed
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        do { try await Task.sleep(for: delay) }
        catch { cancelled = true; throw error }
        let body: [String: Any] = request.url?.path.hasSuffix("audio/transcriptions") == true
            ? ["text": text]
            : ["choices": [["finish_reason": finish, "message": ["content": text]]]]
        return (malformed ? Data("not-json".utf8) : try JSONSerialization.data(withJSONObject: body),
                HTTPURLResponse(url: try #require(request.url), statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

@MainActor private final class MemoryModelCredentials: ModelCredentialStorage {
    var values: [UUID: String] = [:]
    var failWrites = false
    func read(_ id: UUID) throws -> String? { values[id] }
    func write(_ value: String?, for id: UUID) throws {
        if failWrites { throw CloudServiceError.keychain }
        values[id] = value
    }
}

private actor LocalFixtureTranscriber: TranscriptionService {
    private(set) var calls = 0
    private(set) var preparations = 0
    func prepare() async throws { preparations += 1 }
    func transcribe(url: URL) async throws -> String { calls += 1; return "明天开会" }
    func cancel() async {}
}

private actor LocalFixturePolisher: PolishingService {
    private(set) var calls = 0
    func polish(_ text: String, model: PolishModel) async throws -> PolishResult {
        calls += 1
        return .init(accepted: true, reason: "fixture", text: "明天开会。")
    }
}

private func signalFixture() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
    let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
    buffer.frameLength = 8000
    buffer.floatChannelData?[0].initialize(repeating: 0.01, count: 8000)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
    return url
}

struct CloudModelClientTests {
    @Test(arguments: ["http://example.com/v1", "https://key@example.com/v1", "https://example.com/v1?key=x", "file:///tmp/models", "https://example.com/v1#fragment"])
    func rejectsUnsafeAddresses(address: String) {
        var value = connection(); value.baseURL = address
        #expect(throws: CloudServiceError.invalidURL) { try value.validate() }
    }

    @Test func supportsVersionedBasesFullEndpointsAndLocalServers() throws {
        var value = connection()
        #expect(try value.endpointURL().absoluteString == "https://models.example/v1/chat/completions")
        value.baseURL = "https://models.example/custom/v2/chat/completions"
        #expect(try value.endpointURL().absoluteString == value.baseURL)
        value.baseURL = "http://127.0.0.1:1234/v1/"
        #expect(try value.endpointURL().absoluteString == "http://127.0.0.1:1234/v1/chat/completions")
    }

    @Test func chatRequestKeepsUserTextAsDataAndSupportsProviderParameters() async throws {
        let transport = MockModelTransport()
        var config = connection(); config.extraBodyJSON = #"{"enable_thinking":false,"max_tokens":512}"#
        let client = CloudModelClient(connection: config, apiKey: "fixture-key", transport: transport)
        let result = try await client.polish("明天开会", language: .mandarin)
        #expect(result.accepted)
        #expect(result.text == "明天开会。")
        let request = try #require(await transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-key")
        let requestData = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: requestData) as? [String: Any])
        #expect(body["stream"] as? Bool == false)
        #expect(body["enable_thinking"] as? Bool == false)
        #expect(body["max_tokens"] as? Int == 512)
        let messages = try #require(body["messages"] as? [[String: String]])
        let user = try JSONDecoder().decode([String: String].self, from: Data(try #require(messages.last?["content"]).utf8))
        #expect(user == ["source": "明天开会"])
    }

    @Test(arguments: [#"{"stream":true}"#, #"{"messages":[]}"#, #"{"model":"other"}"#, #"{"tools":[]}"#, "[]", "bad-json"])
    func rejectsOverrides(parameters: String) {
        var config = connection(); config.extraBodyJSON = parameters
        #expect(throws: CloudServiceError.invalidParameters) { try config.validate() }
    }

    @Test func transcriptionMultipartContainsAudioModelAndLanguageWithoutLocalPath() async throws {
        let url = try signalFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = MockModelTransport(text: "会议开始。")
        let client = CloudModelClient(connection: connection(.transcription), apiKey: nil, transport: transport)
        #expect(try await client.transcribe(url: url, language: .mandarin) == "会议开始。")
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/v1/audio/transcriptions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let body = try #require(request.httpBody)
        #expect(body.range(of: try Data(contentsOf: url)) != nil)
        let prefix = String(decoding: body.prefix(1000), as: UTF8.self)
        #expect(prefix.contains("name=\"model\"\r\n\r\ntest-model"))
        #expect(prefix.contains("name=\"language\"\r\n\r\nzh"))
        #expect(prefix.contains("filename=\"audio.wav\""))
        #expect(!prefix.contains(url.path))
    }

    @Test func automaticLanguageDoesNotForceChinese() async throws {
        let url = try signalFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = MockModelTransport()
        _ = try await CloudModelClient(connection: connection(.transcription), apiKey: nil, transport: transport).transcribe(url: url, language: .automatic)
        let body = try #require(await transport.requests.first?.httpBody)
        #expect(!String(decoding: body.prefix(700), as: UTF8.self).contains("name=\"language\""))
    }

    @Test(arguments: [(401, CloudServiceError.authentication), (403, .authentication), (429, .rateLimited), (503, .http(503)), (302, .http(302))])
    func mapsHTTPFailuresWithoutEchoingResponse(status: Int, expected: CloudServiceError) async {
        let client = CloudModelClient(connection: connection(), apiKey: nil, transport: MockModelTransport(status: status, text: "private-provider-body"))
        await #expect(throws: expected) { try await client.polish("明天开会", language: .mandarin) }
        #expect(!expected.localizedDescription.contains("private-provider-body"))
    }

    @Test func malformedOrTruncatedResponsesAreNotAccepted() async {
        for transport in [MockModelTransport(malformed: true), MockModelTransport(finish: "length")] {
            await #expect(throws: CloudServiceError.invalidResponse) {
                try await CloudModelClient(connection: connection(), apiKey: nil, transport: transport).polish("明天开会", language: .mandarin)
            }
        }
    }

    @Test func inventedAnswerIsRejectedAndSourcePreserved() async throws {
        let client = CloudModelClient(connection: connection(), apiKey: nil, transport: MockModelTransport(text: "法国首都是巴黎。"))
        let source = "请问法国首都是什么？"
        let result = try await client.polish(source, language: .mandarin)
        #expect(!result.accepted)
        #expect(result.text == source)
    }

    @Test func totalDeadlineCancelsTransport() async {
        var config = connection(); config.timeoutSeconds = 1
        let transport = MockModelTransport(delay: .seconds(30))
        await #expect(throws: CloudServiceError.timeout) {
            try await CloudModelClient(connection: config, apiKey: nil, transport: transport).polish("明天开会", language: .mandarin)
        }
        #expect(await transport.cancelled)
    }

    @Test func cancellationPropagatesToTransport() async throws {
        let transport = MockModelTransport(delay: .seconds(30))
        let task = Task { try await CloudModelClient(connection: connection(), apiKey: nil, transport: transport).polish("明天开会", language: .mandarin) }
        for _ in 0..<100 {
            if await !transport.requests.isEmpty { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.cancelled)
    }

    @Test func noSpeechNeverUploads() async throws {
        let url = try signalFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = MockModelTransport()
        let service = CloudTranscriptionService(client: .init(connection: connection(.transcription), apiKey: nil, transport: transport), speechDetector: { _ in false })
        await #expect(throws: QwenTranscriptionService.ServiceError.noSpeechDetected) { try await service.transcribe(url: url) }
        #expect(await transport.requests.isEmpty)
    }
}

@MainActor struct ModelConnectionSettingsTests {
    @Test func persistsIndependentSelectionsWithoutCredentials() throws {
        let suite = "VoxInk.CloudTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keys = MemoryModelCredentials()
        let store = AppStore(preferences: defaults, modelCredentials: keys)
        let asr = connection(.transcription), polish = connection(.polishing)
        try store.saveModelConnection(asr, apiKey: "fixture-asr-key")
        try store.saveModelConnection(polish, apiKey: "fixture-polish-key")
        try store.selectModelService(asr.id, for: .transcription)
        try store.selectModelService(polish.id, for: .polishing)
        let restored = AppStore(preferences: defaults, modelCredentials: keys)
        #expect(restored.modelServices.transcriptionID == asr.id)
        #expect(restored.modelServices.polishingID == polish.id)
        let json = String(decoding: try #require(defaults.data(forKey: "modelServices.v1")), as: UTF8.self)
        #expect(!json.contains("fixture-asr-key"))
        #expect(!json.contains("fixture-polish-key"))
        #expect(try keys.read(asr.id) == "fixture-asr-key")
    }

    @Test func failedKeychainWriteDoesNotSaveConnection() {
        let keys = MemoryModelCredentials(); keys.failWrites = true
        let store = AppStore(preferences: nil, modelCredentials: keys)
        #expect(throws: CloudServiceError.keychain) { try store.saveModelConnection(connection(), apiKey: "fixture") }
        #expect(store.modelServices.connections.isEmpty)
    }

    @Test func editingAddressRequiresNewKeyOrExplicitRemoval() throws {
        let keys = MemoryModelCredentials(), store = AppStore(preferences: nil, modelCredentials: MemoryModelCredentials())
        var config = connection()
        try store.saveModelConnection(config, apiKey: "fixture")
        config.baseURL = "https://another.example/v1"
        #expect(throws: CloudServiceError.addressChanged) { try store.saveModelConnection(config, apiKey: nil) }
        try store.saveModelConnection(config, apiKey: nil, clearKey: true)
        #expect(store.modelServices.connections.first?.baseURL == config.baseURL)
        let other = AppStore(preferences: nil, modelCredentials: keys)
        try other.saveModelConnection(config, apiKey: "first")
        config.name = "renamed"
        try other.saveModelConnection(config, apiKey: nil)
        #expect(try keys.read(config.id) == "first")
        try other.deleteModelConnection(config.id)
        #expect(try keys.read(config.id) == nil)
    }

    @Test func protectsActiveConnectionsAndRejectsWrongPurpose() throws {
        let store = AppStore(preferences: nil, modelCredentials: MemoryModelCredentials())
        var config = connection(.transcription)
        try store.saveModelConnection(config, apiKey: nil)
        #expect(throws: CloudServiceError.missingConnection) { try store.selectModelService(config.id, for: .polishing) }
        try store.selectModelService(config.id, for: .transcription)
        #expect(throws: CloudServiceError.connectionInUse) { try store.deleteModelConnection(config.id) }
        config.purpose = .polishing
        #expect(throws: CloudServiceError.connectionInUse) { try store.saveModelConnection(config, apiKey: nil) }
    }

    @Test func cloudPreparationDoesNotLoadLocalModel() async throws {
        let local = LocalFixtureTranscriber()
        let store = AppStore(service: local, preferences: nil, modelCredentials: MemoryModelCredentials(), microphoneStatus: { .authorized })
        let config = connection(.transcription)
        try store.saveModelConnection(config, apiKey: nil)
        try store.selectModelService(config.id, for: .transcription)
        store.refreshPermissions()
        #expect(store.canRecord)
        #expect(store.modelState == .notLoaded)
        store.warmUp()
        store.installModel()
        #expect(await local.preparations == 0)
        await store.shutdown()
    }

    @Test func localTranscriptionAndCloudPolishingWorkWithoutLocalPolishModels() async throws {
        let transport = MockModelTransport(), local = LocalFixtureTranscriber(), keys = MemoryModelCredentials()
        let store = AppStore(polishDeviceProvider: { .init(memoryGB: 4, appleSilicon: false) }, polishInventory: { [] },
                             service: local, preferences: nil, modelCredentials: keys, modelTransport: transport, audioCleaner: { _ in })
        let config = connection()
        try store.saveModelConnection(config, apiKey: nil)
        try store.selectModelService(config.id, for: .polishing)
        store.setPolishingEnabled(true)
        await store.handlePolishMemoryPressure(2)
        await store.transcribePrepared(URL(fileURLWithPath: "/fixture.wav"))
        #expect(await local.calls == 1)
        #expect(await transport.requests.count == 1)
        #expect(store.rawTranscript == "明天开会")
        #expect(store.transcript == "明天开会。")
        await store.shutdown()
    }

    @Test func cloudTranscriptionAndLocalPolishingUseIndependentServices() async throws {
        let url = try signalFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let transport = MockModelTransport(text: "明天开会"), local = LocalFixtureTranscriber(), polisher = LocalFixturePolisher()
        let store = AppStore(polishingService: polisher, polishInventory: { [.balanced] }, service: local,
                             preferences: nil, modelCredentials: MemoryModelCredentials(), modelTransport: transport,
                             cloudSpeechDetector: { _ in true }, audioCleaner: { _ in })
        let config = connection(.transcription)
        try store.saveModelConnection(config, apiKey: nil)
        try store.selectModelService(config.id, for: .transcription)
        store.setPolishingEnabled(true)
        await store.transcribePrepared(url)
        #expect(await local.calls == 0)
        #expect(await polisher.calls == 1)
        #expect(await transport.requests.first?.url?.path == "/v1/audio/transcriptions")
        #expect(store.transcript == "明天开会。")
        #expect(store.modelState == .notLoaded)
        await store.shutdown()
    }

    @Test func cloudFailurePreservesUnpolishedText() async throws {
        let store = AppStore(service: LocalFixtureTranscriber(), preferences: nil, modelCredentials: MemoryModelCredentials(),
                             modelTransport: MockModelTransport(status: 429), audioCleaner: { _ in })
        let config = connection()
        try store.saveModelConnection(config, apiKey: nil)
        try store.selectModelService(config.id, for: .polishing)
        store.setPolishingEnabled(true)
        await store.transcribePrepared(URL(fileURLWithPath: "/fixture.wav"))
        #expect(store.transcript == "明天开会")
        #expect(store.phase == .ready)
        #expect(store.polishMessage.contains("限流"))
        await store.shutdown()
    }

    @Test func cloudTranscriptionFailureDoesNotMarkLocalModelBrokenOrFallback() async throws {
        let url = try signalFixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let local = LocalFixtureTranscriber()
        let store = AppStore(service: local, preferences: nil, modelCredentials: MemoryModelCredentials(), modelTransport: MockModelTransport(status: 401),
                             cloudSpeechDetector: { _ in true }, audioCleaner: { _ in })
        let config = connection(.transcription)
        try store.saveModelConnection(config, apiKey: nil)
        try store.selectModelService(config.id, for: .transcription)
        await store.transcribePrepared(url)
        #expect(store.phase == .failed)
        #expect(store.recovery == .configureService)
        #expect(store.modelState == .notLoaded)
        #expect(await local.calls == 0)
        #expect(store.sessionHistory.isEmpty)
        await store.shutdown()
    }

    @Test func cancellingConnectionTestClearsProgressAndDoesNotStoreAResult() async throws {
        let transport = MockModelTransport(delay: .seconds(30))
        let store = AppStore(service: LocalFixtureTranscriber(), preferences: nil, modelCredentials: MemoryModelCredentials(), modelTransport: transport)
        let config = connection()
        try store.saveModelConnection(config, apiKey: nil)
        store.testModelConnection(config.id)
        for _ in 0..<100 {
            if await !transport.requests.isEmpty { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await transport.requests.count == 1)
        await store.cancel()
        #expect(await transport.cancelled)
        #expect(store.connectionTestMessage == L("已取消 · 未发出粘贴"))
        #expect(store.transcript.isEmpty)
        #expect(store.sessionHistory.isEmpty)
        #expect(store.phase == .ready)
        await store.shutdown()
    }

    @Test func cancelCloudRequestBlocksLateResultAndConfigurationChanges() async throws {
        let transport = MockModelTransport(delay: .seconds(30))
        let store = AppStore(service: LocalFixtureTranscriber(), preferences: nil, modelCredentials: MemoryModelCredentials(), modelTransport: transport,
                             audioPreparer: { $0 }, audioCleaner: { _ in })
        let config = connection()
        try store.saveModelConnection(config, apiKey: nil)
        try store.selectModelService(config.id, for: .polishing)
        store.setPolishingEnabled(true)
        store.importAudio(URL(fileURLWithPath: "/fixture.wav"))
        for _ in 0..<100 {
            if await !transport.requests.isEmpty { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(throws: CloudServiceError.busy) { try store.selectModelService(nil, for: .polishing) }
        await store.cancel()
        #expect(await transport.cancelled)
        #expect(store.sessionHistory.isEmpty)
        #expect(store.phase == .ready)
        await store.shutdown()
    }
}

struct CloudModelWireTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOXINK_TEST_HTTP_BASE_URL"] != nil))
    func realURLSessionPostsJSONMultipartAndRefusesRedirects() async throws {
        let base = try #require(ProcessInfo.processInfo.environment["VOXINK_TEST_HTTP_BASE_URL"])
        // This opt-in fixture must be local; it never uses account credentials.
        let host = try #require(URL(string: base)?.host)
        #expect(host == "127.0.0.1")
        guard host == "127.0.0.1" else { return }
        var config = connection(); config.baseURL = base
        let transport = ModelURLSessionTransport()
        let client = CloudModelClient(connection: config, apiKey: "wire-fixture", transport: transport)
        let result = try await client.polish("明天开会", language: .mandarin)
        #expect(result.accepted)
        #expect(result.text == "明天开会。")
        let audio = try signalFixture()
        defer { try? FileManager.default.removeItem(at: audio) }
        config.purpose = .transcription
        let transcript = try await CloudModelClient(connection: config, apiKey: "wire-fixture", transport: transport).transcribe(url: audio, language: .english)
        #expect(transcript == "File transcription fixture.")
        config.purpose = .polishing
        config.baseURL = base + "/redirect"
        await #expect(throws: CloudServiceError.http(307)) {
            try await CloudModelClient(connection: config, apiKey: "wire-fixture", transport: transport).polish("明天开会", language: .mandarin)
        }
    }
}
