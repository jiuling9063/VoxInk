import Foundation
import NaturalLanguage

/// Conservative checks, not a semantic verifier. Unsupported rewrites keep the original text.
public enum PolishTextSafety {
    public static func accepts(source: String, output: String, language: SpeechLanguage, style: PolishStyle = .original) -> Bool {
        // “检查一下” is a softening phrase, not a quantity. Keep real numbers protected.
        func protectedInput(_ text: String) -> String {
            guard style == .natural, let segments = ProtectedText.segments(in: text) else { return text }
            func soften(_ value: String) -> String {
                value.replacingOccurrences(of: "(测试|確認|确认|检查|討論|讨论|整理|处理|调整|查看)一下",
                                           with: "$1", options: .regularExpression)
            }
            var result = "", editable = ""
            for segment in segments {
                if segment.isProtected && segment.text != "一" {
                    result += soften(editable) + segment.text
                    editable = ""
                } else { editable += segment.text }
            }
            return result + soften(editable)
        }
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              output.count <= max(source.count * 2, 100),
              let before = ProtectedText.segments(in: protectedInput(source)), let after = ProtectedText.segments(in: protectedInput(output)) else { return false }
        guard before.filter(\.isProtected).map(\.text) == after.filter(\.isProtected).map(\.text),
              matches(#"“[^”]*”|「[^」]*」|『[^』]*』|\"[^\"\n]*\""#, source) == matches(#"“[^”]*”|「[^」]*」|『[^』]*』|\"[^\"\n]*\""#, output),
              matches("不是|不要|不能|不得|没有|沒有|并非|並非|尚未|还没|還沒|不确定|不確定|好像|似乎|大概|可能|也许|也許|未必|不|没|沒", source)
                == matches("不是|不要|不能|不得|没有|沒有|并非|並非|尚未|还没|還沒|不确定|不確定|好像|似乎|大概|可能|也许|也許|未必|不|没|沒", output) else { return false }
        if style == .natural {
            return acceptsNatural(source: source, output: output)
        }
        let chinese = language == .mandarin || language == .cantonese
        let normalizedSource = chinese ? removingDisfluencies(source) : source
        let normalizedOutput = chinese ? removingDisfluencies(output) : output
        guard content(normalizedSource) == content(normalizedOutput) else { return false }
        // Preserve alphabetic word boundaries (e.g. "now here" versus "nowhere") in every language.
        return matches(#"[A-Za-z\p{M}]+"#, normalizedSource) == matches(#"[A-Za-z\p{M}]+"#, normalizedOutput)
    }

    // These checks bound edits; they cannot prove semantic equivalence.
    private static func acceptsNatural(source: String, output: String) -> Bool {
        guard output.count <= max(30, Int(Double(source.count) * 1.3)),
              output.count >= max(1, source.count / 2),
              matches("今天|明天|后天|後天|昨天|上午|下午|晚上|之前|之后|之後|先|再|最后|最後", source)
                == matches("今天|明天|后天|後天|昨天|上午|下午|晚上|之前|之后|之後|先|再|最后|最後", output),
              matches("[？?]", source).count <= matches("[？?]", output).count else { return false }
        let actionHeads = "(?:先|再|最后|最後|之前|之后|之後)[\\p{L}\\p{N}]{1,2}"
        guard matches(actionHeads, source) == matches(actionHeads, output) else { return false }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = source
        var namesPreserved = true
        var nameCursor = output.startIndex
        tagger.enumerateTags(in: source.startIndex..<source.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
            if [.personalName, .placeName, .organizationName].contains(tag) {
                let name = String(source[range])
                if source.components(separatedBy: name).count != output.components(separatedBy: name).count {
                    namesPreserved = false
                }
                if let found = output.range(of: name, range: nameCursor..<output.endIndex) {
                    nameCursor = found.upperBound
                } else { namesPreserved = false }
            }
            return true
        }
        guard namesPreserved else { return false }
        let before = Array(content(source)), after = Array(content(output))
        guard !before.isEmpty, !after.isEmpty else { return false }
        // Limit additions and deletions while permitting local clause/time movement.
        let beforeCounts = Dictionary(before.map { ($0, 1) }, uniquingKeysWith: +)
        let afterCounts = Dictionary(after.map { ($0, 1) }, uniquingKeysWith: +)
        let shared = beforeCounts.reduce(0) { $0 + min($1.value, afterCounts[$1.key, default: 0]) }
        guard Double(shared) / Double(before.count) >= 0.7,
              Double(shared) / Double(after.count) >= 0.9 else { return false }
        // Short utterances should never be freely rearranged (e.g. swapping two people).
        if before.count <= 12 {
            var remaining = before.makeIterator()
            return after.allSatisfy { character in
                while let next = remaining.next() { if next == character { return true } }
                return false
            }
        }
        return true
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
