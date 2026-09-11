import Testing
@testable import VoxInkCore

struct LightTextPolisherTests {
    @Test func preservesWordingAndProtectedContent() {
        let source = "明天讨论。预算1234.50元。网址 https://example.com/a?q=1\n```swift\nlet text = \"你好。世界\"\n```"
        let result = LightTextPolisher.polish(source)
        #expect(result.contains("讨论。\n预算1234.50元。"))
        #expect(result.contains("https://example.com/a?q=1"))
        #expect(result.contains("```swift\nlet text = \"你好。世界\"\n```"))
    }
}
