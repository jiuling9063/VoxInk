import Foundation

/// Context consists only of user-confirmed terms, never an instruction template.
public struct HotwordContext: Equatable, Sendable {
    public let text: String?
    public let tokenCount: Int
    public let wordCount: Int
    public static let maximumTokens = 256

    public static func make(words: [String], countTokens: (String) -> Int) throws -> Self {
        guard words.count <= 32, words.reduce(0, { $0 + $1.utf8.count }) <= 1024 else {
            throw HotwordError.invalidWords
        }
        let allowed = CharacterSet.letters.union(.nonBaseCharacters).union(.decimalDigits)
            .union(CharacterSet(charactersIn: " ._+-"))
        guard words.allSatisfy({ word in
            !word.isEmpty && word.count <= 64 && word.utf8.count <= 512
                && word == word.trimmingCharacters(in: .whitespacesAndNewlines)
                && word.unicodeScalars.allSatisfy({ allowed.contains($0) })
                && word.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
        }) else { throw HotwordError.invalidWords }
        var selected: [String] = []
        var seen = Set<String>()
        var tokens = 0
        for word in words where seen.insert(word).inserted {
            let candidate = (selected + [word]).joined(separator: ", ")
            let count = countTokens(candidate)
            guard count > 0 else { throw HotwordError.invalidTokenCount }
            guard count <= maximumTokens else { break }
            selected.append(word); tokens = count
        }
        return Self(text: selected.isEmpty ? nil : selected.joined(separator: ", "),
                    tokenCount: tokens, wordCount: selected.count)
    }
}

public enum HotwordError: Error { case invalidWords, invalidTokenCount, incompatiblePrompt }
