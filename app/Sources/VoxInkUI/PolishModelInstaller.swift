import Darwin
import Foundation

public enum PolishInstallationStage: String, Sendable {
    case preparing = "正在准备本地组件…"
    case downloading = "正在下载并校验模型…"
    case verifying = "正在验证模型运行，请稍候…"
}

public protocol PolishModelInstalling: Sendable {
    func install(_ model: PolishModel) async throws
    func install(_ model: PolishModel, progress: @escaping @Sendable (PolishInstallationStage) async -> Void) async throws
}

extension PolishModelInstalling {
    public func install(_ model: PolishModel, progress: @escaping @Sendable (PolishInstallationStage) async -> Void) async throws {
        try await install(model)
    }
}

public enum PolishInstallationFailure: Error, LocalizedError {
    case componentsMissing, preparationFailed, downloadFailed, verificationFailed, timedOut
    public var errorDescription: String? {
        switch self {
        case .componentsMissing: "App 的本地组件不完整，请重新安装最新版语落后重试。无需手动配置环境。"
        case .preparationFailed: "本地组件未能启动，请重新安装最新版语落后重试。"
        case .downloadFailed: "模型下载未完成，请检查网络和可用磁盘空间后重试，已下载的部分会保留。"
        case .verificationFailed: "模型运行验证未通过，请关闭占用大量内存的应用后重试。"
        case .timedOut: "准备超过等待上限，请稍后重试。"
        }
    }
}

public actor LocalPolishModelInstaller: PolishModelInstalling {
    private let root: URL
    private let resources: URL?
    private var installing = false

    public init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("VoxInk/Polish"),
                resources: URL? = Bundle.main.resourceURL) {
        self.root = root; self.resources = resources
    }

    public func install(_ model: PolishModel) async throws {
        try await install(model, progress: { _ in })
    }

    public func install(_ model: PolishModel, progress: @escaping @Sendable (PolishInstallationStage) async -> Void) async throws {
        guard !installing else { throw PolishInstallationFailure.preparationFailed }
        installing = true
        defer { installing = false }
        guard let config = PolishRuntime.configuration(resources: resources, root: root),
              let script = resources?.appendingPathComponent("Polish/download_polish_model.py"),
              FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: config.worker) else { throw PolishInstallationFailure.componentsMissing }
        try Task.checkCancellation()
        await progress(.preparing)
        try await run(config.python, arguments: ["-I", "-B", "-c",
            "import ssl,mlx.core,mlx_lm,huggingface_hub,tokenizers; assert mlx.core.metal.is_available()"],
                      timeout: .seconds(60), failure: .preparationFailed)
        let directory = model.directory(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pending = directory.appendingPathComponent(".installation-pending")
        try Data().write(to: pending, options: .atomic)
        await progress(.downloading)
        try await run(config.python, arguments: ["-B", "-E", "-s", script.path, model.repository,
                                                model.revision, model.directory(in: root).path],
                      timeout: .seconds(24 * 60 * 60), failure: .downloadFailed)
        await progress(.verifying)
        // Use a fixed, non-user sentence and deny networking for the inference check.
        try await run("/usr/bin/sandbox-exec", arguments: ["-p", "(version 1)(allow default)(deny network*)",
            config.python, "-B", "-E", "-s", config.worker, model.directory(in: root).path],
                      timeout: .seconds(120), failure: .verificationFailed,
                      input: Data("\"明天下午开会。\"".utf8))
        try Task.checkCancellation()
        try FileManager.default.removeItem(at: pending)
    }

    private func run(_ executable: String, arguments: [String], timeout: Duration,
                     failure: PolishInstallationFailure, input: Data? = nil) async throws {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardInput = pipe
        defer {
            try? pipe.fileHandleForWriting.close()
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
        }
        do { try process.run() } catch { throw failure }
        if let input { try pipe.fileHandleForWriting.write(contentsOf: input) }
        try pipe.fileHandleForWriting.close()
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while process.isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw PolishInstallationFailure.timedOut }
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw failure }
    }
}
