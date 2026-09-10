import Darwin
import Foundation
import Testing
@testable import VoxInkCore

@MainActor struct UserDictionaryTests {
    private func process(_ raw: String, _ pairs: [(String, String)]) throws -> String {
        let rules = try UserDictionaryRules(entries: pairs.map { try UserDictionaryEntry(source: $0.0, replacement: $0.1) })
        return DeterministicTextProcessor.shared.process(raw, dictionary: rules).text
    }

    @Test func chineseCorrectionsRespectWordBoundaries() throws {
        #expect(try process("请打开雨落。下雨落地后再说。", [("雨落", "语落")]) == "请打开语落。下雨落地后再说。")
    }
    @Test func namesWithNumbersCanBeCorrectedWithoutChangingTheirNumbers() throws {
        #expect(try process("一佳手机 Qwin3", [("一佳", "一加"), ("Qwin3", "Qwen3")]) == "一加手机 Qwen3")
        #expect(throws: (any Error).self) { try UserDictionaryEntry(source: "Qwin3", replacement: "Qwen4") }
        #expect(throws: (any Error).self) { try UserDictionaryEntry(source: "三丰", replacement: "四丰") }
        #expect(throws: (any Error).self) { try UserDictionaryEntry(source: "Qwin３", replacement: "Qwen４") }
        #expect(throws: (any Error).self) { try UserDictionaryEntry(source: "Qwin3", replacement: "Qwen-3") }
        #expect(throws: (any Error).self) { try UserDictionaryEntry(source: "一", replacement: "一名字") }
    }
    @Test func englishIsCaseSensitiveAndCannotMatchInsideIdentifiers() throws {
        let raw = "Wisper wisper Wispering Wisper_字段 Wisper.dev Wisper(1) `Wisper` https://test.com/Wisper /tmp/Wisper"
        #expect(try process(raw, [("Wisper", "Whisper")]) == "Whisper wisper Wispering Wisper_字段 Wisper.dev Wisper(1) `Wisper` https://test.com/Wisper /tmp/Wisper")
    }
    @Test func longestPhraseWinsWithoutCascading() throws {
        let rules = [("voice", "声音"), ("voice ink", "语落"), ("语落", "别名")]
        #expect(try process("voice ink and voice", rules) == "语落 and 声音")
    }
    @Test func protectsNumbersPathsCodeAndOriginalFormatting() throws {
        let raw = "雨落 123.45 ¥  20.00 /雨落 `雨落` https://雨落.example user@雨落.公司\n```\n雨落  123;;\n```"
        let actual = try process(raw, [("雨落", "语落")])
        #expect(actual == "语落 123.45 ¥  20.00 /雨落 `雨落` https://雨落.example user@雨落.公司\n```\n雨落  123;;\n```")
    }
    @Test func unmatchedDictionaryDoesNotAlterBaseRules() throws {
        for raw in ["foo,,bar", "1,,234", "呃，請用Swift整理檔案。", "（ 今天 ）", "`unchanged  code`", ""] {
            #expect(try process(raw, [("雨落", "语落")]) == DeterministicTextProcessor.shared.process(raw).text)
        }
    }
    @Test func rejectsInvalidDuplicateAndOversizedConfigurations() throws {
        for (source, target) in [("", "语落"), ("雨落", "雨落"), ("123", "名字"), ("一", "名字"), ("foo()", "Bar"), ("雨落\n软件", "语落"), ("雨落", "https://x.test"), ("雨落", "\u{202E}语落")] {
            #expect(throws: (any Error).self) { try UserDictionaryEntry(source: source, replacement: target) }
        }
        let entry = try UserDictionaryEntry(source: "雨落", replacement: "语落")
        #expect(throws: (any Error).self) { try UserDictionaryRules(entries: [entry, entry]) }
        #expect(throws: (any Error).self) {
            try UserDictionaryEntry(source: String(repeating: "词", count: 65), replacement: "语落")
        }
        let many = try (0..<101).map { index in try UserDictionaryEntry(source: "term" + String(UnicodeScalar(65 + index / 26)!) + String(UnicodeScalar(65 + index % 26)!), replacement: "语落") }
        #expect(throws: (any Error).self) { try UserDictionaryRules(entries: many) }
        #expect(throws: (any Error).self) {
            try UserDictionaryEntry(source: "a" + String(repeating: "\u{0301}", count: 1000), replacement: "名称")
        }
        let longEntries = try (0..<40).map { index in
            try UserDictionaryEntry(source: String(repeating: "a", count: 62) + String(UnicodeScalar(65 + index / 26)!) + String(UnicodeScalar(65 + index % 26)!),
                                    replacement: String(repeating: "b", count: 64))
        }
        #expect(throws: (any Error).self) { try UserDictionaryRules(entries: longEntries) }
    }

    private func temporaryFile() throws -> URL {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        let pointer = try #require(realpath(temporary.path, nil)); defer { free(pointer) }
        return URL(fileURLWithPath: String(cString: pointer)).appendingPathComponent("words.json")
    }

    @Test func fileRoundTripUsesPrivatePermissionsAndPersistsEdits() async throws {
        let url = try temporaryFile(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = UserDictionaryFileStore(url: url)
        #expect(try await store.load().isEmpty)
        let entry = try UserDictionaryEntry(source: "雨落", replacement: "语落")
        try await store.save([entry])
        #expect(try await UserDictionaryFileStore(url: url).load() == [entry])
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
        #expect(try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? Int == 0o700)
        try await store.save([])
        #expect(try await UserDictionaryFileStore(url: url).load().isEmpty)
    }
    @Test func malformedAndFutureFilesStayUntouchedWhenLoadingFails() async throws {
        let url = try temporaryFile(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = UserDictionaryFileStore(url: url)
        for contents in ["broken", "{\"version\":2,\"entries\":[]}"] {
            let data = Data(contents.utf8); try data.write(to: url)
            await #expect(throws: (any Error).self) { try await store.load() }
            #expect(try Data(contentsOf: url) == data)
        }
    }
    @Test func invalidSaveCannotReplacePreviousFileAndLinksAreRejected() async throws {
        let url = try temporaryFile(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = UserDictionaryFileStore(url: url)
        let entry = try UserDictionaryEntry(source: "雨落", replacement: "语落")
        try await store.save([entry]); let before = try Data(contentsOf: url)
        await #expect(throws: (any Error).self) { try await store.save([entry, entry]) }
        #expect(try Data(contentsOf: url) == before)
        let linked = url.deletingLastPathComponent().appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: url)
        await #expect(throws: (any Error).self) { try await UserDictionaryFileStore(url: linked).save([]) }
        #expect(try Data(contentsOf: url) == before)
    }
}
