import Darwin
import Foundation

public struct PolishResult: Codable, Sendable {
    public let accepted: Bool
    public let reason: String
    public let text: String
    public init(accepted: Bool, reason: String, text: String) {
        self.accepted = accepted; self.reason = reason; self.text = text
    }
}

public protocol PolishingService: Sendable {
    func polish(_ text: String) async throws -> PolishResult
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
            case .unavailable: "本地润色模型或运行环境尚未安装，原文已保留。"
            case .tooLong: "单次润色最多支持 2000 字，原文已保留。"
            case .timeout: "润色超过 30 秒，已停止并保留原文。"
            case .failed: "本地润色失败，原文已保留。"
            }
        }
    }

    public init() {}

    public func polish(_ text: String) async throws -> PolishResult {
        guard text.count <= 2000 else { throw Failure.tooLong }
        let location = URL.applicationSupportDirectory.appendingPathComponent("VoxInk/Polish/runtime.json")
        guard let data = try? Data(contentsOf: location),
              let config = try? JSONDecoder().decode(Configuration.self, from: data),
              FileManager.default.isExecutableFile(atPath: config.python),
              FileManager.default.fileExists(atPath: config.worker) else { throw Failure.unavailable }
        try Task.checkCancellation()
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", "(version 1)(allow default)(deny network*)", config.python, config.worker, config.model]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
        }
        try process.run()
        try input.fileHandleForWriting.write(contentsOf: JSONEncoder().encode(text))
        try input.fileHandleForWriting.close()
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while process.isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw Failure.timeout }
            try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0,
              let resultData = try output.fileHandleForReading.readToEnd(),
              let result = try? JSONDecoder().decode(PolishResult.self, from: resultData),
              !result.text.isEmpty else { throw Failure.failed }
        return result
    }
}
