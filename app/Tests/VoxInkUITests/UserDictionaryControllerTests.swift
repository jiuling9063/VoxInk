import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

private actor DictionaryMemoryStore: UserDictionaryStorage {
    var entries: [UserDictionaryEntry] = []
    var loadFails = false
    var saveFails = false
    private(set) var writes = 0
    var blockSave = false
    var saveContinuation: CheckedContinuation<Void, Never>?
    init(loadFails: Bool = false) { self.loadFails = loadFails }
    func setSaveFailure(_ value: Bool) { saveFails = value }
    func blockNextSave() { blockSave = true }
    func releaseSave() { saveContinuation?.resume(); saveContinuation = nil; blockSave = false }
    func load() throws -> [UserDictionaryEntry] {
        if loadFails { throw CocoaError(.fileReadUnknown) }
        return entries
    }
    func save(_ entries: [UserDictionaryEntry]) async throws {
        if blockSave { await withCheckedContinuation { saveContinuation = $0 } }
        if saveFails { throw CocoaError(.fileWriteUnknown) }
        writes += 1; self.entries = entries
    }
}

@MainActor private final class DictionaryTranscriber: TranscriptionService {
    var text = "請打開雨落。"
    var blocked = false
    var continuation: CheckedContinuation<String, Never>?
    func prepare() async throws {}
    func transcribe(url: URL) async throws -> String {
        if blocked { return await withCheckedContinuation { continuation = $0 } }
        return text
    }
    func release() { continuation?.resume(returning: text); continuation = nil }
    func cancel() async { release() }
}

@MainActor struct UserDictionaryControllerTests {
    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try #require(predicate())
    }
    @Test func saveEditDeleteAndRestartUseCanonicalConfirmedEntries() async throws {
        let storage = DictionaryMemoryStore(); let controller = UserDictionaryController(storage: storage)
        await controller.load()
        #expect(await controller.save(source: " 雨落 ", replacement: "語落"))
        let entry = try #require(controller.entries.first)
        #expect(entry.source == "雨落" && entry.replacement == "语落")
        #expect(await controller.save(source: "雨落", replacement: "VoxInk", id: entry.id))
        let next = UserDictionaryController(storage: storage); await next.load()
        #expect(next.entries.first?.id == entry.id)
        #expect(next.entries.first?.replacement == "VoxInk")
        await next.remove(entry.id)
        #expect(try await storage.load().isEmpty)
        #expect(next.entries.isEmpty)
    }
    @Test func duplicateCanonicalSourceIsRejectedWithoutSaving() async {
        let storage = DictionaryMemoryStore(); let controller = UserDictionaryController(storage: storage)
        await controller.load()
        #expect(await controller.save(source: "軟件", replacement: "VoxInk"))
        #expect(await !controller.save(source: "软件", replacement: "Whisper"))
        #expect(controller.entries.count == 1)
        #expect(await storage.writes == 1)
        #expect(controller.errorMessage != nil)
    }
    @Test func saveFailurePreservesPreviousEntriesAndActiveRules() async throws {
        let storage = DictionaryMemoryStore(); let controller = UserDictionaryController(storage: storage)
        await controller.load()
        #expect(await controller.save(source: "雨落", replacement: "语落"))
        let before = controller.entries
        await storage.setSaveFailure(true)
        #expect(await !controller.save(source: "雨落", replacement: "VoxInk", id: before[0].id))
        #expect(controller.entries == before)
        #expect(DeterministicTextProcessor.shared.process("雨落", dictionary: controller.rules).text == "语落")
        #expect(controller.errorMessage != nil)
        await storage.setSaveFailure(false)
        #expect(await controller.save(source: "雨落", replacement: "VoxInk", id: before[0].id))
    }
    @Test func failedLoadCannotOverwriteUnrecognizedStorage() async {
        let storage = DictionaryMemoryStore(loadFails: true); let controller = UserDictionaryController(storage: storage)
        await controller.load()
        #expect(!controller.isReady)
        #expect(await !controller.save(source: "雨落", replacement: "语落"))
        #expect(await storage.writes == 0)
        #expect(controller.errorMessage != nil)
    }
    @Test func appLoadsDictionaryBeforePreparingAndKeepsRawRecognition() async throws {
        let storage = DictionaryMemoryStore()
        try await storage.save([UserDictionaryEntry(source: "雨落", replacement: "语落")])
        let dictionary = UserDictionaryController(storage: storage)
        let service = DictionaryTranscriber()
        let store = AppStore(service: service, preferences: nil, audioCleaner: { _ in }, dictionary: dictionary)
        store.prepareForUse()
        try await wait { store.canStart }
        #expect(dictionary.isReady)
        await store.transcribePrepared(URL(fileURLWithPath: "/fixture.wav"))
        #expect(store.transcript == "请打开语落。")
        #expect(store.rawTranscript == "請打開雨落。")
        await store.shutdown()
    }
    @Test func activeRecognitionUsesSnapshotWhileNextOneUsesSavedEdit() async throws {
        let storage = DictionaryMemoryStore(); let dictionary = UserDictionaryController(storage: storage)
        await dictionary.load()
        #expect(await dictionary.save(source: "雨落", replacement: "语落"))
        let service = DictionaryTranscriber(); service.blocked = true
        let store = AppStore(service: service, preferences: nil, audioCleaner: { _ in }, dictionary: dictionary)
        let pending = Task { await store.transcribePrepared(URL(fileURLWithPath: "/fixture.wav")) }
        try await wait { service.continuation != nil }
        let id = try #require(dictionary.entries.first?.id)
        #expect(await dictionary.save(source: "雨落", replacement: "VoxInk", id: id))
        service.release(); await pending.value
        #expect(store.transcript == "请打开语落。")
        service.blocked = false
        await store.transcribePrepared(URL(fileURLWithPath: "/fixture.wav"))
        #expect(store.transcript == "请打开VoxInk。")
    }
    @Test func missingDictionaryDoesNotBlockBaseRecognition() async {
        let dictionary = UserDictionaryController(storage: DictionaryMemoryStore(loadFails: true))
        await dictionary.load()
        let store = AppStore(service: DictionaryTranscriber(), preferences: nil, audioCleaner: { _ in }, dictionary: dictionary)
        await store.transcribePrepared(URL(fileURLWithPath: "/fixture.wav"))
        #expect(store.phase == .ready)
        #expect(store.transcript == "请打开雨落。")
        #expect(store.conversionWarning?.contains("词典暂不可用") == true)
    }

    @Test func quittingWaitsUntilPendingDictionarySaveCompletes() async throws {
        let storage = DictionaryMemoryStore(); let dictionary = UserDictionaryController(storage: storage)
        await dictionary.load(); await storage.blockNextSave()
        let save = Task { await dictionary.save(source: "雨落", replacement: "语落") }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while await storage.saveContinuation == nil, ContinuousClock.now < deadline { await Task.yield() }
        try #require(await storage.saveContinuation != nil)
        let store = AppStore(service: DictionaryTranscriber(), preferences: nil, dictionary: dictionary)
        var finished = false
        let shutdown = Task { await store.shutdown(); finished = true }
        await Task.yield()
        #expect(!finished)
        await storage.releaseSave()
        #expect(await save.value)
        await shutdown.value
        #expect(finished)
        #expect(try await storage.load().first?.replacement == "语落")
    }
}
