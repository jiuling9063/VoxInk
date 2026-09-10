import CryptoKit
import Foundation

public struct VerifiedModel: Equatable, Sendable {
    public let revision: String
    public let directory: URL
}

public enum ModelVerifier {
    public static func verify(manifestURL: URL, directory: URL) throws -> VerifiedModel {
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        let candidates = manifest.candidates.filter { $0.id == SmokeContract.engine }
        guard candidates.count == 1, let candidate = candidates.first,
              candidate.engine.source_revision == SmokeContract.engineRevision,
              candidate.model.repository == SmokeContract.modelID,
              candidate.model.revision == SmokeContract.modelRevision else {
            throw VerificationError.identityMismatch
        }
        let files = candidate.model.files
        let names = Set(files.map(\.path))
        let requiredNames: Set<String> = [
            "config.json", "merges.txt", "model.safetensors",
            "model.safetensors.index.json", "tokenizer_config.json", "vocab.json"
        ]
        guard names == requiredNames, names.count == files.count else {
            throw VerificationError.invalidManifest
        }
        let root = directory.standardizedFileURL.resolvingSymlinksInPath()
        for file in files {
            guard !file.path.isEmpty, !file.path.hasPrefix("."),
                  !file.path.contains("/"), !file.path.contains("\\"),
                  file.size_bytes > 0,
                  file.sha256.count == 64,
                  file.sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
                throw VerificationError.invalidManifest
            }
            let url = root.appendingPathComponent(file.path)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.uint64Value == file.size_bytes else {
                throw VerificationError.fileMismatch(file.path)
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var digest = SHA256()
            var bytes: UInt64 = 0
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                bytes += UInt64(chunk.count)
                guard bytes <= file.size_bytes else { throw VerificationError.fileMismatch(file.path) }
                digest.update(data: chunk)
            }
            let actual = digest.finalize().map { String(format: "%02x", $0) }.joined()
            guard bytes == file.size_bytes, actual == file.sha256 else {
                throw VerificationError.fileMismatch(file.path)
            }
        }
        // The pinned loader discovers weights by extension; unlisted shards must not be loaded.
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        guard entries.filter({ $0.pathExtension == "safetensors" }).allSatisfy({ names.contains($0.lastPathComponent) }) else {
            throw VerificationError.unlistedWeights
        }
        return VerifiedModel(revision: candidate.model.revision, directory: root)
    }

    private struct Manifest: Decodable { let candidates: [Candidate] }
    private struct Candidate: Decodable {
        let id: String
        let engine: Engine
        let model: Model
    }
    private struct Engine: Decodable { let source_revision: String }
    private struct Model: Decodable {
        let repository: String
        let revision: String
        let files: [ModelFile]
    }
    private struct ModelFile: Decodable {
        let path: String
        let size_bytes: UInt64
        let sha256: String
    }

    public enum VerificationError: Error, LocalizedError {
        case identityMismatch
        case invalidManifest
        case fileMismatch(String)
        case unlistedWeights

        public var errorDescription: String? {
            switch self {
            case .identityMismatch: "model or engine identity does not match the pinned smoke contract"
            case .invalidManifest: "model manifest contains invalid or duplicate file entries"
            case .fileMismatch(let name): "model file failed size, type or SHA-256 verification: \(name)"
            case .unlistedWeights: "model directory contains weights absent from the manifest"
            }
        }
    }
}
