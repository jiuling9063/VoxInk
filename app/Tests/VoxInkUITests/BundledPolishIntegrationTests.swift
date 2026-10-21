import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

struct BundledPolishIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOXINK_TEST_STYLE_RESOURCES"] != nil))
    func installedModelUsesBothStylesAndClientGuard() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["VOXINK_TEST_STYLE_RESOURCES"])
        let resources = URL(fileURLWithPath: path)
        let installed = LocalPolishingService.installedModels(resources: resources)
        let model = try #require(installed.sorted { $0.rank < $1.rank }.first)
        let service = LocalPolishingService(resources: resources)
        do {
            for style in PolishStyle.allCases {
                let source = "我们，嗯，明天讨论这个方案，下午三点。"
                let result = try await service.polish(source, model: model, timeout: .seconds(60), language: .mandarin, style: style)
                #expect(!result.text.isEmpty)
                #expect(result.accepted ? PolishTextSafety.accepts(source: source, output: result.text, language: .mandarin, style: style) : result.text == source)
                print("Local style \(style.rawValue): accepted=\(result.accepted), seconds=\(result.generationSeconds ?? 0), text=\(result.text)")
            }
            await service.release()
        } catch { await service.release(); throw error }
    }

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
