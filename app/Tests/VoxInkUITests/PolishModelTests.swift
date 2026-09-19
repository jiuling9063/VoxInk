import Foundation
import Testing
@testable import VoxInkUI

private actor FixtureInstaller: PolishModelInstalling {
    let shouldFail: Bool
    let delayed: Bool
    private(set) var calls: [PolishModel] = []
    init(shouldFail: Bool = false, delayed: Bool = false) {
        self.shouldFail = shouldFail; self.delayed = delayed
    }
    func install(_ model: PolishModel) async throws {
        calls.append(model)
        if delayed { try await Task.sleep(for: .seconds(30)) }
        if shouldFail { throw LocalPolishingService.Failure.failed }
    }
}

@MainActor struct PolishModelTests {
    @Test func bundledWorkerDoesNotWriteBytecodeIntoSignedResources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Resources")
        let scripts = resources.appendingPathComponent("Polish")
        let model = PolishModel.light.directory(in: root)
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: model.appendingPathComponent("verified.json"))
        try Data("value = 'ok'".utf8).write(to: scripts.appendingPathComponent("fixture.py"))
        let worker = """
        import json,sys,fixture,os
        print(json.dumps(dict(type='ready', protocol_version=1, pid=os.getpid(), load_ms=0)), flush=True)
        for line in sys.stdin:
            request = json.loads(line)
            print(json.dumps(dict(request_id=request['request_id'], result=dict(accepted=True, reason=fixture.value,
                                  text=str(sys.dont_write_bytecode)))), flush=True)
        """
        try Data(worker.utf8).write(to: scripts.appendingPathComponent("polish_worker.py"))
        let config = ["python": "/usr/bin/python3", "worker": "/missing-worker", "model": "/missing-model"]
        try JSONEncoder().encode(config).write(to: root.appendingPathComponent("runtime.json"))
        let service = LocalPolishingService(resources: resources, root: root)
        let result = try await service.polish("测试", model: .light)
        #expect(result.text == "True")
        #expect(!FileManager.default.fileExists(atPath: scripts.appendingPathComponent("__pycache__").path))
        await service.release()
    }

    private func waitForInstall(_ store: AppStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while store.isInstallingPolishModel, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!store.isInstallingPolishModel)
    }

    @Test func installationDoesNotEnablePolishAndRefreshesInventory() async throws {
        let installer = FixtureInstaller()
        let store = AppStore(polishInstaller: installer, polishInventory: { [.light] }, preferences: nil)
        store.setPolishModel(.light)
        store.installSelectedPolishModel()
        store.setPolishModel(.quality)
        store.installSelectedPolishModel()
        try await waitForInstall(store)
        #expect(await installer.calls == [.light])
        #expect(store.polishModel == .light)
        #expect(store.installedPolishModels == [.light])
        #expect(!store.polishingEnabled)
        #expect(store.polishInstallationMessage.contains("安装完成"))
    }

    @Test func failedInstallIsNotReportedReady() async throws {
        let store = AppStore(polishInstaller: FixtureInstaller(shouldFail: true), polishInventory: { [] }, preferences: nil)
        store.installSelectedPolishModel()
        try await waitForInstall(store)
        #expect(store.installedPolishModels.isEmpty)
        #expect(store.polishInstallationMessage.contains("安装未完成"))
    }

    @Test func cancelledInstallUnlocksSelection() async throws {
        let store = AppStore(polishInstaller: FixtureInstaller(delayed: true), polishInventory: { [] }, preferences: nil)
        store.installSelectedPolishModel()
        store.cancelPolishInstallation()
        try await waitForInstall(store)
        #expect(store.polishInstallationMessage.contains("已取消"))
        store.setPolishModel(.quality)
        #expect(store.polishModel == .quality)
        #expect(store.installedPolishModels.isEmpty)
    }

    @Test func choicePersistsAndUnknownChoiceUsesBalanced() throws {
        let name = "polish-model-" + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let store = AppStore(preferences: preferences)
        #expect(store.polishModel == .balanced)
        #expect(!store.polishingEnabled)
        store.setPolishModel(.light)
        #expect(AppStore(preferences: preferences).polishModel == .light)
        #expect(!store.polishingEnabled)
        preferences.set("unknown", forKey: "polishModel")
        #expect(AppStore(preferences: preferences).polishModel == .balanced)
    }

    @Test func eachTierHasSeparatePinnedLocation() {
        let root = URL(fileURLWithPath: "/fixture")
        #expect(PolishModel.allCases.count == 4)
        #expect(Set(PolishModel.allCases.map { $0.directory(in: root) }).count == 4)
        #expect(PolishModel.allCases.allSatisfy { $0.revision.count == 40 })
    }

    @Test func legacyModelOnlyServesMatchingBalancedRevision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("legacy").appendingPathComponent(PolishModel.balanced.revision)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: legacy.appendingPathComponent("verified.json"))
        let config = LocalPolishingService.Configuration(python: "/python", worker: "/worker", model: legacy.path)
        #expect(LocalPolishingService.modelDirectory(.balanced, root: root, config: config)?.path == legacy.path)
        #expect(LocalPolishingService.modelDirectory(.light, root: root, config: config) == nil)
        try FileManager.default.removeItem(at: legacy.appendingPathComponent("verified.json"))
        #expect(LocalPolishingService.modelDirectory(.balanced, root: root, config: config) == nil)
    }
}
