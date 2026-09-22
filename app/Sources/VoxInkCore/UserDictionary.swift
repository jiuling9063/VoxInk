import Foundation
import Darwin

public struct UserDictionaryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let source: String
    public let replacement: String
    public init(id: UUID = UUID(), source: String, replacement: String) throws {
        self.id = id; self.source = source; self.replacement = replacement
        try validate()
    }
    func validate() throws {
        guard !source.isEmpty, !replacement.isEmpty else { throw UserDictionaryError.emptyTerm }
        guard source.count <= 64, replacement.count <= 64, source.utf8.count <= 512, replacement.utf8.count <= 512 else {
            throw UserDictionaryError.termTooLong
        }
        let letters = CharacterSet.letters.union(.nonBaseCharacters)
        let targetCharacters = letters.union(.decimalDigits).union(CharacterSet(charactersIn: " ._+-"))
        guard source.unicodeScalars.allSatisfy({ letters.contains($0) || CharacterSet.decimalDigits.contains($0) || $0 == " " }),
              replacement.unicodeScalars.allSatisfy({ targetCharacters.contains($0) }),
              source.unicodeScalars.contains(where: { letters.contains($0) }),
              replacement.unicodeScalars.contains(where: { letters.contains($0) }) else { throw UserDictionaryError.invalidTerm }
        guard source == source.trimmingCharacters(in: .whitespacesAndNewlines),
              replacement == replacement.trimmingCharacters(in: .whitespacesAndNewlines) else { throw UserDictionaryError.invalidTerm }
        guard source != replacement else { throw UserDictionaryError.identicalTerms }
        guard UserDictionaryRules.containsNonNumericLetter(source) else { throw UserDictionaryError.protectedSource }
        guard let originalNumbers = UserDictionaryRules.numbers(in: source),
              let replacementNumbers = UserDictionaryRules.numbers(in: replacement), originalNumbers == replacementNumbers else {
            throw UserDictionaryError.changedNumbers
        }
        guard let segments = ProtectedText.segments(in: source),
              !segments.contains(where: { $0.isProtected && !UserDictionaryRules.isDictionaryFragment($0.text) }) else {
            throw UserDictionaryError.protectedSource
        }
    }
}

public enum UserDictionaryError: Error, LocalizedError {
    case emptyTerm, termTooLong, invalidTerm, identicalTerms, protectedSource, changedNumbers, duplicateSource, duplicateID, tooManyEntries, budgetExceeded, unsupportedVersion, invalidFile
    public var errorDescription: String? {
        switch self {
        case .emptyTerm: L("请填写识别词和正确写法。")
        case .termTooLong: L("每个词最多 64 个字符。")
        case .invalidTerm: L("词条需含文字。识别词可包含数字与空格；正确写法还可包含点、下划线、加号和连字符。")
        case .identicalTerms: L("识别词与正确写法相同，无需添加。")
        case .protectedSource: L("数字、金额、网址、路径和代码不参与词典替换。")
        case .changedNumbers: L("纠正词不能增加或改变原有数字，请保留原来的数字写法。")
        case .duplicateSource: L("此识别词已存在，请编辑已有词条。")
        case .duplicateID: L("词典条目重复，无法读取。")
        case .tooManyEntries: L("最多保存 100 条纠正词。")
        case .budgetExceeded: L("词典总长度最多 4096 个字符，请精简词条。")
        case .unsupportedVersion: L("此词典版本暂不兼容，原文件已保留。")
        case .invalidFile: L("词典文件无法读取，原文件已保留。")
        }
    }
}

