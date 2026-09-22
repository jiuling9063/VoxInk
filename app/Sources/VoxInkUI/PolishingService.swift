import Darwin
import Foundation
import VoxInkCore

public struct PolishResult: Codable, Sendable {
    public let accepted: Bool
    public let reason: String
    public let text: String
    public let generationSeconds: Double?
    public init(accepted: Bool, reason: String, text: String, generationSeconds: Double? = nil) {
        self.accepted = accepted; self.reason = reason; self.text = text; self.generationSeconds = generationSeconds
    }
}

public protocol PolishingService: Sendable {
    func polish(_ text: String, model: PolishModel) async throws -> PolishResult
    func polish(_ text: String, model: PolishModel, timeout: Duration) async throws -> PolishResult
    func polish(_ text: String, model: PolishModel, timeout: Duration, language: SpeechLanguage) async throws -> PolishResult
    func prepare(model: PolishModel) async throws
    func release() async
}

extension PolishingService {
    public func polish(_ text: String, model: PolishModel, timeout: Duration, language: SpeechLanguage) async throws -> PolishResult {
        try await polish(text, model: model, timeout: timeout)
    }
    public func polish(_ text: String, model: PolishModel, timeout: Duration) async throws -> PolishResult {
        try await polish(text, model: model)
    }
    public func prepare(model: PolishModel) async throws {}
    public func release() async {}
}

