import Foundation
import Testing
@testable import VoxInkUI

struct PolishRuntimeTests {
    private func fixture() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resources = root.appendingPathComponent("VoxInk.app/Contents/Resources")
        let bin = resources.appendingPathComponent("PolishRuntime/bin")
        let scripts = resources.appendingPathComponent("Polish")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: bin.appendingPathComponent("python3.12").path)
        try Data().write(to: scripts.appendingPathComponent("polish_worker.py"))
        return (root, resources)
    }

    @Test func freshInstallFindsBundledRuntimeWithoutConfiguration() throws {
        let (root, resources) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = try #require(PolishRuntime.configuration(resources: resources, root: root))
        #expect(configuration.python.hasPrefix(resources.path))
        #expect(configuration.model.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("runtime.json").path))
    }

    @Test func bundleWinsOverStaleLegacyInterpreterAndRemainsRelocatable() throws {
        let (root, resources) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = ["python": "/missing/developer/python", "worker": "/missing/worker", "model": "/old/model"]
        try JSONEncoder().encode(old).write(to: root.appendingPathComponent("runtime.json"))
        let moved = root.appendingPathComponent("Moved Resources")
        try FileManager.default.moveItem(at: resources, to: moved)
        let configuration = try #require(PolishRuntime.configuration(resources: moved, root: root))
        #expect(configuration.python.hasPrefix(moved.path))
        #expect(configuration.worker.hasPrefix(moved.path))
        #expect(configuration.model == "/old/model")
    }

    @Test func modelIsUnavailableUntilRuntimeVerificationCompletes() throws {
        let (root, resources) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = PolishModel.light.directory(in: root)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: model.appendingPathComponent("verified.json"))
        let pending = model.appendingPathComponent(".installation-pending")
        try Data().write(to: pending)
        #expect(LocalPolishingService.installedModels(root: root, resources: resources).isEmpty)
        try FileManager.default.removeItem(at: pending)
        #expect(LocalPolishingService.installedModels(root: root, resources: resources) == [.light])
    }

    @Test func incompleteAppFailsWithRepairInstruction() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let installer = LocalPolishModelInstaller(root: root, resources: root)
        await #expect(throws: PolishInstallationFailure.componentsMissing) { try await installer.install(.light) }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
