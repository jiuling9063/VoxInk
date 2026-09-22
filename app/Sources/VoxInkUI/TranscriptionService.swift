import Foundation
import VoxInkCore

public protocol TranscriptionService: Sendable {
    func prepare() async throws
    func prepare(allowDownload: Bool, progress: @escaping @Sendable (ModelInstallationProgress) -> Void) async throws
    func transcribe(url: URL) async throws -> String
    func transcribe(url: URL, language: SpeechLanguage) async throws -> String
    func cancel() async
}

extension TranscriptionService {
    public func transcribe(url: URL, language: SpeechLanguage) async throws -> String { try await transcribe(url: url) }
    public func prepare(allowDownload: Bool, progress: @escaping @Sendable (ModelInstallationProgress) -> Void) async throws {
        try await prepare()
    }
}

public actor QwenTranscriptionService: TranscriptionService {
    private let client = ResidentWorkerClient()
    private let resources: URL?
    private let installer: ModelInstaller
    private let speechDetector: @Sendable (URL) async throws -> Bool
    public init(resources: URL? = Bundle.main.resourceURL, installer: ModelInstaller = ModelInstaller(),
                speechDetector: @escaping @Sendable (URL) async throws -> Bool = { try await SpeechActivityDetector.assess(url: $0).hasSpeech }) {
        self.resources = resources; self.installer = installer; self.speechDetector = speechDetector
    }

    public func prepare() async throws {
        try await prepare(allowDownload: false, progress: { _ in })
    }

    public func prepare(allowDownload: Bool, progress: @escaping @Sendable (ModelInstallationProgress) -> Void) async throws {
        if allowDownload { await client.shutdown() }
        else if await client.readyInfo != nil { return }
        guard let resources else { throw ServiceError.missingBundle }
        let worker = resources.appendingPathComponent("Worker/voxink-qwen-smoke")
        let manifest = resources.appendingPathComponent("model-manifest.json")
        guard FileManager.default.isExecutableFile(atPath: worker.path),
              FileManager.default.fileExists(atPath: manifest.path) else { throw ServiceError.missingBundle }
        let package = try ModelPackage(manifestURL: manifest)
        let cacheRoot = try await installer.ensureInstalled(package: package, allowDownload: allowDownload, progress: progress)
        try Task.checkCancellation()
        var environment = ProcessInfo.processInfo.environment
        environment["QWEN3_CACHE_DIR"] = cacheRoot.path
        _ = try await client.start(
            executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
            arguments: ["-p", "(version 1)(allow default)(deny network*)", worker.path,
                        "--resident", "--manifest", manifest.path],
            environment: environment
        )
    }

    public func transcribe(url: URL) async throws -> String { try await transcribe(url: url, language: .automatic) }

    public func transcribe(url: URL, language: SpeechLanguage) async throws -> String {
        let hasSignal = try await Task.detached { try AudioFilePreparation.containsSignal(url: url) }.value
        try Task.checkCancellation()
        guard hasSignal else { throw ServiceError.noSpeech }
        let hasSpeech = try await speechDetector(url)
        try Task.checkCancellation()
        guard hasSpeech else { throw ServiceError.noSpeechDetected }
        try await prepare()
        let result = try await client.transcribe(sampleID: UUID().uuidString, audioPath: url.path, language: language)
        guard result.success else { throw ServiceError.noSpeech }
        return result.rawText
    }

    public func cancel() async { await client.shutdown() }
    enum ServiceError: Error, Equatable { case missingBundle, noSpeech, noSpeechDetected }
}
