import Darwin
import Foundation

public struct ResidentRequest: Codable, Sendable {
    public let request_id: String
    public let sample_id: String
    public let audio_path: String

    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 65536 else { throw ProtocolError.invalidRequest }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard [value.request_id, value.sample_id].allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 128
        }), value.audio_path.hasPrefix("/"), !value.audio_path.contains("\0"),
        !value.audio_path.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else {
            throw ProtocolError.invalidRequest
        }
        return value
    }
}

public enum ProtocolError: Error { case invalidRequest, duplicateRequest }

public struct ResidentReady: Encodable, Sendable {
    public let type = "ready"
    public let protocol_version = 1
    public let pid = getpid()
    public let load_ms: Int
    public init(loadMilliseconds: Int) { load_ms = loadMilliseconds }
}

/// Only the condition-protected queue crosses threads; decoding and seen IDs stay on the consumer.
public final class ResidentInput: @unchecked Sendable {
    private let condition = NSCondition()
    private var lines: [Data] = []
    private var seen: Set<String> = []

    public init() {
        DispatchQueue.global(qos: .utility).async { [self] in
            var buffer = Data()
            do {
                var bytes = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = Darwin.read(STDIN_FILENO, &bytes, bytes.count)
                    if count < 0 {
                        if errno == EINTR { continue }
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    if count == 0 { break }
                    buffer.append(contentsOf: bytes.prefix(count))
                    while let newline = buffer.firstIndex(of: 10) {
                        let line = Data(buffer[..<newline])
                        guard line.count <= 65536 else { _exit(65) }
                        buffer.removeSubrange(...newline)
                        condition.lock()
                        guard lines.count < 16 else { condition.unlock(); _exit(65) }
                        lines.append(line)
                        condition.signal()
                        condition.unlock()
                    }
                    guard buffer.count <= 65536 else { _exit(65) }
                }
                // No owner remains to consume results. Bypass engine atexit hooks so inference cannot finish during cleanup.
                _exit(0)
            } catch { _exit(74) }
        }
    }

    public func next() throws -> ResidentRequest {
        condition.lock()
        while lines.isEmpty { condition.wait() }
        let line = lines.removeFirst()
        condition.unlock()
        let request = try ResidentRequest.decode(line)
        guard seen.insert(request.request_id).inserted else { throw ProtocolError.duplicateRequest }
        return request
    }
}
