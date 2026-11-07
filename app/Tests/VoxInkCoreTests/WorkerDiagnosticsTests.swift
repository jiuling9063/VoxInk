import Foundation
import Testing
@testable import VoxInkCore

struct WorkerDiagnosticsTests {
    @Test func stripsFreeTextAndBoundsAllGenerations() throws {
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let logs = WorkerDiagnostics(directory: directory, limit: 80)
        for _ in 0..<100 { logs.record(stderr: Data("error: private transcript and credential".utf8)) }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        #expect(Set(files.map(\.lastPathComponent)) == ["worker.log", "worker.log.1", "worker.log.2"])
        for file in files { #expect(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize! <= 80) }
        #expect(logs.export().contains("error"))
        #expect(!logs.export().contains("private"))
    }
}
