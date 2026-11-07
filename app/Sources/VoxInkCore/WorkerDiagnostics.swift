import Foundation

/// Only fixed event names cross the logging boundary. Library stderr can contain arbitrary user input.
public final class WorkerDiagnostics: @unchecked Sendable {
    public static let shared = WorkerDiagnostics(directory: URL.libraryDirectory.appendingPathComponent("Logs/VoxInk"))
    enum Event: String, CaseIterable {
        case started, stopped, loading, transcribing, error, warning, other
    }
    private let directory: URL
    private let limit: Int
    private let lock = NSLock()

    init(directory: URL, limit: Int = 1_000_000) {
        self.directory = directory
        self.limit = limit
    }

    func record(stderr: Data) {
        let prefix = String(decoding: stderr.prefix(256), as: UTF8.self)
        let event: Event
        if prefix.hasPrefix("VOXINK_PHASE transcribing") { event = .transcribing }
        else if prefix.hasPrefix("MODEL ") { event = .loading }
        else if prefix.localizedCaseInsensitiveContains("error") { event = .error }
        else if prefix.localizedCaseInsensitiveContains("warning") { event = .warning }
        else { event = .other }
        append(event)
    }

    private func file(_ generation: Int) -> URL {
        directory.appendingPathComponent(generation == 0 ? "worker.log" : "worker.log.\(generation)")
    }

    func append(_ event: Event) {
        lock.lock()
        defer { lock.unlock() }
        let manager = FileManager.default
        let data = Data("\(Int(Date().timeIntervalSince1970)) \(event.rawValue)\n".utf8)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let current = file(0)
            let size = (try? current.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if size + data.count > limit {
                if manager.fileExists(atPath: file(2).path) { try manager.removeItem(at: file(2)) }
                for index in [1, 0] where manager.fileExists(atPath: file(index).path) {
                    try manager.moveItem(at: file(index), to: file(index + 1))
                }
            }
            if !manager.fileExists(atPath: current.path) {
                guard manager.createFile(atPath: current.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { return }
            }
            let handle = try FileHandle(forWritingTo: current)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch { /* Diagnostics must never interrupt dictation. */ }
    }

    public func export() -> String {
        lock.lock()
        defer { lock.unlock() }
        return [2, 1, 0].compactMap { index -> String? in
            guard let handle = try? FileHandle(forReadingFrom: file(index)) else { return nil }
            defer { try? handle.close() }
            guard let data = try? handle.read(upToCount: limit) else { return nil }
            return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
                let parts = line.split(separator: " ")
                guard parts.count == 2, let timestamp = Int(parts[0]),
                      let event = Event(rawValue: String(parts[1])) else { return nil }
                return "\(timestamp) \(event.rawValue)"
            }.joined(separator: "\n")
        }.joined(separator: "\n")
    }
}
