import CryptoKit
import Darwin
import Foundation
import Testing
@testable import VoxInkCore

private let payload = Data(String(repeating: "abcdefghij", count: 10_000).utf8)
private let partialByteCount = 40_000

private func modelFile(_ mode: String = "resume") -> ModelPackage.File {
    .init(path: "model.safetensors", sizeBytes: Int64(payload.count),
        sha256: SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined(),
        downloadURL: URL(string: "https://huggingface.co/voxink-fixture/\(mode)")!)
}

private final class RangeURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let mode = request.url!.lastPathComponent
        let range = request.value(forHTTPHeaderField: "Range")
        var status = 200
        var bytes = payload
        var headers: [String: String] = [:]
        if mode == "resume" || mode == "interrupt", range != nil {
            guard range == "bytes=\(partialByteCount)-" else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
            }
            status = 206; bytes = payload.dropFirst(partialByteCount)
            headers["Content-Range"] = "bytes \(partialByteCount)-\(payload.count - 1)/\(payload.count)"
        } else if mode == "invalid-range" {
            status = 206; bytes = payload.dropFirst(partialByteCount)
            headers["Content-Range"] = "bytes \(partialByteCount - 1)-\(payload.count - 2)/\(payload.count)"
        } else if mode == "oversized" { bytes = payload + payload }
        else if mode == "corrupt" { bytes = Data(repeating: 120, count: payload.count) }
        else if mode == "unavailable" { status = 503 }
        headers["Content-Length"] = String(bytes.count)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if mode == "cancel" || (mode == "interrupt" && range == nil) {
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(20)) { [self] in
                client?.urlProtocol(self, didLoad: payload.prefix(partialByteCount))
                if mode == "interrupt" {
                    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50)) { [self] in
                        client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
                    }
                }
            }
            return
        }
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func transport() -> ResumableModelDownload {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RangeURLProtocol.self]
    return ResumableModelDownload(configuration: config)
}

private func temporaryRoot() throws -> URL {
    guard let resolved = realpath(FileManager.default.temporaryDirectory.path, nil) else { throw CocoaError(.fileNoSuchFile) }
    let temporary = String(cString: resolved); free(resolved)
    let root = URL(fileURLWithPath: temporary, isDirectory: true).appendingPathComponent("VoxInkModelTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    return root
}

private final class ByteProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int64 = 0
    var value: Int64 { lock.withLock { stored } }
    func update(_ bytes: Int64) { lock.withLock { stored = bytes } }
}

