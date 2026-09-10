import Testing
@testable import VoxInkCore

@MainActor struct SimplifiedTextConverterTests {
    @Test func convertsCharactersAndMainlandTerms() {
        let result = SimplifiedTextConverter.shared.convert("軟體平台、滑鼠、記憶體、網路、檔案；今天的天氣很好，請聯絡我。")
        #expect(result.text == "软件平台、鼠标、内存、网络、文件；今天的天气很好，请联系我。")
        #expect(result.mode == .openCC)
    }

    @Test func preservesProtectedFragmentsAndFormatting() {
        let raw = "下載 https://example.com/軟體?q=繁體，郵箱 user@例子.公司；路徑 /Users/test/繁體.txt；執行 `let 檔案 = 123`。\nEnglish、123.45、2026-09-09、v1.2.3、貳佰元 🙂"
        let result = SimplifiedTextConverter.shared.convert(raw)
        #expect(result.text == "下载 https://example.com/軟體?q=繁體，邮箱 user@例子.公司；路径 /Users/test/繁體.txt；运行 `let 檔案 = 123`。\nEnglish、123.45、2026-09-09、v1.2.3、貳佰元 🙂")
    }

    @Test func preservesFencedCodeAndQuotedPaths() {
        let raw = "檔案：\n```swift\nlet 軟體 = \"網路\"\n```\n開啟 \"/Users/test/繁體 文件.txt\" 和 C:\\繁體\\檔案.txt。"
        #expect(SimplifiedTextConverter.shared.convert(raw).text == "文件：\n```swift\nlet 軟體 = \"網路\"\n```\n打开 \"/Users/test/繁體 文件.txt\" 和 C:\\繁體\\檔案.txt。")
    }

    @Test func simplifiedTextIsStable() {
        let text = "软件平台已经准备好了。English 123！\n"
        #expect(SimplifiedTextConverter.shared.convert(text).text == text)
        #expect(SimplifiedTextConverter.shared.convert("").text.isEmpty)
    }

    @Test func mainlandFileNounDoesNotDriftIntoDocumentOnSecondPass() {
        let result = SimplifiedTextConverter.shared.convert("檔案和文件夾中的文件。").text
        #expect(result == "文件和文件夹中的文件。")
        #expect(SimplifiedTextConverter.shared.convert(result).text == result)
    }

    @Test func fallbackReportsLimitedConversionAndProtectsCode() {
        let converter = SimplifiedTextConverter(primary: nil)
        let result = converter.convert("軟體 `軟體` https://example.com/軟體")
        #expect(result.text == "软体 `軟體` https://example.com/軟體")
        #expect(result.mode == .characterFallback)
    }

    @Test func totalFailurePreservesRawText() {
        let converter = SimplifiedTextConverter(primary: nil, fallback: { _ in nil })
        let result = converter.convert("軟體 https://example.com/繁體")
        #expect(result.text == "軟體 https://example.com/繁體")
        #expect(result.mode == .unconverted)
    }
}
