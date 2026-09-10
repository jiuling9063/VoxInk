import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

private actor InstallationStub: TranscriptionService {
    private(set) var requests: [Bool] = []
    let failDownload: Bool
    let invalidManifest: Bool
    init(failDownload: Bool = false, invalidManifest: Bool = false) {
        self.failDownload = failDownload; self.invalidManifest = invalidManifest
    }
    func prepare() async throws {}
    func prepare(allowDownload: Bool, progress: @escaping @Sendable (ModelInstallationProgress) -> Void) async throws {
        requests.append(allowDownload)
        if invalidManifest { throw ModelInstallationError.invalidManifest }
        guard allowDownload else { throw ModelInstallationError.downloadRequired }
        progress(.init(stage: .downloading, completedBytes: 5, totalBytes: 10))
        if failDownload { throw URLError(.networkConnectionLost) }
    }
    func transcribe(url: URL) async throws -> String { "测试" }
    func cancel() async {}
}

private actor DelayedInstallation: TranscriptionService {
    private(set) var started = false
    private var continuation: CheckedContinuation<Void, Never>?
    func prepare() async throws {}
    func prepare(allowDownload: Bool, progress: @escaping @Sendable (ModelInstallationProgress) -> Void) async throws {
        started = true
        await withCheckedContinuation { continuation = $0 }
        progress(.init(stage: .downloading, completedBytes: 10, totalBytes: 10))
    }
    func release() { continuation?.resume(); continuation = nil }
    func transcribe(url: URL) async throws -> String { "测试" }
    func cancel() async {}
}

@MainActor struct ModelSetupTests {
    private func waitForCompletion(_ store: AppStore) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !store.canStart && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(store.canStart)
    }

    @Test func startupDoesNotDownloadUntilUserChoosesInstall() async throws {
        let service = InstallationStub()
        let store = AppStore(service: service, preferences: nil)
        store.warmUp()
        try await waitForCompletion(store)
        #expect(store.modelState == .needsDownload)
        #expect(store.recovery == .installModel)
        #expect(await service.requests == [false])
        store.installModel()
        try await waitForCompletion(store)
        #expect(await service.requests == [false, true])
        #expect(store.modelState == .ready)
        #expect(store.modelInstallationProgress == nil)
        #expect(store.recovery == nil)
    }

    @Test func networkFailureOffersResumeWithoutClaimingReady() async throws {
        let store = AppStore(service: InstallationStub(failDownload: true), preferences: nil)
        store.installModel()
        try await waitForCompletion(store)
        #expect(store.modelState == .needsDownload)
        #expect(store.recovery == .installModel)
        #expect(store.phase == .failed)
        #expect(store.status.contains("继续"))
        #expect(store.modelInstallationProgress == nil)
    }

    @Test func invalidManifestDoesNotOfferDownloadAsARepair() async throws {
        let store = AppStore(service: InstallationStub(invalidManifest: true), preferences: nil)
        store.warmUp()
        try await waitForCompletion(store)
        #expect(store.modelState == .failed)
        #expect(store.recovery == .checkInstallation)
        #expect(store.status.contains("重新安装"))
    }

    @Test func cancellationWaitsForInstallerAndDiscardsLateProgress() async throws {
        let service = DelayedInstallation()
        let store = AppStore(service: service, preferences: nil)
        store.installModel()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await !service.started && ContinuousClock.now < deadline { await Task.yield() }
        #expect(await service.started)
        let cancellation = Task { await store.cancel() }
        while store.phase != .cancelling && ContinuousClock.now < deadline { await Task.yield() }
        #expect(store.phase == .cancelling)
        #expect(!store.canStart)
        await service.release()
        await cancellation.value
        #expect(store.modelState == .notLoaded)
        #expect(store.phase == .ready)
        #expect(store.modelInstallationProgress == nil)
    }
}
