import Foundation
import Testing
@testable import VoxInkUI

struct ModelProviderPresetTests {
    @Test func credentialReusePrefersSelectedProviderAccountAndExcludesCustomHosts() {
        var settings = ModelServiceSettings()
        let first = ModelProviderPreset.siliconFlow.makeConnection(for: .transcription)
        let selected = ModelProviderPreset.siliconFlow.makeConnection(for: .transcription)
        settings.connections = [first, selected]
        settings.transcriptionID = selected.id
        var target = ModelProviderPreset.siliconFlow.makeConnection(for: .polishing)
        #expect(settings.credentialSource(for: target)?.id == selected.id)
        target.baseURL += "/different-account"
        #expect(settings.credentialSource(for: target) == nil)
        #expect(settings.credentialSource(for: ModelProviderPreset.openAI.makeConnection(for: .polishing)) == nil)
    }

    @Test func audioCatalogOnlyIncludesCompatibleProviders() {
        #expect(ModelProviderPreset.available(for: .transcription) == [.siliconFlow, .openAI, .groq, .custom])
        #expect(ModelProviderPreset.available(for: .polishing).count == 11)
    }

    @Test(arguments: ModelProviderPreset.allCases.filter { $0 != .custom })
    func presetsUseValidHTTPSChatEndpoints(provider: ModelProviderPreset) throws {
        var connection = provider.makeConnection(for: .polishing)
        if connection.model.isEmpty { connection.model = "account-selected-model" }
        try connection.validate()
        let endpoint = try connection.endpointURL()
        #expect(endpoint.scheme == "https")
        #expect(endpoint.path.hasSuffix("/chat/completions"))
        #expect(provider.consoleURL?.scheme == "https")
        #expect(provider.documentationURL?.scheme == "https")
    }

    @Test(arguments: [ModelProviderPreset.siliconFlow, .openAI, .groq])
    func audioPresetsHaveModelsAndAudioEndpoints(provider: ModelProviderPreset) throws {
        let connection = provider.makeConnection(for: .transcription)
        try connection.validate()
        #expect(try connection.endpointURL().path.hasSuffix("/audio/transcriptions"))
        #expect(try connection.extraBody().isEmpty)
    }

    @Test func editingLegacyConnectionDoesNotReplaceSettings() {
        var saved = ModelProviderPreset.siliconFlow.makeConnection(for: .polishing)
        saved.name = "My connection"
        saved.model = "custom-model"
        saved.timeoutSeconds = 45
        saved.extraBodyJSON = #"{"temperature":0.2}"#
        let draft = ModelConnectionDraft(connection: saved, isExisting: true)
        #expect(draft.provider == .siliconFlow)
        #expect(draft.connection == saved)
        #expect(!draft.needsKey)
        #expect(draft.canSave)
    }

    @Test func switchingProviderResetsUnsavedCredentialAndParameters() {
        var draft = ModelConnectionDraft(connection: ModelProviderPreset.siliconFlow.makeConnection(for: .polishing), isExisting: true)
        let id = draft.connection.id
        draft.apiKey = "test-only-not-a-credential"
        draft.selectProvider(.openAI)
        #expect(draft.connection.id == id)
        #expect(draft.connection.baseURL == ModelProviderPreset.openAI.baseURL)
        #expect(draft.connection.model == "gpt-4.1-mini")
        #expect(draft.connection.extraBodyJSON == "{}")
        #expect(draft.apiKey.isEmpty)
        #expect(draft.endpointChanged)
        #expect(draft.needsKey)
        #expect(!draft.canSave)
    }

    @Test func purposeChangeDoesNotAdvertiseUnsupportedAudioEndpoint() {
        var draft = ModelConnectionDraft(connection: ModelProviderPreset.deepSeek.makeConnection(for: .polishing), isExisting: false)
        draft.selectPurpose(.transcription)
        #expect(draft.provider == .custom)
        #expect(draft.connection.baseURL.isEmpty)
        #expect(draft.connection.model.isEmpty)
        #expect(!draft.canSave)
    }

    @Test func supportedPurposeChangeUpdatesModelAndPreservesIdentity() {
        var draft = ModelConnectionDraft(connection: ModelProviderPreset.siliconFlow.makeConnection(for: .polishing), isExisting: false)
        let id = draft.connection.id
        draft.selectPurpose(.transcription)
        #expect(draft.provider == .siliconFlow)
        #expect(draft.connection.id == id)
        #expect(draft.connection.model == "FunAudioLLM/SenseVoiceSmall")
        #expect(draft.connection.extraBodyJSON == "{}")
    }

    @Test func customConnectionsStayEditableWithoutAuthentication() {
        var connection = ModelConnection()
        connection.name = "Local server"
        connection.baseURL = "http://localhost:8000/v1"
        connection.model = "local-model"
        let draft = ModelConnectionDraft(connection: connection, isExisting: false)
        #expect(draft.provider == .custom)
        #expect(draft.canSave)
    }

    @Test func newCloudConnectionRequiresCredentialButSelectingCustomPreservesFields() {
        var draft = ModelConnectionDraft(connection: ModelProviderPreset.openAI.makeConnection(for: .polishing), isExisting: false)
        #expect(draft.needsKey)
        draft.apiKey = "test-only-not-a-credential"
        #expect(draft.canSave)
        let connection = draft.connection
        draft.selectProvider(.custom)
        #expect(draft.connection == connection)
    }

    @Test func providerMatchingRequiresExactEndpoint() {
        var connection = ModelProviderPreset.siliconFlow.makeConnection(for: .polishing)
        connection.baseURL = "https://api.siliconflow.cn/v1/chat/completions"
        #expect(ModelProviderPreset.matching(connection) == .siliconFlow)
        connection.baseURL = "https://api.siliconflow.cn.untrusted.example/v1"
        #expect(ModelProviderPreset.matching(connection) == .custom)
    }

    @Test func changingModelClearsOnlyUntouchedPresetParameters() {
        var draft = ModelConnectionDraft(connection: ModelProviderPreset.siliconFlow.makeConnection(for: .polishing), isExisting: false)
        draft.updateModel("another-model")
        #expect(draft.connection.extraBodyJSON == "{}")
        draft.connection.extraBodyJSON = #"{"temperature":0.3}"#
        draft.updateModel("my-model")
        #expect(draft.connection.extraBodyJSON == #"{"temperature":0.3}"#)
    }
}
