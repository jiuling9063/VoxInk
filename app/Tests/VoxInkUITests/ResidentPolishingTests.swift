import Foundation
import Testing
@testable import VoxInkUI

struct ResidentPolishingTests {
    private func fixture(idle: Duration = .seconds(120), loadSeconds: Double = 0.05) throws -> (URL, LocalPolishingService) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let scripts = root.appendingPathComponent("Polish")
        try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
        for model in [PolishModel.light, .balanced] {
            let directory = model.directory(in: root)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("[]".utf8).write(to: directory.appendingPathComponent("verified.json"))
        }
        let worker = """
        import os,sys,json,time
        time.sleep(\(loadSeconds))
        print(json.dumps(dict(type='ready',protocol_version=1,pid=os.getpid(),load_ms=50)),flush=True)
        for line in sys.stdin:
            request=json.loads(line)
            if request['text']=='slow': time.sleep(30)
            if request['text']=='exit': sys.exit(1)
            print(json.dumps(dict(request_id=request['request_id'],result=dict(accepted=True,
                reason=str(os.getpid()),text=request['text'],generationSeconds=0.01))),flush=True)
        """
        try Data(worker.utf8).write(to: scripts.appendingPathComponent("polish_worker.py"))
        try JSONEncoder().encode(["python": "/usr/bin/python3", "worker": "/missing", "model": "/missing"])
            .write(to: root.appendingPathComponent("runtime.json"))
        return (root, LocalPolishingService(resources: root, root: root, idleTimeout: idle))
    }

    @Test func prewarmAndRepeatedRequestsReuseSameProcessThenSwitch() async throws {
        let (root, service) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await service.prepare(model: .light)
        let first = try await service.polish("你好", model: .light)
        let second = try await service.polish("再见", model: .light)
        #expect(first.reason == second.reason)
        let third = try await service.polish("切换", model: .balanced)
        #expect(third.reason != first.reason)
        await service.release()
    }

    @Test func prewarmingAndPolishShareLoading() async throws {
        let (root, service) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        async let warm: Void = service.prepare(model: .light)
        let result = try await service.polish("并发", model: .light)
        try await warm
        #expect(result.text == "并发")
        await service.release()
    }

    @Test func requestDeadlineAlsoBoundsAnExistingPrewarm() async throws {
        let (root, service) = try fixture(loadSeconds: 1)
        defer { try? FileManager.default.removeItem(at: root) }
        let warm = Task { try await service.prepare(model: .light) }
        try await Task.sleep(for: .milliseconds(20))
        let start = ContinuousClock.now
        await #expect(throws: LocalPolishingService.Failure.timeout) {
            try await service.polish("测试", model: .light, timeout: .milliseconds(80))
        }
        #expect(start.duration(to: .now) < .seconds(1))
        _ = try? await warm.value
        await service.release()
    }

    @Test func timeoutAndExitAllowFreshProcess() async throws {
        let (root, service) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try await service.prepare(model: .light)
        await #expect(throws: LocalPolishingService.Failure.timeout) {
            try await service.polish("slow", model: .light, timeout: .milliseconds(100))
        }
        await #expect(throws: LocalPolishingService.Failure.failed) { try await service.polish("exit", model: .light) }
        let result = try await service.polish("恢复", model: .light)
        #expect(result.text == "恢复")
        await service.release()
    }

    @Test func cancellationDuringLoadingAndGenerationAllowsRestart() async throws {
        let (root, service) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for prewarm in [false, true] {
            if prewarm { try await service.prepare(model: .light) }
            let task = Task { try await service.polish("slow", model: .light) }
            try await Task.sleep(for: .milliseconds(10))
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
            let result = try await service.polish("恢复", model: .light)
            #expect(result.text == "恢复")
            await service.release()
        }
    }

    @Test func idleReleasesWorker() async throws {
        let (root, service) = try fixture(idle: .milliseconds(80))
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try await service.polish("首次", model: .light)
        try await Task.sleep(for: .milliseconds(250))
        let second = try await service.polish("再次", model: .light)
        #expect(first.reason != second.reason)
        await service.release()
    }
}
