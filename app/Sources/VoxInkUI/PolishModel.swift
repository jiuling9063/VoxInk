import Foundation

public enum PolishModel: String, CaseIterable, Sendable {
    case light, balanced, medium, quality

    public var title: String {
        switch self {
        case .light: "轻量"
        case .balanced: "均衡"
        case .medium: "中量"
        case .quality: "最佳效果"
        }
    }

    var modelName: String {
        switch self {
        case .light: "Qwen3-1.7B-4bit"
        case .balanced: "Qwen3-4B-Instruct-2507-4bit"
        case .medium: "Qwen3-8B-4bit"
        case .quality: "Qwen3-14B-4bit"
        }
    }
    var repository: String { "mlx-community/" + modelName }
    var revision: String {
        switch self {
        case .light: "3b1b1768f8f8cf8351c712464f906e86c2b8269e"
        case .balanced: "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b"
        case .medium: "545dc4251c05440727734bcd94334791f6ab0192"
        case .quality: "a4d9b2df59d2c150bef02fcbe0d91046b7ca33a4"
        }
    }
    var detail: String {
        switch self {
        case .light: "约 1 GB · 速度优先，适合短句"
        case .balanced: "约 2.3 GB · 日常输入，兼顾速度与效果"
        case .medium: "约 4.6 GB · 适合更复杂的表达，等待更久"
        case .quality: "约 8.3 GB · 效果优先，建议 24 GB 及以上内存"
        }
    }

    func directory(in root: URL) -> URL {
        root.appendingPathComponent("models").appendingPathComponent(revision)
    }
}
