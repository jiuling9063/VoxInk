import Foundation

public struct RetainedAudio: Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let url: URL
    public var expiresAt: Date { createdAt.addingTimeInterval(86_400) }
    public init(id: UUID, createdAt: Date, url: URL) { self.id = id; self.createdAt = createdAt; self.url = url }
}

public protocol AudioRecoveryStorage: Sendable {
    func save(_ source: URL) async throws -> RetainedAudio
    func latest() async throws -> RetainedAudio?
    func discard(_ id: UUID) async throws
    func purgeExpired() async throws
}

public actor AudioRecoveryStore: AudioRecoveryStorage {
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/VoxInk/AudioRecovery", isDirectory: true)
    }
    private let root: URL
    private let now: @Sendable () -> Date
    private struct Metadata: Codable { let id: UUID; let createdAt: Date }
    public init(root: URL = AudioRecoveryStore.defaultRoot, now: @escaping @Sendable () -> Date = Date.init) {
        self.root = root; self.now = now
    }

    public func save(_ source: URL) throws -> RetainedAudio {
        try Task.checkCancellation()
        try prepareRoot()
        guard source.isFileURL else { throw RecoveryError.invalidAudio }
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0, size <= 2_100_000 else {
            throw RecoveryError.invalidAudio
        }
        let id = UUID()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let destination = directory.appendingPathComponent("audio.wav")
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            try Task.checkCancellation()
            let copied = try FileManager.default.attributesOfItem(atPath: destination.path)
            guard copied[.type] as? FileAttributeType == .typeRegular else { throw RecoveryError.invalidAudio }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            let createdAt = now()
            let metadata = directory.appendingPathComponent("metadata.json")
            try JSONEncoder().encode(Metadata(id: id, createdAt: createdAt)).write(to: metadata, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadata.path)
            for other in try directories() where other.lastPathComponent != id.uuidString {
                try FileManager.default.removeItem(at: other)
            }
            return RetainedAudio(id: id, createdAt: createdAt, url: destination)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    public func latest() throws -> RetainedAudio? {
        try purgeExpired()
        let records = try directories().compactMap { try? read($0) }.sorted { $0.createdAt > $1.createdAt }
        for record in records.dropFirst() { try discard(record.id) }
        return records.first
    }

    public func discard(_ id: UUID) throws {
        try prepareRoot()
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw RecoveryError.invalidStorage }
        try FileManager.default.removeItem(at: directory)
    }

    public func purgeExpired() throws {
        try prepareRoot()
        for directory in try directories() {
            if let record = try? read(directory), record.expiresAt > now(), record.createdAt <= now().addingTimeInterval(300) {
                continue
            } else {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }

    private func prepareRoot() throws {
        do { try ModelStorage.ensureDirectory(root) }
        catch { throw RecoveryError.invalidStorage }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var url = root; try url.setResourceValues(values)
    }

    private func directories() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { url in
            UUID(uuidString: url.lastPathComponent) != nil &&
                (try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType) == .typeDirectory
        }
    }

    private func read(_ directory: URL) throws -> RetainedAudio {
        let metadataURL = directory.appendingPathComponent("metadata.json")
        let metadataAttributes = try FileManager.default.attributesOfItem(atPath: metadataURL.path)
        guard metadataAttributes[.type] as? FileAttributeType == .typeRegular,
              (metadataAttributes[.size] as? NSNumber)?.int64Value ?? 0 < 4_096 else { throw RecoveryError.invalidStorage }
        let metadata = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metadataURL))
        guard metadata.id.uuidString == directory.lastPathComponent else { throw RecoveryError.invalidStorage }
        let audio = directory.appendingPathComponent("audio.wav")
        let attributes = try FileManager.default.attributesOfItem(atPath: audio.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.int64Value, size > 0, size <= 2_100_000 else {
            throw RecoveryError.invalidAudio
        }
        return RetainedAudio(id: metadata.id, createdAt: metadata.createdAt, url: audio)
    }

    public enum RecoveryError: Error { case invalidStorage, invalidAudio }
}
