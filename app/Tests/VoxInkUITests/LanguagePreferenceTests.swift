import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

private actor LanguageTranscriber: TranscriptionService {
    let text: String
    init(text: String = "図書館で資料を確認します。") { self.text = text }
    var received: SpeechLanguage?
    func prepare() async throws {}
    func cancel() async {}
    func transcribe(url: URL) async throws -> String { "unexpected legacy request" }
    func transcribe(url: URL, language: SpeechLanguage) async throws -> String {
        received = language
        return text
    }
}

private actor LanguagePolisher: PolishingService {
    private(set) var received: SpeechLanguage?
    func polish(_ text: String, model: PolishModel) async throws -> PolishResult {
        .init(accepted: true, reason: "checks_passed", text: text)
    }
    func polish(_ text: String, model: PolishModel, timeout: Duration, language: SpeechLanguage) async throws -> PolishResult {
        received = language
        return .init(accepted: true, reason: "checks_passed", text: text)
    }
}

private actor LanguageDictionaryStorage: UserDictionaryStorage {
    let entries: [UserDictionaryEntry]
    init(entries: [UserDictionaryEntry]) { self.entries = entries }
    func load() async throws -> [UserDictionaryEntry] { entries }
    func save(_ entries: [UserDictionaryEntry]) async throws {}
}

@MainActor struct LanguagePreferenceTests {
    @Test func preferencesPersistIndependentlyAndSystemChoiceClearsOverride() throws {
        let name = "VoxInk.Language.\(UUID())"
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let store = AppStore(preferences: preferences)
        #expect(store.speechLanguage == .automatic)
        store.setInterfaceLanguage(.korean)
        store.setSpeechLanguage(.cantonese)
        store.setChineseOutput(.traditional)
        let restored = AppStore(preferences: preferences)
        #expect(restored.interfaceLanguage == .korean)
        #expect(restored.speechLanguage == .cantonese)
        #expect(restored.chineseOutput == .traditional)
        #expect(preferences.stringArray(forKey: "AppleLanguages") == ["ko"])
        restored.setInterfaceLanguage(.system)
        #expect(preferences.persistentDomain(forName: name)?["AppleLanguages"] == nil)
    }

    @Test func selectedLanguageReachesRecognitionAndKeepsJapaneseScript() async {
        let service = LanguageTranscriber()
        let store = AppStore(service: service, preferences: nil)
        store.setSpeechLanguage(.japanese)
        await store.transcribePrepared(URL(fileURLWithPath: "/language-fixture.wav"))
        #expect(await service.received == .japanese)
        #expect(store.transcript == "図書館で資料を確認します。")
        #expect(store.rawTranscript == store.transcript)
    }

    @Test func languageCannotChangeDuringShortcutRecording() {
        let store = AppStore(preferences: nil)
        store.configureShortcutRegistration { _ in true }
        #expect(store.beginShortcutRecording())
        store.setSpeechLanguage(.japanese)
        store.setChineseOutput(.traditional)
        store.setInterfaceLanguage(.english)
        #expect(store.speechLanguage == .automatic && store.chineseOutput == .simplified && store.interfaceLanguage == .system)
        store.finishShortcutRecording()
    }

    @Test func polishingKeepsDictionaryScriptAndReceivesLanguage() async throws {
        let dictionary = UserDictionaryController(storage: LanguageDictionaryStorage(entries: [
            try .init(source: "雨落", replacement: "語落")
        ]))
        await dictionary.load()
        let polisher = LanguagePolisher()
        let store = AppStore(polishingService: polisher, polishDeviceProvider: { .init(memoryGB: 16) },
                             polishInventory: { [.balanced] }, service: LanguageTranscriber(text: "请打开雨落。"),
                             preferences: nil, dictionary: dictionary)
        store.setSpeechLanguage(.mandarin)
        store.setPolishingEnabled(true)
        await store.transcribePrepared(URL(fileURLWithPath: "/language-fixture.wav"))
        #expect(await polisher.received == .mandarin)
        #expect(store.transcript == "请打开語落。")
        #expect(store.rawTranscript == "请打开雨落。")
        await store.shutdown()
    }
}
