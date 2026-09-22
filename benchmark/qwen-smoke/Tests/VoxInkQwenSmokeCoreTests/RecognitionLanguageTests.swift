import Testing
@testable import VoxInkQwenSmokeCore

@Test func speechLanguageHintsUseModelLanguageNamesAndNilForAutoDetection() throws {
    #expect(try RecognitionLanguage.hint(for: "auto") == nil)
    for (code, expected) in [("zh", "Chinese"), ("yue", "Cantonese"), ("en", "English"), ("ja", "Japanese"), ("ko", "Korean")] {
        #expect(try RecognitionLanguage.hint(for: code) == expected)
    }
    #expect(try RecognitionLanguage.hint(for: nil) == "Chinese")
    #expect(throws: (any Error).self) { try RecognitionLanguage.hint(for: "invalid") }
}
