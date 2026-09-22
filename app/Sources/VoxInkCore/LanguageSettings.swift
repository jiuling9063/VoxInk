import Foundation
import NaturalLanguage
import OpenCCSwift

public enum InterfaceLanguage: String, CaseIterable, Sendable {
    case system, simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant", english = "en", japanese = "ja", korean = "ko"
    public var nativeName: String {
        switch self {
        case .system: L("跟随系统")
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .english: "English"
        case .japanese: "日本語"
        case .korean: "한국어"
        }
    }
    public static func resolve(_ choice: Self, preferredLanguages: [String] = Locale.preferredLanguages) -> Self {
        guard choice == .system else { return choice }
        for identifier in preferredLanguages {
            if identifier.hasPrefix("zh") {
                if identifier.contains("Hans") { return .simplifiedChinese }
                if identifier.contains("Hant") { return .traditionalChinese }
                return identifier.contains("TW") || identifier.contains("HK") || identifier.contains("MO") ? .traditionalChinese : .simplifiedChinese
            }
            for language in [Self.english, .japanese, .korean] where identifier.hasPrefix(language.rawValue) { return language }
        }
        return .english
    }
}

public enum SpeechLanguage: String, CaseIterable, Codable, Sendable {
    case automatic = "auto", mandarin = "zh", cantonese = "yue", english = "en", japanese = "ja", korean = "ko"
    public var title: String {
        switch self {
        case .automatic: L("自动检测")
        case .mandarin: L("普通话")
        case .cantonese: L("粤语")
        case .english: L("英语")
        case .japanese: L("日语")
        case .korean: L("韩语")
        }
    }
    public func resolved(for text: String) -> Self {
        guard self == .automatic else { return self }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let scores = recognizer.languageHypotheses(withMaximum: 1)
        guard let (language, confidence) = scores.first, confidence >= 0.8 else { return .automatic }
        switch language {
        case .simplifiedChinese, .traditionalChinese: return .mandarin
        case .english: return .english
        case .japanese: return .japanese
        case .korean: return .korean
        default: return .automatic
        }
    }
}

public enum ChineseOutput: String, CaseIterable, Sendable {
    case simplified, traditional, original
    public var title: String {
        switch self {
        case .simplified: L("简体中文")
        case .traditional: L("繁体中文")
        case .original: L("保留原样")
        }
    }
}

@MainActor public enum LanguageTextProcessor {
    private static let traditional = try? OpenCC.converter(from: "cn", to: "twp")
    public static func process(_ text: String, language: SpeechLanguage, output: ChineseOutput,
                               dictionary: UserDictionaryRules = .empty) -> SimplifiedTextResult {
        let resolved = language.resolved(for: text)
        let chinese = resolved == .mandarin || resolved == .cantonese
        if chinese, output == .simplified {
            return DeterministicTextProcessor.shared.process(text, dictionary: dictionary, dictionaryFirst: true)
        }
        if chinese, output == .traditional {
            guard let traditional else { return .init(text: text, mode: .unconverted) }
            return DeterministicTextProcessor.shared.preservingScript(text, dictionary: dictionary, convert: { traditional.convert($0) })
        }
        return DeterministicTextProcessor.shared.preservingScript(text, dictionary: dictionary)
    }
}
