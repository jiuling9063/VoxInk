import Darwin
import Foundation

public protocol ModelDownloadTransport: Sendable {
    func download(_ file: ModelPackage.File, to partialURL: URL,
        progress: @escaping @Sendable (Int64) -> Void) async throws
}

public enum ModelLocations {
    public static var cacheRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VoxInk/Models/\(ModelPackage.revision)", isDirectory: true)
    }
    public static var legacyCacheRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/VoxInkBenchmark", isDirectory: true)
    }
    public static func modelDirectory(in cacheRoot: URL) -> URL {
        cacheRoot.appendingPathComponent("qwen3-speech/models/\(ModelPackage.repository)", isDirectory: true)
    }
}

public actor ModelInstaller {
    private let root: URL
    private let legacyRoot: URL?
    private let transport: any ModelDownloadTransport
    private var installing = false

    public init(root: URL = ModelLocations.cacheRoot, legacyRoot: URL? = ModelLocations.legacyCacheRoot,
                transport: any ModelDownloadTransport = ResumableModelDownload()) {
        self.root = root; self.legacyRoot = legacyRoot; self.transport = transport
    }

    public func ensureInstalled(package: ModelPackage, allowDownload: Bool,
        progress: @escaping @Sendable (ModelInstallationProgress) -> Void = { _ in }) async throws -> URL {
        guard !installing else { throw ModelInstallationError.busy }
        installing = true
        defer { installing = false }
        try Task.checkCancellation()
        try ModelStorage.ensureDirectory(root)
        let lock = try ModelStorage.openPartial(root.appendingPathComponent(".install.lock"))
        guard flock(lock.fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            try? lock.close(); throw ModelInstallationError.busy
        }
        defer { _ = flock(lock.fileDescriptor, LOCK_UN); try? lock.close() }
        let directory = ModelLocations.modelDirectory(in: root)
        try ModelStorage.ensureDirectory(directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        var resource = URLResourceValues(); resource.isExcludedFromBackup = true
        var excludedRoot = root; try excludedRoot.setResourceValues(resource)
        let staging = directory.appendingPathComponent(".partial", isDirectory: true)
        try ModelStorage.ensureDirectory(staging)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: staging.path)
        let names = Set(package.files.map(\.path))
        let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard entries.filter({ $0.pathExtension == "safetensors" }).allSatisfy({ names.contains($0.lastPathComponent) }) else {
            throw ModelInstallationError.unsafePath
        }
        var completed: Int64 = 0
        for file in package.files {
            try Task.checkCancellation()
            guard !file.path.isEmpty, !file.path.hasPrefix("."), !file.path.contains("/"), !file.path.contains("\\") else {
                throw ModelInstallationError.invalidManifest
            }
            let destination = directory.appendingPathComponent(file.path)
            progress(.init(stage: .checking, completedBytes: completed, totalBytes: package.totalBytes))
            if try ModelPackage.matches(file, at: destination) {
                completed += file.sizeBytes
                continue
            }
            let partial = staging.appendingPathComponent(file.path)
            if try ModelPackage.matches(file, at: partial) {
                try ModelStorage.publish(partial, to: destination)
                completed += file.sizeBytes
                continue
            }
            if let legacyRoot {
                let source = ModelLocations.modelDirectory(in: legacyRoot).appendingPathComponent(file.path)
                if (try? ModelPackage.matches(file, at: source)) == true {
                    try Task.checkCancellation()
                    progress(.init(stage: .importing, completedBytes: completed, totalBytes: package.totalBytes))
                    let temporary = staging.appendingPathComponent("import-\(UUID().uuidString)")
                    defer { try? FileManager.default.removeItem(at: temporary) }
                    try FileManager.default.copyItem(at: source, to: temporary)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
                    guard try ModelPackage.matches(file, at: temporary) else { throw ModelInstallationError.checksum(file.path) }
                    try ModelStorage.publish(temporary, to: destination)
                    completed += file.sizeBytes
                    continue
                }
            }
            try Task.checkCancellation()
            guard allowDownload else { throw ModelInstallationError.downloadRequired }
            // A complete but corrupt partial cannot be repaired by appending to it.
            if let attributes = try? FileManager.default.attributesOfItem(atPath: partial.path),
               (attributes[.size] as? NSNumber)?.int64Value ?? 0 >= file.sizeBytes {
                guard attributes[.type] as? FileAttributeType == .typeRegular else { throw ModelInstallationError.unsafePath }
                try FileManager.default.removeItem(at: partial)
            }
            let priorBytes = completed
            try await transport.download(file, to: partial) { bytes in
                progress(.init(stage: .downloading, completedBytes: priorBytes + bytes, totalBytes: package.totalBytes))
            }
            try Task.checkCancellation()
            progress(.init(stage: .verifying, completedBytes: completed + file.sizeBytes, totalBytes: package.totalBytes))
            guard try ModelPackage.matches(file, at: partial) else {
                try? FileManager.default.removeItem(at: partial)
                throw ModelInstallationError.checksum(file.path)
            }
            try ModelStorage.publish(partial, to: destination)
            completed += file.sizeBytes
        }
        let metadata = directory.appendingPathComponent(".cache/huggingface/download", isDirectory: true)
        try ModelStorage.ensureDirectory(metadata)
        for file in package.files {
            try Task.checkCancellation()
            // The pinned Hub loader accepts a SHA-256 content identity in its local
            // metadata and rehashes the file before using the offline snapshot.
            let record = "\(ModelPackage.revision)\n\(file.sha256)\n\(Date().timeIntervalSince1970)\n"
            let temporary = staging.appendingPathComponent("metadata-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            let handle = try ModelStorage.openPartial(temporary)
            try handle.write(contentsOf: Data(record.utf8))
            try handle.close()
            try ModelStorage.publish(temporary, to: metadata.appendingPathComponent(file.path + ".metadata"))
        }
        progress(.init(stage: .verifying, completedBytes: completed, totalBytes: package.totalBytes))
        return root
    }
}

enum ModelStorage {
    static func ensureDirectory(_ url: URL) throws {
        let manager = FileManager.default
        guard url.isFileURL else { throw ModelInstallationError.unsafePath }
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.path.split(separator: "/") {
            guard component != ".", component != ".." else { throw ModelInstallationError.unsafePath }
            current.appendPathComponent(String(component), isDirectory: true)
            if let attributes = try? manager.attributesOfItem(atPath: current.path) {
                guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw ModelInstallationError.unsafePath }
            } else {
                try manager.createDirectory(at: current, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            }
        }
    }

    static func openPartial(_ url: URL) throws -> FileHandle {
        let descriptor = Darwin.open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard descriptor >= 0 else { throw ModelInstallationError.unsafePath }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            try? handle.close(); throw ModelInstallationError.unsafePath
        }
        guard fchmod(descriptor, mode_t(0o600)) == 0 else {
            try? handle.close(); throw CocoaError(.fileWriteNoPermission)
        }
        return handle
    }

    static func publish(_ source: URL, to destination: URL) throws {
        try Task.checkCancellation()
        guard rename(source.path, destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}
