import Darwin
import Foundation
import Testing
@testable import VoxInkCore

private final class RecoveryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_789_000_000)
    func now() -> Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}

private func recoveryFixture() throws -> (URL, URL) {
    guard let resolved = realpath(FileManager.default.temporaryDirectory.path, nil) else { throw CocoaError(.fileNoSuchFile) }
    let path = String(cString: resolved); free(resolved)
    let root = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("VoxInkRecoveryTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    let source = root.appendingPathComponent("source.wav")
    try Data("private audio fixture".utf8).write(to: source)
    return (root, source)
}

struct AudioRecoveryStoreTests {
    @Test func survivesNewStoreAndPreservesOriginalFile() async throws {
        let (root, source) = try recoveryFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let clock = RecoveryClock()
        let directory = root.appendingPathComponent("recovery")
        let store = AudioRecoveryStore(root: directory, now: clock.now)
        let record = try await store.save(source)
        #expect(try Data(contentsOf: record.url) == Data(contentsOf: source))
        let restored = try await AudioRecoveryStore(root: directory, now: clock.now).latest()
        #expect(restored == record)
        let attributes = try FileManager.default.attributesOfItem(atPath: record.url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let folder = try FileManager.default.attributesOfItem(atPath: record.url.deletingLastPathComponent().path)
        #expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func expiryDoesNotExtendWhenRecordIsRestored() async throws {
        let (root, source) = try recoveryFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let clock = RecoveryClock()
        let store = AudioRecoveryStore(root: root.appendingPathComponent("recovery"), now: clock.now)
        let record = try await store.save(source)
        clock.advance(86_399)
        #expect(try await store.latest() == record)
        clock.advance(1)
        #expect(try await store.latest() == nil)
        #expect(!FileManager.default.fileExists(atPath: record.url.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func onlyNewestRecordRemainsAndDiscardIsScopedByID() async throws {
        let (root, source) = try recoveryFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let store = AudioRecoveryStore(root: root.appendingPathComponent("recovery"))
        let first = try await store.save(source)
        let second = try await store.save(source)
        #expect(!FileManager.default.fileExists(atPath: first.url.path))
        try await store.discard(first.id)
        #expect(try await store.latest() == second)
        try await store.discard(second.id)
        #expect(try await store.latest() == nil)
    }

    @Test func corruptMetadataIsRemovedWithoutTouchingOtherFiles() async throws {
        let (root, source) = try recoveryFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("recovery")
        let store = AudioRecoveryStore(root: directory)
        let record = try await store.save(source)
        let unrelated = directory.appendingPathComponent("notes.txt"); try Data("keep".utf8).write(to: unrelated)
        try Data("broken".utf8).write(to: record.url.deletingLastPathComponent().appendingPathComponent("metadata.json"))
        #expect(try await store.latest() == nil)
        #expect(try String(contentsOf: unrelated, encoding: .utf8) == "keep")
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func rejectsSymlinkSourceAndLinkedStorageRoot() async throws {
        let (root, source) = try recoveryFixture(); defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("link.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        let store = AudioRecoveryStore(root: root.appendingPathComponent("recovery"))
        await #expect(throws: (any Error).self) { try await store.save(link) }
        let linkedRoot = root.appendingPathComponent("linked-root")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: root)
        await #expect(throws: (any Error).self) {
            try await AudioRecoveryStore(root: linkedRoot).save(source)
        }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }
}
