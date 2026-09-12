import Foundation
import Testing
@testable import VoxInkCore

@MainActor struct DeterministicTextProcessorTests {
    private let processor = DeterministicTextProcessor.shared

    @Test func normalizesProseWithoutChangingEnglishWordsOrParagraphs() {
        let raw = " \t今天  的天氣很好 ，， 請使用 Swift   開發軟體。。\r\n\r\n\r\nEnglish\t  words  stay\tseparate \n "
        #expect(processor.process(raw).text == "今天的天气很好，请使用 Swift 开发软件。\n\nEnglish words stay separate")
    }

    @Test func protectsHighRiskOriginalSubstringsAcrossAllRules() {
        let protected = [
            "https://example.com/繁體?a=1.2&b=3", "user@例子.公司", "/Users/test/繁體.txt",
            "\"/Users/test/繁體  文件.txt\"", "../繁體/檔案.swift", "C:\\繁體\\檔案.txt",
            "v1.2.3-beta", "-1,234.50", "¥  12,345.60", "€  1\u{202F}234.50", "1  234  567", "2026 年  9 月 9 日", "08:03:02", "12.5％",
            "貳佰", "foo_繁體", "`let 軟體  =  123;;`", "```swift\n\tlet 軟體  =  \"呃，\"\n\n\n```",
            "~~~text\n呃，繁體，，\n~~~", "`unterminated  軟體  "
        ]
        for value in protected {
            let raw = "檢查  \(value)"
            let result = processor.process(raw)
            #expect(result.text == "检查 \(value)", "Changed protected input: \(value)")
            #expect(processor.process(result.text).text == result.text)
        }
    }

    @Test func mixedChineseAfterEnglishStillConverts() {
        #expect(processor.process("Swift開發軟體，Today是週三，VoxInk支援繁體轉簡體。").text == "Swift开发软件，Today是周三，VoxInk支持繁体转简体。")
        #expect(processor.process("軟  體平台與檔  案").text == "软件平台与文件")
    }

    @Test func removesOnlyCommaDelimitedSentenceInitialHesitation() {
        #expect(processor.process("呃，請明天聯絡我。呃呃，現在先整理檔案。").text == "请明天联系我。现在先整理文件。")
        for raw in ["嗯，是的。", "就是这个，然后继续。", "呃", "呃，", "他说“呃，请等等”。", "发音是呃，请跟读。", "呃，表示犹豫。", "呃，是语气词。", "呃，怎么写？", "呃这个音怎么读？"] {
            #expect(processor.process(raw).text == raw)
        }
    }

    @Test func preservesToneEllipsesDecimalsAndSeparatelySpokenNumbers() {
        for raw in ["真的吗？？", "太好了！！", "也许……", "Wait...", "还没说完。。。", "一 二 三", "1 2 3", "12.34", "1,,234", "0::30", "say \"hello world\""] {
            #expect(processor.process(raw).text == raw)
        }
        #expect(processor.process("（ 你好 ）；；然后：：继续").text == "（你好）；然后：继续")
    }

    @Test func removesInvisibleControlsButPreservesEmojiJoiners() {
        #expect(processor.process("\u{FEFF}請\u{200B}查看\u{0000} 👩‍💻 👨‍👩‍👧‍👦 ❤️\u{202E}\n").text == "请查看 👩‍💻 👨‍👩‍👧‍👦 ❤️")
        let code = "`let a = \"\u{200B}\"`"
        #expect(processor.process(code).text == code)
    }

    @Test func recordingTimeUnitConvertsWhileDecimalValueRemainsVerbatim() {
        let raw = "明天下午三點開會。四點半結束，數值負三點一四保持不變，`三點` 不改。"
        let expected = "明天下午三点开会。四点半结束，数值負三點一四保持不变，`三點` 不改。"
        #expect(processor.process(raw).text == expected)
        #expect(processor.process(expected).text == expected)
    }

    @Test func doesNotInventEndPunctuationOrRemoveMeaningfulWords() {
        for raw in ["明天提交", "然后就是这个方案", "金额 ¥  12.50 和 2026 年 9 月 9 日", "真的……真的吗？！"] {
            #expect(processor.process(raw).text == raw)
        }
    }

    @Test func fallbackModeIsVisibleAndTotalFailurePreservesOriginal() {
        let fallback = DeterministicTextProcessor(converter: SimplifiedTextConverter(primary: nil))
        let result = fallback.process("  軟體，， `軟體`  ")
        #expect(result.text == "软体， `軟體`")
        #expect(result.mode == .characterFallback)
        #expect(result.warning != nil)
        let failed = DeterministicTextProcessor(converter: SimplifiedTextConverter(primary: nil, fallback: { _ in nil }))
        let raw = "  軟體，，  "
        #expect(failed.process(raw).text == raw)
        #expect(failed.process(raw).mode == .unconverted)
    }

    @Test func processingIsIdempotentAcrossMixedFixtures() {
        let fixtures = ["呃，請用Swift整理  檔案。。", "中文  English   123。", "開始\n\n\n結束", "HTTPS://EXAMPLE.COM/繁體", "\t\n", "", " ，，， ", "hello\u{00A0}world"]
        for raw in fixtures {
            let result = processor.process(raw).text
            #expect(processor.process(result).text == result, "Not idempotent: \(raw)")
        }
    }
}
