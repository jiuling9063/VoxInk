import Darwin
import Foundation
import VoxInkCore

@main struct ModelInstallationCheck {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Model check failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var manifest: String?
        var fullRoot: String?
        var smallDownload = false
        var pauseBytes: Int64?
        var index = 0
        while index < arguments.count {
            let option = arguments[index]
            switch option {
            case "--download-small-file": smallDownload = true
            case "--manifest", "--full-download-root", "--pause-after-bytes":
                index += 1
                guard arguments.indices.contains(index) else { throw CheckError.usage }
                switch option {
                case "--manifest": manifest = arguments[index]
                case "--full-download-root": fullRoot = arguments[index]
                default:
                    guard let bytes = Int64(arguments[index]), bytes > 0 else { throw CheckError.usage }
                    pauseBytes = bytes
                }
            default: throw CheckError.usage
            }
            index += 1
        }
        guard let manifest, pauseBytes == nil || fullRoot != nil, !(smallDownload && fullRoot != nil) else { throw CheckError.usage }
        let package = try ModelPackage(manifestURL: URL(fileURLWithPath: manifest))
        let requestedRoot = fullRoot.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? ModelLocations.cacheRoot
        guard fullRoot == nil || requestedRoot.path != ModelLocations.cacheRoot.path else { throw CheckError.usage }
        let directory = ModelLocations.modelDirectory(in: requestedRoot)
        let filesAtStart = package.files.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.path).path) }.count
        let installer = ModelInstaller(root: requestedRoot, legacyRoot: fullRoot == nil ? ModelLocations.legacyCacheRoot : nil,
            transport: CheckDownloadTransport())
        let probe = InstallationProbe(pauseAfter: pauseBytes)
        let installation = Task {
            try await installer.ensureInstalled(package: package, allowDownload: fullRoot != nil) { probe.report($0) }
        }
        probe.attach(installation)
        let root: URL
        do { root = try await installation.value }
        catch {
            if probe.paused {
                try emit(Result(status: "paused", cacheRoot: requestedRoot.path, filesAtStart: filesAtStart,
                    verifiedFiles: 0, verifiedBytes: 0, smallFileDownloadVerified: false))
                return
            }
            throw error
        }
        for file in package.files {
            guard try ModelPackage.matches(file, at: directory.appendingPathComponent(file.path)) else {
                throw ModelInstallationError.checksum(file.path)
            }
        }
        var downloaded = false
        if smallDownload {
            guard let file = package.files.min(by: { $0.sizeBytes < $1.sizeBytes }), file.sizeBytes <= 100_000 else { throw CheckError.noSmallFile }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("VoxInkModelDownloadCheck-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: temporary) }
            let destination = temporary.appendingPathComponent(file.path)
            try await ResumableModelDownload().download(file, to: destination) { _ in }
            guard try ModelPackage.matches(file, at: destination) else { throw ModelInstallationError.checksum(file.path) }
            downloaded = true
        }
        try emit(Result(status: "verified", cacheRoot: root.path, filesAtStart: filesAtStart,
            verifiedFiles: package.files.count, verifiedBytes: package.totalBytes, smallFileDownloadVerified: downloaded))
    }

    private static func emit(_ result: Result) throws { print(String(decoding: try JSONEncoder().encode(result), as: UTF8.self)) }
    private struct Result: Encodable {
        let status: String
        let cacheRoot: String
        let filesAtStart: Int
        let verifiedFiles: Int
        let verifiedBytes: Int64
        let smallFileDownloadVerified: Bool
    }
    private enum CheckError: Error { case usage, noSmallFile }
}

private struct CheckDownloadTransport: ModelDownloadTransport {
    func download(_ file: ModelPackage.File, to partialURL: URL, progress: @escaping @Sendable (Int64) -> Void) async throws {
        let first = FirstOffsetReport(name: file.path)
        try await ResumableModelDownload().download(file, to: partialURL) { bytes in
            first.report(bytes)
            progress(bytes)
        }
    }
}

private final class FirstOffsetReport: @unchecked Sendable {
    private let lock = NSLock()
    private var reported = false
    private let name: String
    init(name: String) { self.name = name }
    func report(_ bytes: Int64) {
        lock.withLock {
            guard !reported else { return }
            reported = true
            FileHandle.standardError.write(Data("TRANSFER \(name) accepted_start_offset=\(bytes)\n".utf8))
        }
    }
}

private final class InstallationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let pauseAfter: Int64?
    private var task: Task<URL, Error>?
    private var didPause = false
    private var lastPercent = -1
    var paused: Bool { lock.withLock { didPause } }
    init(pauseAfter: Int64?) { self.pauseAfter = pauseAfter }
    func attach(_ task: Task<URL, Error>) {
        let cancel = lock.withLock { self.task = task; return didPause }
        if cancel { task.cancel() }
    }
    func report(_ progress: ModelInstallationProgress) {
        let cancellation: Task<URL, Error>? = lock.withLock {
            let percent = Int(progress.fraction * 100)
            if percent != lastPercent {
                lastPercent = percent
                FileHandle.standardError.write(Data("MODEL \(percent)% \(progress.completedBytes)/\(progress.totalBytes)\n".utf8))
            }
            if case .downloading = progress.stage, let pauseAfter, progress.completedBytes >= pauseAfter, !didPause {
                didPause = true
                FileHandle.standardError.write(Data("PAUSE requested at \(progress.completedBytes) bytes\n".utf8))
                return task
            }
            return nil
        }
        cancellation?.cancel()
    }
}
