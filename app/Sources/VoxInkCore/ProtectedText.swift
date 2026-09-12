import Foundation

struct ProtectedTextSegment {
    let text: String
    let isProtected: Bool
}

// Keep original substrings rather than replace them with collision-prone placeholder tokens.
enum ProtectedText {
    private static let expression: NSRegularExpression? = {
        let arabicNumber = #"[+\-−]?(?:[0-9]{1,3}(?:\h+[0-9]{3})+|[0-9]+)(?:[.,:/%％\-][0-9]+)*"#
        let patterns = [
            #"```[\s\S]*?(?:```|\z)|~~~[\s\S]*?(?:~~~|\z)"#,
            #"`[^`\r\n]*(?:`|\z)"#,
            #"["'](?:~/|/|\.{1,2}/|[A-Za-z]:\\)[^"'\r\n]*["']"#,
            #"(?:https?://|www\.)[^\s<>\"'，。；！？、]+"#,
            #"[\p{L}\p{N}._%+\-]+@[\p{L}\p{N}.\-]+"#,
            #"(?:~/|/|\.{1,2}/|[A-Za-z]:\\)[^\s<>\"'，。；！？、`]+"#,
            #"[0-9]{4}\h*年\h*[0-9]{1,2}\h*月\h*[0-9]{1,2}\h*日"#,
            #"[￥¥$€£]\h*"# + arabicNumber,
            #"[A-Za-z][A-Za-z0-9]*_[\p{L}\p{N}_]+"#,
            #"[A-Za-z_][A-Za-z0-9_\p{M}]*(?:[.\-][A-Za-z0-9_\p{M}]+)*"#,
            arabicNumber + #"(?:[%％]|\h*(?:元|圓|圆|美元|人民幣|人民币))?"#,
            #"(?:負|负|正)?[零〇一二三四五六七八九十百千万亿兆兩两壹貳贰參叁肆伍陸陆柒捌玖拾佰仟萬億]+(?:(?:點|点)[零〇一二三四五六七八九]+)?"#
        ]
        return try? NSRegularExpression(pattern: patterns.joined(separator: "|"))
    }()

    static func segments(in raw: String) -> [ProtectedTextSegment]? {
        guard let expression else { return nil }
        let source = raw as NSString
        var segments: [ProtectedTextSegment] = []
        var cursor = 0
        for match in expression.matches(in: raw, range: NSRange(location: 0, length: source.length)) {
            if match.range.location > cursor {
                segments.append(.init(text: source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), isProtected: false))
            }
            segments.append(.init(text: source.substring(with: match.range), isProtected: true))
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length {
            segments.append(.init(text: source.substring(from: cursor), isProtected: false))
        }
        return segments
    }
}
