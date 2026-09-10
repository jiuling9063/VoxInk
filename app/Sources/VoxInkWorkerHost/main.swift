import Foundation
import Darwin
import VoxInkCore

private struct HostSummary: Encodable {
    let pid: Int
    let load_ms: Double
    let results: [WorkerResult]
}

@main struct WorkerHost {
    static func main() async {
        let client = ResidentWorkerClient()
        do {
            var worker: String?
            var workerStderr: String?
            var modelArguments: [String] = []
            var audio: [String] = []
            var args = Array(CommandLine.arguments.dropFirst())[...]
            while let flag = args.popFirst() {
                guard let value = args.popFirst() else { throw CLIError.usage }
                switch flag {
                case "--worker": worker = value
                case "--worker-stderr": workerStderr = value
                case "--model-args-json": modelArguments = try JSONDecoder().decode([String].self, from: Data(value.utf8))
                case "--audio": audio.append(value)
                default: throw CLIError.usage
                }
            }
            guard let worker, worker.hasPrefix("/"), !audio.isEmpty,
                  audio.allSatisfy({ $0.hasPrefix("/") }) else { throw CLIError.usage }
            var diagnostics = FileHandle.nullDevice
            if let workerStderr {
                let fd = open(workerStderr, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
                guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                diagnostics = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            }
            defer { if workerStderr != nil { try? diagnostics.close() } }
            let ready = try await client.start(
                executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                arguments: ["-p", "(version 1)(allow default)(deny network*)", worker] + modelArguments,
                standardError: diagnostics
            )
            var results: [WorkerResult] = []
            for (index, path) in audio.enumerated() {
                results.append(try await client.transcribe(sampleID: String(format: "SMOKE-%03d", index + 1), audioPath: path))
            }
            await client.shutdown()
            let encoded = try JSONEncoder().encode(HostSummary(pid: ready.pid, load_ms: ready.loadMS, results: results))
            FileHandle.standardOutput.write(encoded + Data([10]))
        } catch {
            await client.shutdown()
            let status = await client.lastExitStatus.map(String.init) ?? "unavailable"
            let message = "worker exit status: \(status)\nvoxink-worker-host: \(error)\nUsage: --worker /absolute/binary --model-args-json '[\"--resident\"]' --audio /absolute/audio.wav [--audio /absolute/second.wav] [--worker-stderr /new/diagnostics.log]\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
    }
    private enum CLIError: Error { case usage }
}
