import Foundation

/// Bundled components are the default. Older development installs remain readable.
enum PolishRuntime {
    static func configuration(resources: URL?, root: URL) -> LocalPolishingService.Configuration? {
        let legacy = (try? Data(contentsOf: root.appendingPathComponent("runtime.json")))
            .flatMap { try? JSONDecoder().decode(LocalPolishingService.Configuration.self, from: $0) }
        if let resources {
            let python = resources.appendingPathComponent("PolishRuntime/bin/python3.12")
            let worker = resources.appendingPathComponent("Polish/polish_worker.py")
            if FileManager.default.isExecutableFile(atPath: python.path),
               FileManager.default.fileExists(atPath: worker.path) {
                return .init(python: python.path, worker: worker.path, model: legacy?.model ?? "")
            }
        }
        guard let legacy, FileManager.default.isExecutableFile(atPath: legacy.python) else { return nil }
        return legacy
    }
}