struct ModelInstallationTests {
    @Test func filesystemRootTerminatesDirectoryValidation() throws {
        try ModelStorage.ensureDirectory(URL(fileURLWithPath: "/", isDirectory: true))
    }
    @Test func bundledManifestHasPinnedDownloadAddresses() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let package = try ModelPackage(manifestURL: project.appendingPathComponent("benchmark/model-manifest.json"))
        #expect(package.files.count == 6)
        #expect(package.totalBytes == 712_777_119)
        #expect(package.files.allSatisfy { $0.downloadURL.path.contains(ModelPackage.revision) })
    }

    @Test(arguments: ["url", "hash", "size", "revision", "duplicate", "missing"])
    func invalidManifestCannotDirectDownloads(change: String) throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: project.appendingPathComponent("benchmark/model-manifest.json"))) as? [String: Any])
        var candidates = try #require(manifest["candidates"] as? [[String: Any]])
        let index = try #require(candidates.firstIndex { $0["id"] as? String == ModelPackage.candidateID })
        var model = try #require(candidates[index]["model"] as? [String: Any])
        var files = try #require(model["files"] as? [[String: Any]])
        switch change {
        case "url": files[0]["download_url"] = "https://example.com/other-model"
        case "hash": files[0]["sha256"] = "invalid"
        case "size": files[0]["size_bytes"] = -1
        case "revision": model["revision"] = "main"
        case "duplicate": files.append(files[0])
        default: files[0].removeValue(forKey: "download_url")
        }
        model["files"] = files; candidates[index]["model"] = model; manifest["candidates"] = candidates
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: manifest).write(to: file)
        #expect(throws: ModelInstallationError.invalidManifest) { try ModelPackage(manifestURL: file) }
    }

    @Test(arguments: ["resume", "restart"])
    func partialDownloadResumesOrRestartsIfServerIgnoresRange(mode: String) async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let partial = root.appendingPathComponent("file.part")
        try payload.prefix(partialByteCount).write(to: partial)
        try await transport().download(modelFile(mode), to: partial) { _ in }
        #expect(try Data(contentsOf: partial) == payload)
    }

    @Test func invalidRangeDoesNotAppendWrongBytes() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let partial = root.appendingPathComponent("file.part")
        try payload.prefix(partialByteCount).write(to: partial)
        await #expect(throws: ModelInstallationError.invalidRange) {
            try await transport().download(modelFile("invalid-range"), to: partial) { _ in }
        }
        #expect(try Data(contentsOf: partial) == payload.prefix(partialByteCount))
    }

    @Test func networkInterruptionKeepsBytesForNextAttempt() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let partial = root.appendingPathComponent("file.part")
        await #expect(throws: (any Error).self) {
            try await transport().download(modelFile("interrupt"), to: partial) { _ in }
        }
        #expect(try Data(contentsOf: partial) == payload.prefix(partialByteCount))
        try await transport().download(modelFile("interrupt"), to: partial) { _ in }
        #expect(try Data(contentsOf: partial) == payload)
    }

    @Test func cancellationClosesTransferAndKeepsPartial() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let partial = root.appendingPathComponent("file.part")
        let probe = ByteProbe()
        let task = Task { try await transport().download(modelFile("cancel"), to: partial) { probe.update($0) } }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while probe.value < partialByteCount && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(probe.value == partialByteCount)
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        #expect(try Data(contentsOf: partial) == payload.prefix(partialByteCount))
    }

    @Test func installedModelNeedsNoNetworkAndMigrationPreservesSource() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old")
        let oldDirectory = ModelLocations.modelDirectory(in: old)
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        let source = oldDirectory.appendingPathComponent("model.safetensors")
        try payload.write(to: source)
        let new = root.appendingPathComponent("new")
        let installer = ModelInstaller(root: new, legacyRoot: old, transport: transport())
        let package = ModelPackage(files: [modelFile("unavailable")])
        let installedRoot = try await installer.ensureInstalled(package: package, allowDownload: false)
        #expect(installedRoot == new)
        #expect(try Data(contentsOf: source) == payload)
        #expect(try Data(contentsOf: ModelLocations.modelDirectory(in: new).appendingPathComponent("model.safetensors")) == payload)
        let metadata = ModelLocations.modelDirectory(in: new).appendingPathComponent(".cache/huggingface/download/model.safetensors.metadata")
        let lines = try String(contentsOf: metadata, encoding: .utf8).split(separator: "\n")
        #expect(lines[0] == Substring(ModelPackage.revision))
        #expect(lines[1] == Substring(package.files[0].sha256))
        #expect(Double(lines[2]) != nil)
        _ = try await installer.ensureInstalled(package: package, allowDownload: false)
    }

    @Test func missingModelWaitsForExplicitDownload() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let installer = ModelInstaller(root: root, legacyRoot: nil, transport: transport())
        await #expect(throws: ModelInstallationError.downloadRequired) {
            try await installer.ensureInstalled(package: ModelPackage(files: [modelFile()]), allowDownload: false)
        }
        _ = try await installer.ensureInstalled(package: ModelPackage(files: [modelFile()]), allowDownload: true)
        #expect(try Data(contentsOf: ModelLocations.modelDirectory(in: root).appendingPathComponent("model.safetensors")) == payload)
    }

    @Test func corruptDownloadNeverReplacesExistingModelAndRetryRecovers() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = ModelLocations.modelDirectory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("model.safetensors")
        let oldBytes = Data("old".utf8); try oldBytes.write(to: destination)
        let installer = ModelInstaller(root: root, legacyRoot: nil, transport: transport())
        await #expect(throws: ModelInstallationError.checksum("model.safetensors")) {
            try await installer.ensureInstalled(package: ModelPackage(files: [modelFile("corrupt")]), allowDownload: true)
        }
        #expect(try Data(contentsOf: destination) == oldBytes)
        _ = try await installer.ensureInstalled(package: ModelPackage(files: [modelFile()]), allowDownload: true)
        #expect(try Data(contentsOf: destination) == payload)
    }

    @Test func symlinkPartialAndUnexpectedWeightsAreRejected() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("private-file"); try payload.write(to: target)
        let link = root.appendingPathComponent("linked.part")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        await #expect(throws: ModelInstallationError.unsafePath) {
            try await transport().download(modelFile(), to: link) { _ in }
        }
        #expect(try Data(contentsOf: target) == payload)
        let directory = ModelLocations.modelDirectory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try payload.write(to: directory.appendingPathComponent("unknown.safetensors"))
        let installer = ModelInstaller(root: root, legacyRoot: nil, transport: transport())
        await #expect(throws: ModelInstallationError.unsafePath) {
            try await installer.ensureInstalled(package: ModelPackage(files: [modelFile()]), allowDownload: true)
        }
    }

    @Test func oversizeResponseIsRejectedBeforeWriting() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let partial = root.appendingPathComponent("file.part")
        await #expect(throws: ModelInstallationError.invalidRange) {
            try await transport().download(modelFile("oversized"), to: partial) { _ in }
        }
        #expect(try Data(contentsOf: partial).isEmpty)
    }

    @Test func concurrentInstallerCannotWriteSamePartialAndLockReleasesAfterCancel() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let first = ModelInstaller(root: root, legacyRoot: nil, transport: transport())
        let second = ModelInstaller(root: root, legacyRoot: nil, transport: transport())
        let probe = ByteProbe()
        let task = Task {
            try await first.ensureInstalled(package: ModelPackage(files: [modelFile("cancel")]), allowDownload: true) {
                if case .downloading = $0.stage { probe.update($0.completedBytes) }
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while probe.value < partialByteCount && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(probe.value == partialByteCount)
        await #expect(throws: ModelInstallationError.busy) {
            try await second.ensureInstalled(package: ModelPackage(files: [modelFile()]), allowDownload: true)
        }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
        _ = try await second.ensureInstalled(package: ModelPackage(files: [modelFile()]), allowDownload: true)
        #expect(try Data(contentsOf: ModelLocations.modelDirectory(in: root).appendingPathComponent("model.safetensors")) == payload)
    }
}
