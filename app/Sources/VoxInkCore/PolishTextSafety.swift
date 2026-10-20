import Foundation

/// Conservative checks, not a semantic verifier. Unsupported rewrites keep the original text.
public enum PolishTextSafety {
    public static func accepts(source: String, output: String, language: SpeechLanguage) -> Bool {
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              output.count <= max(source.count * 2, 100),
              let before = ProtectedText.segments(in: source), let after = ProtectedText.segments(in: output) else { return false }
        guard before.filter(\.isProtected).map(\.text) == after.filter(\.isProtected).map(\.text),
              matches(#"“[^”]*”|「[^」]*」|『[^』]*』|\"[^\"\n]*\""#, source) == matches(#"“[^”]*”|「[^」]*」|『[^』]*』|\"[^\"\n]*\""#, output),
              matches("不是|不要|不能|不得|没有|沒有|并非|並非|尚未|还没|還沒|不确定|不確定|好像|似乎|大概|可能|也许|也許|未必|不|没|沒", source)
                == matches("不是|不要|不能|不得|没有|沒有|并非|並非|尚未|还没|還沒|不确定|不確定|好像|似乎|大概|可能|也许|也許|未必|不|没|沒", output) else { return false }
        let chinese = language == .mandarin || language == .cantonese
        let normalizedSource = chinese ? removingDisfluencies(source) : source
        let normalizedOutput = chinese ? removingDisfluencies(output) : output
        guard content(normalizedSource) == content(normalizedOutput) else { return false }
        // Preserve alphabetic word boundaries (e.g. "now here" versus "nowhere") in every language.
        return matches(#"[A-Za-z\p{M}]+"#, normalizedSource) == matches(#"[A-Za-z\p{M}]+"#, normalizedOutput)
    }

    private static func removingDisfluencies(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: #"(^|[，,。；;！？!?\s])(?:呃+|嗯+|啊+|额)(?=[，,。；;！？!?\s]|$)"#,
                                                with: "$1", options: .regularExpression)
        let clauses = cleaned.components(separatedBy: CharacterSet(charactersIn: "，,。；;！？!?\n"))
        var result: [String] = []
        for clause in clauses {
            let value = content(clause)
            if !value.isEmpty, result.last != value { result.append(value) }
        }
        return result.joined(separator: "，")
    }

    private static func content(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.unicodeScalars
            .filter { CharacterSet.alphanumerics.union(.nonBaseCharacters).contains($0) }
            .map(String.init).joined()
    }

    private static func matches(_ pattern: String, _ text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let value = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: value.length)).map { value.substring(with: $0.range) }
    }
}
