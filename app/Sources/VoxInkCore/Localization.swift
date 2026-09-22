import Foundation

public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public let key: String
    public let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key; arguments = stringInterpolation.arguments
    }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"; arguments.append(String(describing: value))
        }
    }
}

public enum Localization {
    // Interface changes take effect after relaunch, including native menus and permission dialogs.
    public static let language: InterfaceLanguage = {
        let override = ProcessInfo.processInfo.environment["VOXINK_UI_LANGUAGE"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "VoxInkPreviewLanguage") as? String)
        let saved = UserDefaults.standard.string(forKey: "interfaceLanguage")
        return InterfaceLanguage.resolve((override ?? saved).flatMap(InterfaceLanguage.init(rawValue:)) ?? .system)
    }()
    public static let catalogs: [String: [String: String]] = {
        var result: [String: [String: String]] = [:]
        for language in ["en", "ja", "ko", "zh-Hant"] {
            if let url = Bundle.module.url(forResource: language, withExtension: "json"),
               let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode([String: String].self, from: data) {
                result[language] = catalog
            }
        }
        return result
    }()
    public static func text(_ message: LocalizedMessage, language: InterfaceLanguage = language) -> String {
        let template = catalogs[language.rawValue]?[message.key] ?? message.key
        // Substitute in one pass so user text resembling a placeholder stays literal.
        var result = "", cursor = template.startIndex
        while cursor < template.endIndex {
            if template[cursor] == "{", let end = template[cursor...].firstIndex(of: "}"),
               let index = Int(template[template.index(after: cursor)..<end]), message.arguments.indices.contains(index) {
                result += message.arguments[index]; cursor = template.index(after: end)
            } else { result.append(template[cursor]); cursor = template.index(after: cursor) }
        }
        return result
    }
}

public func L(_ message: LocalizedMessage) -> String { Localization.text(message) }
