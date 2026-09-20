import Foundation

public enum UserDictionaryCSV {
    public static let maximumBytes = 128 * 1024
    public struct Row: Sendable {
        public let number: Int
        public let source: String
        public let replacement: String
    }
    public enum FormatError: LocalizedError {
        case invalid
        public var errorDescription: String? { "请使用 UTF-8 CSV 文件，首行为“识别词,正确写法”，每行两列，文件不超过 128 KB。" }
    }
    public static func decode(_ data: Data) throws -> [Row] {
        guard data.count <= maximumBytes, var text = String(data: data, encoding: .utf8) else { throw FormatError.invalid }
        if text.first == "\u{FEFF}" { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var records: [[String]] = [], fields: [String] = [], field = ""
        var quoted = false, closed = false
        let chars = Array(text); var i = 0
        while i < chars.count {
            let c = chars[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append(c); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "," || c == "\n" {
                fields.append(field); field = ""; closed = false
                if c == "\n" { records.append(fields); fields = [] }
            } else if c == "\"", field.isEmpty, !closed { quoted = true }
            else {
                guard !closed, c != "\"" else { throw FormatError.invalid }
                field.append(c)
            }
            i += 1
        }
        guard !quoted else { throw FormatError.invalid }
        if !field.isEmpty || !fields.isEmpty || closed { fields.append(field); records.append(fields) }
        guard let header = records.first, header == ["识别词", "正确写法"] || header == ["source", "replacement"] else { throw FormatError.invalid }
        return try records.dropFirst().enumerated().compactMap { index, fields in
            if fields == [""] { return nil }
            guard fields.count == 2 else { throw FormatError.invalid }
            return Row(number: index + 2, source: fields[0], replacement: fields[1])
        }
    }
    public static func encode(_ entries: [UserDictionaryEntry]) -> Data {
        func quote(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let lines = entries.map { quote($0.source) + "," + quote($0.replacement) }
        return Data(("\u{FEFF}识别词,正确写法\r\n" + lines.joined(separator: "\r\n") + "\r\n").utf8)
    }
}
