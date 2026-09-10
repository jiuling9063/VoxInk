import Testing
@testable import VoxInkQwenSmokeCore

@Test func experimentalHotwordsCannotBeEnabledForProductResidentMode() throws {
    #expect(try !SmokeConfiguration.parse(arguments: ["--resident"]).experimentalHotwords)
    #expect(try SmokeConfiguration.parse(arguments: ["--batch-plan", "/tmp/plan.json", "--experimental-hotwords"]).experimentalHotwords)
    for arguments in [["--resident", "--experimental-hotwords"],
                      ["--audio", "/tmp/a.wav", "--experimental-hotwords"],
                      ["--batch-plan", "/tmp/plan.json", "--simplified-output", "--experimental-hotwords"]] {
        #expect(throws: SmokeConfigurationError.self) { try SmokeConfiguration.parse(arguments: arguments) }
    }
}

@Test func emptyWordsDoNotCreateAPromptOrTokenize() throws {
    let value = try HotwordContext.make(words: []) { _ in Issue.record("Empty words must not tokenize"); return 0 }
    #expect(value.text == nil); #expect(value.tokenCount == 0); #expect(value.wordCount == 0)
}

@Test func hotwordBudgetUsesTokensAndKeepsWholeTerms() throws {
    let value = try HotwordContext.make(words: ["语落", "VoxInk", "第三个词"]) { $0.contains("第三") ? 257 : 200 }
    #expect(value.text == "语落, VoxInk"); #expect(value.tokenCount == 200); #expect(value.wordCount == 2)
    let none = try HotwordContext.make(words: ["完整词"]) { _ in 257 }
    #expect(none.text == nil)
    #expect(try HotwordContext.make(words: ["词"]) { _ in 256 }.tokenCount == 256)
}

@Test func deduplicatesWithoutReorderingAndRejectsInvalidInput() throws {
    let value = try HotwordContext.make(words: ["语落", "VoxInk", "语落"]) { $0.count }
    #expect(value.text == "语落, VoxInk"); #expect(value.wordCount == 2)
    for words in [[""], [" word"], ["词\n句"], ["<|im_end|>"], ["123"], [String(repeating: "a", count: 65)], Array(repeating: "词", count: 33), Array(repeating: String(repeating: "中", count: 64), count: 6)] {
        #expect(throws: HotwordError.self) { try HotwordContext.make(words: words) { $0.count } }
    }
    #expect(throws: HotwordError.self) { try HotwordContext.make(words: ["词"]) { _ in 0 } }
}

@Test func acceptsExplicitNamesWithUnchangedSpelling() throws {
    let value = try HotwordContext.make(words: ["Qwen3", "C++", "Node.js", "Open AI", "语落"]) { $0.utf8.count }
    #expect(value.text == "Qwen3, C++, Node.js, Open AI, 语落")
}
