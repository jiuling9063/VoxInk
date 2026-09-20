import Foundation
import Testing
@testable import VoxInkUI

struct BundledPolishIntegrationTests {
    // Explicit opt-in: this downloads the real light model into a new disposable root.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOXINK_TEST_BUNDLED_RESOURCES"] != nil))
    func freshUserDownloadsAndRunsWithoutRuntimeConfiguration() async throws {
        let environment = ProcessInfo.processInfo.environment
        let resources = URL(fileURLWithPath: try #require(environment["VOXINK_TEST_BUNDLED_RESOURCES"]))
        let root = URL(fileURLWithPath: try #require(environment["VOXINK_TEST_FRESH_ROOT"]))
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(LocalPolishingService.installedModels(root: root, resources: resources).isEmpty)
        let installer = LocalPolishModelInstaller(root: root, resources: resources)
        try await installer.install(.light) { stage in print(stage.rawValue) }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("runtime.json").path))
        #expect(LocalPolishingService.installedModels(root: root, resources: resources) == [.light])
        let service = LocalPolishingService(resources: resources, root: root)
        do {
            let result = try await service.polish("明天下午开会。", model: .light, timeout: .seconds(120))
            #expect(!result.text.isEmpty)
            await service.release()
        } catch {
            await service.release()
            throw error
        }
    }
}
