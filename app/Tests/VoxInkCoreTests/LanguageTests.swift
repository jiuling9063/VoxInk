import Foundation
import Testing
@testable import VoxInkCore

struct LanguageTests {
    @Test func resolvesSystemLanguageAndFallback() {
        #expect(InterfaceLanguage.resolve(.system, preferredLanguages: ["zh-HK"]) == .traditionalChinese)
        #expect(InterfaceLanguage.resolve(.system, preferredLanguages: ["zh-Hans-CN"]) == .simplifiedChinese)
        #expect(InterfaceLanguage.resolve(.system, preferredLanguages: ["zh-Hans-HK"]) == .simplifiedChinese)
        #expect(InterfaceLanguage.resolve(.system, preferredLanguages: ["zh-Hant-CN"]) == .traditionalChinese)
        #expect(InterfaceLanguage.resolve(.system, preferredLanguages: ["ja-JP"]) == .japanese)
        #expect(InterfaceLanguage.resolve(.system, preferredLanguages: ["fr-FR", "ko-KR"]) == .korean)
        #expect(InterfaceLanguage.resolve(.system, preferredLanguages: ["fr-FR"]) == .english)
        #expect(InterfaceLanguage.resolve(.english, preferredLanguages: ["ja-JP"]) == .english)
    }

    @Test func catalogsCoverSameMessagesAndKeepPlaceholders() throws {
        let english = try #require(Localization.catalogs["en"])
        #expect(english.count > 450)
        let placeholder = try NSRegularExpression(pattern: #"\{\d+\}|%(?:[0-9.]+)?[@df]"#)
        func parameters(_ text: String) -> [String] {
            placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).map {
                String(text[Range($0.range, in: text)!])
            }.sorted()
        }
        for language in ["en", "ja", "ko", "zh-Hant"] {
            let catalog = try #require(Localization.catalogs[language])
            #expect(Set(catalog.keys) == Set(english.keys))
            for (key, value) in catalog {
                #expect(!value.isEmpty)
                #expect(parameters(key) == parameters(value), "\(language): \(key)")
            }
        }
        #expect(Localization.text("语音语言", language: .english) == "Speech language")
        #expect(Localization.text("语音语言", language: .japanese) == "音声の言語")
        #expect(Localization.text("语音语言", language: .korean) == "음성 언어")
        #expect(Localization.text("语音语言", language: .traditionalChinese) == "語音語言")
    }

    @Test func interpolatedUserTextIsNotInterpretedAsAnotherPlaceholder() {
        let value = Localization.text("\("{1}") 不可用，仍使用 \("⌥ Space")", language: .english)
        #expect(value == "{1} unavailable; keeping ⌥ Space")
    }

    @MainActor @Test func foreignTextKeepsScriptSpacingAndProtectedContent() throws {
        for (language, text) in [(SpeechLanguage.japanese, "図書館で資料を確認します。東京の広場。"),
                                 (.korean, "오늘 오후 세 시에 회의가 있습니다."),
                                 (.english, "Please review version 1.2 at https://example.com/A.")] {
            for output in ChineseOutput.allCases {
                #expect(LanguageTextProcessor.process(text, language: language, output: output).text == text)
            }
        }
        let dictionary = try UserDictionaryRules(entries: [.init(source: "Vox Inc", replacement: "VoxInk")])
        #expect(LanguageTextProcessor.process("Open Vox Inc.", language: .english, output: .simplified, dictionary: dictionary).text == "Open VoxInk.")
        #expect(LanguageTextProcessor.process("`Vox Inc` https://VoxInc.com", language: .english, output: .simplified, dictionary: dictionary).text == "`Vox Inc` https://VoxInc.com")
    }

    @MainActor @Test func chineseOutputSelectionKeepsOriginalAndDictionarySpelling() throws {
        #expect(LanguageTextProcessor.process("軟體平台，今天的天氣很好。", language: .mandarin, output: .simplified).text == "软件平台，今天的天气很好。")
        #expect(LanguageTextProcessor.process("今天的天气很好。", language: .mandarin, output: .traditional).text == "今天的天氣很好。")
        #expect(LanguageTextProcessor.process("聽日開會。", language: .cantonese, output: .original).text == "聽日開會。")
        let dictionary = try UserDictionaryRules(entries: [.init(source: "雨落", replacement: "語落")])
        #expect(LanguageTextProcessor.process("请打开雨落。", language: .mandarin, output: .simplified, dictionary: dictionary).text == "请打开語落。")
        #expect(LanguageTextProcessor.process("図書館で資料を確認します。", language: .automatic, output: .simplified).text == "図書館で資料を確認します。")
    }
}
