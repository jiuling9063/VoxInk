import Foundation
import OpenCCSwift

public struct SimplifiedTextResult: Equatable, Sendable {
    public enum Mode: Equatable, Sendable { case openCC, characterFallback, unconverted }
    public let text: String
    public let mode: Mode
    public var warning: String? {
        switch mode {
        case .openCC: nil
        case .characterFallback: "简体词库不可用，仅完成字符级转换"
        case .unconverted: "简体转换失败，已保留原文"
        }
    }
}

@MainActor public final class SimplifiedTextConverter {
    public static let shared = SimplifiedTextConverter()
    public static let configuration = "OpenCC full twp → cn"
    private let primary: ((String) -> String)?
    private let fallback: (String) -> String?

    private convenience init() {
        // This preset is locked by character and Mainland vocabulary fixtures.
        let converter = try? OpenCC.converter(from: "twp", to: "cn")
        self.init(primary: converter.map { value in { value.convert($0) } })
    }

    init(primary: ((String) -> String)?,
         fallback: @escaping (String) -> String? = { $0.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) }) {
        self.primary = primary
        self.fallback = fallback

    }

    public func convert(_ raw: String) -> SimplifiedTextResult {
        guard let segments = ProtectedText.segments(in: raw) else { return .init(text: raw, mode: .unconverted) }
        var output = ""
        let mode: SimplifiedTextResult.Mode = primary == nil ? .characterFallback : .openCC
        for segment in segments {
            if segment.isProtected { output += segment.text; continue }
            let converted = convertUnprotected(segment.text)
            guard converted.mode != .unconverted else { return .init(text: raw, mode: .unconverted) }
            output += converted.text
        }
        return .init(text: output, mode: mode)
    }

    func convertUnprotected(_ text: String) -> SimplifiedTextResult {
        if let primary {
            // The pinned twp dictionary maps 檔案 → 文件 but also 文件 → 文档.
            // Preserve the already-correct Mainland noun so a later pass cannot rewrite it.
            let converted = text.components(separatedBy: "文件").map(primary).joined(separator: "文件")
            return .init(text: converted, mode: .openCC)
        }
        guard let converted = fallback(text) else { return .init(text: text, mode: .unconverted) }
        return .init(text: converted, mode: .characterFallback)
    }
}
