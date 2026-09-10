import Foundation
import Testing
@testable import VoxInkCore

struct AudioTemporaryCleanupTests {
    @Test func onlyExpiredOwnedAudioDirectoriesAreRemoved() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: root) }
        let expired = root.appendingPathComponent(UUID().uuidString)
        let recent = root.appendingPathComponent(UUID().uuidString)
        let unrelated = root.appendingPathComponent(UUID().uuidString)
        let named = root.appendingPathComponent("notes")
        for url in [expired, recent, unrelated, named] {
            try manager.createDirectory(at: url, withIntermediateDirectories: false)
            try Data([1]).write(to: url.appendingPathComponent(url == unrelated ? "notes.txt" : "audio.wav"))
        }
        let now = Date().addingTimeInterval(90_000)
        try manager.setAttributes([.modificationDate: now], ofItemAtPath: recent.appendingPathComponent("audio.wav").path)
        try AudioFilePreparation.purgeExpiredTemporaryAudio(in: root, now: now)
        #expect(!manager.fileExists(atPath: expired.path))
        for url in [recent, unrelated, named] { #expect(manager.fileExists(atPath: url.path)) }
    }

    @Test func linksNeverLeadCleanupOutsideRoot() throws {
        let manager = FileManager.default
        let parent = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = parent.appendingPathComponent("root")
        let outside = parent.appendingPathComponent("outside")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try manager.createDirectory(at: outside, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: parent) }
        try Data([1]).write(to: outside.appendingPathComponent("audio.wav"))
        try manager.createSymbolicLink(at: root.appendingPathComponent(UUID().uuidString), withDestinationURL: outside)
        try AudioFilePreparation.purgeExpiredTemporaryAudio(in: root, now: Date().addingTimeInterval(90_000))
        #expect(manager.fileExists(atPath: outside.appendingPathComponent("audio.wav").path))
        let linkedRoot = parent.appendingPathComponent("link")
        try manager.createSymbolicLink(at: linkedRoot, withDestinationURL: outside)
        #expect(throws: (any Error).self) {
            try AudioFilePreparation.purgeExpiredTemporaryAudio(in: linkedRoot, now: Date().addingTimeInterval(90_000))
        }
    }
}
