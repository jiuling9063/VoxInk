import Foundation

public enum LightTextPolisher {
    public static func polish(_ text: String) -> String {
        guard let segments = ProtectedText.segments(in: text) else { return text }
        return segments.map { segment in
            guard !segment.isProtected else { return segment.text }
            return segment.text
                .replacingOccurrences(of: "[。！？][”’」』）]?", with: "$0\n", options: .regularExpression)
                .replacingOccurrences(of: "\n[ \t]*\n+", with: "\n\n", options: .regularExpression)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
