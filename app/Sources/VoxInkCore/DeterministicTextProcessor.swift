import Foundation

@MainActor public final class DeterministicTextProcessor {
    public static let shared = DeterministicTextProcessor()
    private let converter: SimplifiedTextConverter
    public convenience init() { self.init(converter: .shared) }
    init(converter: SimplifiedTextConverter) { self.converter = converter }

    public func process(_ raw: String, dictionary: UserDictionaryRules = .empty) -> SimplifiedTextResult {
        guard let segments = ProtectedText.segments(in: raw) else { return .init(text: raw, mode: .unconverted) }
        var normalized: [Unit] = []
        for segment in segments {
            if segment.isProtected { normalized.append(Unit(text: segment.text, protected: true)); continue }
            normalized.append(contentsOf: normalize(segment.text).map { Unit(text: String($0), protected: false) })
        }
        var units: [Unit] = []
        var pending = ""
        var mode = SimplifiedTextResult.Mode.openCC
        func flushProse() -> Bool {
            guard !pending.isEmpty else { return true }
            let converted = converter.convertUnprotected(pending)
            guard converted.mode != .unconverted else { return false }
            if converted.mode == .characterFallback { mode = .characterFallback }
            units.append(contentsOf: converted.text.map { Unit(text: String($0), protected: false) })
            pending = ""
            return true
        }
        for unit in cleanSpacing(normalized) {
            if unit.protected {
                guard flushProse() else { return .init(text: raw, mode: .unconverted) }
                units.append(unit)
            } else { pending += unit.text }
        }
        guard flushProse() else { return .init(text: raw, mode: .unconverted) }
        units = applyDictionary(dictionary, to: units)
        units = cleanPunctuation(units)
        units = cleanFillers(units)
        return .init(text: cleanSpacing(units).map(\.text).joined(), mode: mode)
    }

    private func applyDictionary(_ dictionary: UserDictionaryRules, to units: [Unit]) -> [Unit] {
        guard !dictionary.isEmpty else { return units }
        var result: [Unit] = []
        var pending = ""
        func flush() {
            for segment in dictionary.replacing(pending) {
                if segment.isProtected { result.append(Unit(text: segment.text, protected: true)); continue }
                for part in ProtectedText.segments(in: segment.text) ?? [.init(text: segment.text, isProtected: true)] {
                    if part.isProtected { result.append(Unit(text: part.text, protected: true)) }
                    else { result.append(contentsOf: part.text.map { Unit(text: String($0), protected: false) }) }
                }
            }
            pending = ""
        }
        for (index, unit) in units.enumerated() {
            let previous = index > 0 ? units[index - 1].text : ""
            let next = index + 1 < units.count ? units[index + 1].text : ""
            let codeNeighbor = [".", "_", "(" , "[", "{", "+", "-", "="].contains(next) || [".", "_"].contains(previous)
            if !unit.protected || (UserDictionaryRules.isDictionaryFragment(unit.text) && !codeNeighbor) { pending += unit.text }
            else { flush(); result.append(unit) }
        }
        flush()
        return result
    }

    private struct Unit {
        let text: String
        let protected: Bool
        var horizontalSpace: Bool { !protected && text != "\n" && text.unicodeScalars.allSatisfy { CharacterSet.whitespaces.contains($0) } }
        var newline: Bool { !protected && text == "\n" }
        var han: Bool {
            guard !protected, let scalar = text.unicodeScalars.first else { return false }
            return (0x3400...0x4DBF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value) || (0x20000...0x323AF).contains(scalar.value)
        }
    }

    private func normalize(_ text: String) -> String {
        let lineNormalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let scalars = lineNormalized.unicodeScalars.filter { scalar in
            if scalar == "\n" || scalar == "\t" || scalar.value == 0x200C || scalar.value == 0x200D { return true }
            if CharacterSet.controlCharacters.contains(scalar) { return false }
            // Keep joiners and variation selectors: stripping them damages emoji and written languages.
            return ![0x00AD, 0x200B, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2060, 0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF].contains(scalar.value)
        }
        return String(String.UnicodeScalarView(scalars)).precomposedStringWithCanonicalMapping
    }

    private func cleanSpacing(_ units: [Unit]) -> [Unit] {
        var result: [Unit] = []
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit.horizontalSpace {
                var end = index + 1
                while end < units.count, units[end].horizontalSpace { end += 1 }
                let previous = result.last
                let next = end < units.count ? units[end] : nil
                let betweenHan = previous?.han == true && next?.han == true
                let beforeClosing = next.map { !$0.protected && "，。；：！？、）】》」』”".contains($0.text) } ?? false
                let afterOpening = previous.map { !$0.protected && "（【《「『“".contains($0.text) } ?? false
                let afterChinesePunctuation = previous.map { !$0.protected && "，。；：！？、".contains($0.text) } == true && next?.han == true
                if previous != nil, next != nil, previous?.newline != true, next?.newline != true,
                   !betweenHan, !beforeClosing, !afterOpening, !afterChinesePunctuation {
                    result.append(Unit(text: " ", protected: false))
                }
                index = end; continue
            }
            if unit.newline {
                if result.isEmpty { index += 1; continue }
                if result.suffix(2).allSatisfy(\.newline), result.count >= 2 { index += 1; continue }
            }
            result.append(unit); index += 1
        }
        while result.last?.newline == true { result.removeLast() }
        return result
    }

    private func cleanPunctuation(_ units: [Unit]) -> [Unit] {
        var result: [Unit] = []
        var index = 0
        while index < units.count {
            let unit = units[index]
            var end = index + 1
            if !unit.protected, "，,；;：:。".contains(unit.text) {
                while end < units.count, !units[end].protected, units[end].text == unit.text { end += 1 }
            }
            // Do not turn e.g. 1,,234 into a different-looking number, or collapse a possible ellipsis.
            let betweenProtected = result.last?.protected == true && end < units.count && units[end].protected
            if (unit.text == "。" && end - index >= 3) || betweenProtected {
                result.append(contentsOf: units[index..<end])
            }
            else { result.append(unit) }
            index = end
        }
        return result
    }

    private func cleanFillers(_ units: [Unit]) -> [Unit] {
        var result: [Unit] = []
        var index = 0
        while index < units.count {
            let atSentenceStart = result.isEmpty || result.last.map { !$0.protected && "。！？\n".contains($0.text) } == true
            if atSentenceStart, !units[index].protected, units[index].text == "呃" {
                var end = index + 1
                while end < units.count, !units[end].protected, units[end].text == "呃" { end += 1 }
                if end < units.count, !units[end].protected, "，,".contains(units[end].text) {
                    end += 1
                    while end < units.count, units[end].horizontalSpace { end += 1 }
                    let tail = units[end...].prefix(8).map(\.text).joined()
                    // Only known sentence openings qualify; a bare reaction or discussion of the word remains intact.
                    let sentenceOpening = ["请", "我想", "我先", "我们", "这次", "现在", "今天", "明天", "接下来"].contains { tail.hasPrefix($0) }
                    if end < units.count, units[end].han, sentenceOpening {
                        index = end; continue
                    }
                }
            }
            result.append(units[index]); index += 1
        }
        return result
    }
}
