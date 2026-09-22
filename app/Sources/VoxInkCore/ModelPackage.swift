import CryptoKit
import Foundation

public struct ModelPackage: Sendable {
    public struct File: Codable, Sendable {
        public let path: String
        public let sizeBytes: Int64
        public let sha256: String
        public let downloadURL: URL
        enum CodingKeys: String, CodingKey {
            case path, sha256
            case sizeBytes = "size_bytes", downloadURL = "download_url"
        }
    }

    public static let candidateID = "qwen3-asr-0.6b-mlx-4bit"
    public static let repository = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
    public static let revision = "bc441bd1e4295c1f42d9879f056049a925b6e013"
    public let files: [File]
    public var totalBytes: Int64 { files.reduce(0) { $0 + $1.sizeBytes } }

    public init(manifestURL: URL) throws {
        let data = try Data(contentsOf: manifestURL)
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: data) }
        catch { throw ModelInstallationError.invalidManifest }
        let matches = manifest.candidates.filter { $0.id == Self.candidateID }
        guard matches.count == 1, let candidate = matches.first, let model = candidate.model,
              candidate.engine?.source_revision == "d603472b11c21f5fb6492e9448a04ee669d0bf64",
              model.repository == Self.repository,
              model.revision == Self.revision else { throw ModelInstallationError.invalidManifest }
        let files = model.files
        let required: Set<String> = ["config.json", "merges.txt", "model.safetensors",
            "model.safetensors.index.json", "tokenizer_config.json", "vocab.json"]
        guard files.count == required.count, Set(files.map(\.path)) == required,
              model.file_count == files.count else { throw ModelInstallationError.invalidManifest }
        var total: Int64 = 0
        for file in files {
            let expected = "https://huggingface.co/\(Self.repository)/resolve/\(Self.revision)/\(file.path)"
            guard file.sizeBytes > 0, file.sizeBytes < 2_000_000_000,
                  file.sha256.count == 64, file.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
                  file.downloadURL.absoluteString == expected else { throw ModelInstallationError.invalidManifest }
            total += file.sizeBytes
        }
        guard total == model.reported_size_bytes else { throw ModelInstallationError.invalidManifest }
        self.files = files
    }

    // Internal initializer supports tiny, local transport fixtures without changing release metadata.
    init(files: [File]) { self.files = files }

    public static func matches(_ file: File, at url: URL) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value == file.sizeBytes else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        var bytes: Int64 = 0
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            bytes += Int64(chunk.count)
            guard bytes <= file.sizeBytes else { return false }
            digest.update(data: chunk)
        }
        return bytes == file.sizeBytes && digest.finalize().map { String(format: "%02x", $0) }.joined() == file.sha256
    }

    private struct Manifest: Decodable { let candidates: [Candidate] }
    private struct Candidate: Decodable {
        let id: String
        let engine: Engine?
        let model: Model?
        enum CodingKeys: String, CodingKey { case id, engine, model }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            engine = id == ModelPackage.candidateID ? try values.decode(Engine.self, forKey: .engine) : nil
            model = id == ModelPackage.candidateID ? try values.decode(Model.self, forKey: .model) : nil
        }
    }
    private struct Engine: Decodable { let source_revision: String }
    private struct Model: Decodable {
        let repository: String
        let revision: String
        let file_count: Int
        let reported_size_bytes: Int64
        let files: [File]
    }
}

public enum ModelInstallationError: Error, LocalizedError, Equatable {
    case invalidManifest, downloadRequired, unsafePath, checksum(String), response(Int), invalidRange, incomplete, busy
    public var errorDescription: String? {
        switch self {
        case .invalidManifest: L("模型安装清单无效，请重新安装 App。")
        case .downloadRequired: L("需要下载或修复本地模型。")
        case .unsafePath: L("模型目录包含非预期的文件或链接，请检查安装目录。")
        case .checksum(let file): L("模型文件校验失败：\(file)。请重试下载。")
        case .response(let status): L("模型下载服务返回错误（\(status)），请稍后重试。")
        case .invalidRange: L("下载服务返回了不匹配的文件范围，请稍后重试。")
        case .incomplete: L("模型下载未完成，已保留进度，可继续下载。")
        case .busy: L("模型正在准备中，请等待当前操作结束。")
        }
    }
}

public struct ModelInstallationProgress: Sendable {
    public enum Stage: Sendable { case checking, importing, downloading, verifying }
    public let stage: Stage
    public let completedBytes: Int64
    public let totalBytes: Int64
    public init(stage: Stage, completedBytes: Int64, totalBytes: Int64) {
        self.stage = stage; self.completedBytes = completedBytes; self.totalBytes = totalBytes
    }
    public var fraction: Double { totalBytes > 0 ? min(1, max(0, Double(completedBytes) / Double(totalBytes))) : 0 }
    public var title: String {
        switch stage {
        case .checking: L("正在检查本地模型…")
        case .importing: L("正在复用本机已有模型…")
        case .downloading: L("正在下载本地模型…")
        case .verifying: L("正在校验模型文件…")
        }
    }
}