public struct UserDictionaryRules: Sendable {
    public static let empty = Self(unchecked: [])
    private let entries: [UserDictionaryEntry]
    var isEmpty: Bool { entries.isEmpty }
    public init(entries: [UserDictionaryEntry]) throws {
        try Self.validate(entries)
        self.init(unchecked: entries)
    }
    private init(unchecked entries: [UserDictionaryEntry]) {
        self.entries = entries.sorted { $0.source.count == $1.source.count ? $0.source < $1.source : $0.source.count > $1.source.count }
    }
    public static func validate(_ entries: [UserDictionaryEntry]) throws {
        guard entries.count <= 100 else { throw UserDictionaryError.tooManyEntries }
        guard entries.reduce(0, { $0 + $1.source.count + $1.replacement.count }) <= 4096 else { throw UserDictionaryError.budgetExceeded }
        guard entries.reduce(0, { $0 + $1.source.utf8.count + $1.replacement.utf8.count }) <= 16_384 else { throw UserDictionaryError.budgetExceeded }
        var sources = Set<String>(); var ids = Set<UUID>()
        for entry in entries {
            try entry.validate()
            guard sources.insert(entry.source).inserted else { throw UserDictionaryError.duplicateSource }
            guard ids.insert(entry.id).inserted else { throw UserDictionaryError.duplicateID }
        }
    }
    private static let chineseNumbers = CharacterSet(charactersIn: "零〇一二三四五六七八九十百千万亿兆兩两壹貳贰參叁肆伍陸陆柒捌玖拾佰仟萬億")
    private static let numberExpression = try? NSRegularExpression(pattern: #"[+\-−]?\p{Nd}+(?:[.,:/%％\-]\p{Nd}+)*|(?:負|负|正)?[零〇一二三四五六七八九十百千万亿兆兩两壹貳贰參叁肆伍陸陆柒捌玖拾佰仟萬億]+"#)
    static func containsNonNumericLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) && !chineseNumbers.contains($0) }
    }
    static func numbers(in text: String) -> [String]? {
        guard let numberExpression else { return nil }
        let string = text as NSString
        return numberExpression.matches(in: text, range: NSRange(location: 0, length: string.length)).map { string.substring(with: $0.range) }
    }
    static func isDictionaryFragment(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        return text.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) }
            || text.unicodeScalars.allSatisfy { chineseNumbers.contains($0) }
    }
    func replacing(_ text: String) -> [ProtectedTextSegment] {
        guard !entries.isEmpty, !text.isEmpty else { return [.init(text: text, isProtected: false)] }
        var starts = Set<String.Index>(); var ends = Set<String.Index>()
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) { word, range, _, _ in
            guard let word, !word.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) else { return }
            starts.insert(range.lowerBound); ends.insert(range.upperBound)
        }
        var result: [ProtectedTextSegment] = []
        var cursor = text.startIndex
        var pending = ""
        while cursor < text.endIndex {
            let match = starts.contains(cursor) ? entries.first { entry in
                guard text[cursor...].hasPrefix(entry.source),
                      let end = text.index(cursor, offsetBy: entry.source.count, limitedBy: text.endIndex) else { return false }
                return ends.contains(end)
            } : nil
            if let match {
                if !pending.isEmpty { result.append(.init(text: pending, isProtected: false)); pending = "" }
                result.append(.init(text: match.replacement, isProtected: true))
                cursor = text.index(cursor, offsetBy: match.source.count)
            } else { pending.append(text[cursor]); cursor = text.index(after: cursor) }
        }
        if !pending.isEmpty { result.append(.init(text: pending, isProtected: false)) }
        return result
    }
}

public protocol UserDictionaryStorage: Sendable {
    func load() async throws -> [UserDictionaryEntry]
    func save(_ entries: [UserDictionaryEntry]) async throws
}

public actor UserDictionaryFileStore: UserDictionaryStorage {
    private let url: URL
    private struct Document: Codable { let version: Int; let entries: [UserDictionaryEntry] }
    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/VoxInk/Dictionary/words.json")) {
        self.url = url
    }
    public func load() throws -> [UserDictionaryEntry] {
        try prepareDirectory()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        try validateFile()
        let document: Document
        do { document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url)) }
        catch { throw UserDictionaryError.invalidFile }
        guard document.version == 1 else { throw UserDictionaryError.unsupportedVersion }
        try UserDictionaryRules.validate(document.entries)
        return document.entries
    }
    public func save(_ entries: [UserDictionaryEntry]) throws {
        try UserDictionaryRules.validate(entries)
        try prepareDirectory()
        if FileManager.default.fileExists(atPath: url.path) { try validateFile() }
        let data = try JSONEncoder().encode(Document(version: 1, entries: entries))
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        let handle = try ModelStorage.openPartial(temporary)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        guard Darwin.rename(temporary.path, url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
    private func prepareDirectory() throws {
        let directory = url.deletingLastPathComponent()
        try ModelStorage.ensureDirectory(directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutable = directory; try mutable.setResourceValues(values)
    }
    private func validateFile() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.intValue, size <= 128 * 1024 else {
            throw UserDictionaryError.invalidFile
        }
    }
}
