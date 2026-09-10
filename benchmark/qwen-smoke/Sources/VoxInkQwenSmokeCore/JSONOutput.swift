import Darwin
import Foundation

/// Reserve stdout for the CLI contract; dependency print statements become diagnostics.
public final class JSONOutput: Sendable {
    private let destination: FileHandle

    public init() throws {
        let descriptor = dup(STDOUT_FILENO)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            close(descriptor)
            throw POSIXError(code)
        }
        destination = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    public func write<T: Encodable>(_ value: T) throws {
        let line = try JSONLineEncoder.encode(value)
        try destination.write(contentsOf: Data((line + "\n").utf8))
    }
}