public actor LocalPolishingService: PolishingService {
    struct Configuration: Decodable {
        let python: String
        let worker: String
        let model: String
    }

    public enum Failure: Error, LocalizedError {
        case unavailable, tooLong, timeout, failed
        public var errorDescription: String? {
            switch self {
            case .unavailable: L("本地润色模型或运行环境尚未安装，原文已保留。")
            case .tooLong: L("单次润色最多支持 2000 字，原文已保留。")
            case .timeout: L("润色超过等待上限，已停止并保留原文。")
            case .failed: L("本地润色失败，原文已保留。")
            }
        }
    }

    private let bundledWorker: URL?
    private let resources: URL?
    private let root: URL
    private let client = ResidentWorkerClient()
    private let idleTimeout: Duration
    private var loadedModel: PolishModel?
    private var loading: (id: UUID, model: PolishModel, task: Task<Void, Error>)?
    private var idleTask: Task<Void, Never>?
    private var activeRequest: UUID?
    private var expiredRequest: UUID?
    private var epoch = UUID()

    public init(resources: URL? = Bundle.main.resourceURL,
                root: URL = URL.applicationSupportDirectory.appendingPathComponent("VoxInk/Polish"),
                idleTimeout: Duration = .seconds(120)) {
        self.resources = resources
        bundledWorker = resources?.appendingPathComponent("Polish/polish_worker.py")
        self.root = root; self.idleTimeout = idleTimeout
    }

    static func modelDirectory(_ model: PolishModel, root: URL, config: Configuration) -> URL? {
        let preferred = model.directory(in: root)
        let legacy = URL(fileURLWithPath: config.model)
        let candidates = [preferred] + (legacy.lastPathComponent == model.revision ? [legacy] : [])
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("verified.json").path) &&
            !FileManager.default.fileExists(atPath: $0.appendingPathComponent(".installation-pending").path)
        }
    }

    public static func installedModels(root: URL = URL.applicationSupportDirectory.appendingPathComponent("VoxInk/Polish"),
                                       resources: URL? = Bundle.main.resourceURL) -> Set<PolishModel> {
        guard let config = PolishRuntime.configuration(resources: resources, root: root) else { return [] }
        return Set(PolishModel.allCases.filter { modelDirectory($0, root: root, config: config) != nil })
    }

    public func prepare(model: PolishModel) async throws {
        guard activeRequest == nil else { return }
        try await ensureReady(model: model, timeout: .seconds(30))
        scheduleIdleRelease()
    }

    private func ensureReady(model: PolishModel, timeout: Duration) async throws {
        idleTask?.cancel()
        if let pending = loading {
            try await pending.task.value
            try Task.checkCancellation()
            guard epoch == pending.id else { throw Failure.failed }
            loadedModel = pending.model
            loading = nil
        }
        if loadedModel == model, await client.readyInfo != nil { return }
        guard let config = PolishRuntime.configuration(resources: resources, root: root),
              let directory = Self.modelDirectory(model, root: root, config: config) else { throw Failure.unavailable }
        let worker = bundledWorker.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0.path : nil } ?? config.worker
        guard FileManager.default.fileExists(atPath: worker) else { throw Failure.unavailable }
        let id = UUID(); epoch = id
        let task = Task { [client] in
            await client.shutdown()
            try Task.checkCancellation()
            _ = try await client.start(executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                arguments: ["-p", "(version 1)(allow default)(deny network*)", config.python, "-B", "-E", "-s", worker,
                            directory.path, "--resident"], readyTimeout: timeout)
        }
        loading = (id, model, task)
        do {
            try await task.value
            try Task.checkCancellation()
            guard epoch == id else { throw Failure.failed }
            loadedModel = model
            loading = nil
        } catch {
            if epoch == id { loading = nil; loadedModel = nil }
            throw error
        }
    }

    public func polish(_ text: String, model: PolishModel = .balanced) async throws -> PolishResult {
        try await polish(text, model: model, timeout: .seconds(30))
    }

    public func polish(_ text: String, model: PolishModel, timeout: Duration) async throws -> PolishResult {
        try await polish(text, model: model, timeout: timeout, language: .mandarin)
    }

    public func polish(_ text: String, model: PolishModel, timeout: Duration, language: SpeechLanguage) async throws -> PolishResult {
        guard text.count <= 2000 else { throw Failure.tooLong }
        guard activeRequest == nil else { throw Failure.failed }
        try Task.checkCancellation()
        let id = UUID(); activeRequest = id
        expiredRequest = nil
        let deadline = ContinuousClock.now.advanced(by: timeout)
        let deadlineTask = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            await self?.expireRequest(id)
        }
        defer {
            deadlineTask.cancel()
            if activeRequest == id { activeRequest = nil; scheduleIdleRelease() }
        }
        do {
            return try await withTaskCancellationHandler {
                try await ensureReady(model: model, timeout: timeout)
                try Task.checkCancellation()
                let remaining = ContinuousClock.now.duration(to: deadline)
                guard remaining > .zero else { throw Failure.timeout }
                struct Request: Encodable { let request_id: UUID; let text: String; let max_tokens: Int; let language: SpeechLanguage }
                struct Response: Decodable { let result: PolishResult }
                let request = Request(request_id: id, text: text, max_tokens: min(4096, max(128, text.utf8.count + 64)), language: language)
                let response = try await client.exchange(requestID: id, payload: JSONEncoder().encode(request), timeout: remaining)
                try Task.checkCancellation()
                let result = try JSONDecoder().decode(Response.self, from: response).result
                guard !result.text.isEmpty else { throw Failure.failed }
                return result
            } onCancel: {
                Task { await self.cancelRequest(id) }
            }
        } catch {
            await release()
            if Task.isCancelled { throw CancellationError() }
            if expiredRequest == id { throw Failure.timeout }
            if error as? ResidentWorkerError == .timeout { throw Failure.timeout }
            if let failure = error as? Failure { throw failure }
            throw Failure.failed
        }
    }

    private func cancelRequest(_ id: UUID) async {
        guard activeRequest == id else { return }
        await release()
    }

    private func expireRequest(_ id: UUID) async {
        guard activeRequest == id else { return }
        expiredRequest = id
        await release()
    }

    public func release() async {
        epoch = UUID()
        idleTask?.cancel(); idleTask = nil
        let task = loading?.task
        loading = nil; loadedModel = nil
        task?.cancel()
        await client.cancel()
        _ = try? await task?.value
    }

    private func scheduleIdleRelease() {
        idleTask?.cancel()
        let token = epoch
        idleTask = Task { [weak self, idleTimeout] in
            do { try await Task.sleep(for: idleTimeout) } catch { return }
            await self?.releaseIfIdle(token)
        }
    }

    private func releaseIfIdle(_ token: UUID) async {
        guard token == epoch, activeRequest == nil, loading == nil else { return }
        await release()
    }
}
