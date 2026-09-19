import Darwin
import Foundation

public protocol PolishModelInstalling: Sendable {
    func install(_ model: PolishModel) async throws
}

public actor LocalPolishModelInstaller: PolishModelInstalling {
    private let root: URL
    private let resources: URL?

    public init(root: URL = URL.applicationSupportDirectory.appendingPathComponent("VoxInk/Polish"),
                resources: URL? = Bundle.main.resourceURL) {
        self.root = root; self.resources = resources
    }

    public func install(_ model: PolishModel) async throws {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("runtime.json")),
              let config = try? JSONDecoder().decode(LocalPolishingService.Configuration.self, from: data),
              FileManager.default.isExecutableFile(atPath: config.python),
              let script = resources?.appendingPathComponent("Polish/download_polish_model.py"),
              FileManager.default.fileExists(atPath: script.path) else { throw LocalPolishingService.Failure.unavailable }
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.python)
        process.arguments = ["-B", script.path, model.repository, model.revision, model.directory(in: root).path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        defer {
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
        }
        try process.run()
        while process.isRunning {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else { throw LocalPolishingService.Failure.failed }
    }
}
