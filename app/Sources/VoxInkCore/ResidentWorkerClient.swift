import Foundation
import Darwin

public struct WorkerReady: Codable, Sendable, Equatable {
    public let type: String
    public let protocolVersion: Int
    public let pid: Int
    public let loadMS: Double
    enum CodingKeys: String, CodingKey {
        case type, pid
        case protocolVersion = "protocol_version", loadMS = "load_ms"
    }
}

public struct WorkerResult: Codable, Sendable, Equatable {
    public let rawText: String
    public let success: Bool
    public let loadMS: Double?
    public let transcribeMS: Double?
    public let peakRSSBytes: Int64?
    enum CodingKeys: String, CodingKey {
        case success
        case rawText = "raw_text", loadMS = "load_ms", transcribeMS = "transcribe_ms"
        case peakRSSBytes = "peak_rss_bytes"
    }
}

public enum ResidentWorkerError: Error, Equatable, Sendable {
    case busy, notReady, cancelled, timeout, exited, invalidProtocol, terminationFailed
    case worker(String)
}

private struct Request: Encodable {
    let request_id: UUID
    let sample_id: String
    let audio_path: String
}
private struct Response: Decodable {
    let request_id: UUID
    let result: WorkerResult?
    let error_code: String?
}

/// One model process and one in-flight request. Cancellation destroys the process;
/// callers explicitly start a fresh generation before submitting more audio.
public actor ResidentWorkerClient {
    public private(set) var readyInfo: WorkerReady?
    public private(set) var lastExitStatus: Int32?
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var input: FileHandle?
    private var output: FileHandle?
    private var generation = UUID()
    private var buffer = Data()
    private var readyWaiter: CheckedContinuation<WorkerReady, Error>?
    private var resultWaiter: CheckedContinuation<Data, Error>?
    private var requestID: UUID?
    private var deadline: Task<Void, Never>?
    private var cleanup: Task<Bool, Never>?
    private var reader: Task<Void, Never>?
    private var deadlineID = UUID()
    private var activeOperation: UUID?

    public init() {}

    public func start(executable: URL, arguments: [String], environment: [String: String]? = nil,
                      standardError: FileHandle = .nullDevice,
                      readyTimeout: Duration = .seconds(120)) async throws -> WorkerReady {
        guard process == nil, cleanup == nil else { throw ResidentWorkerError.busy }
        lastExitStatus = nil
        let child = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        child.environment = environment ?? ProcessInfo.processInfo.environment
        inputPipe = stdin
        outputPipe = stdout
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = standardError
        let token = UUID()
        generation = token
        process = child
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        // Prevent a closed child pipe from delivering SIGPIPE to the host.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        // One bounded stream consumer preserves stdout ordering, including EOF.
        let stream = AsyncThrowingStream<Data, Error>(bufferingPolicy: .bufferingOldest(16)) { continuation in
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if case .dropped = continuation.yield(data) {
                    continuation.finish(throwing: ResidentWorkerError.invalidProtocol)
                }
                if data.isEmpty { continuation.finish() }
            }
        }
        reader = Task { [weak self] in
            do {
                for try await data in stream { await self?.receive(data, generation: token) }
            } catch {
                await self?.streamFailed(token)
            }
        }
        do { try child.run() } catch {
            // An unlaunched Process cannot be waited on.
            process = nil
            await stop(error: error, graceful: false)
            throw error
        }
        let operation = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeOperation = operation
                readyWaiter = continuation
                armTimeout(readyTimeout, token: token)
            }
        } onCancel: {
            Task { await self.cancelOperation(token, operation: operation) }
        }
    }

    public func transcribe(requestID: UUID = UUID(), sampleID: String, audioPath: String,
                           timeout: Duration = .seconds(300)) async throws -> WorkerResult {
        let data = try JSONEncoder().encode(Request(request_id: requestID, sample_id: sampleID, audio_path: audioPath))
        guard data.count < 4096 else { throw ResidentWorkerError.invalidProtocol }
        let response = try await exchange(requestID: requestID, payload: data, timeout: timeout)
        guard let result = try JSONDecoder().decode(Response.self, from: response).result else {
            throw ResidentWorkerError.invalidProtocol
        }
        return result
    }

    /// Exchanges one bounded JSON envelope; the caller decodes its result schema.
    public func exchange(requestID: UUID, payload: Data, timeout: Duration) async throws -> Data {
        guard readyInfo != nil, let input else { throw ResidentWorkerError.notReady }
        guard resultWaiter == nil else { throw ResidentWorkerError.busy }
        guard payload.count <= 32768,
              let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let id = object["request_id"] as? String, UUID(uuidString: id) == requestID else {
            throw ResidentWorkerError.invalidProtocol
        }
        let token = generation
        let operation = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                activeOperation = operation
                resultWaiter = continuation
                self.requestID = requestID
                armTimeout(timeout, token: token)
                do { try input.write(contentsOf: payload + Data([10])) } catch {
                    Task { await self.writeFailed(error, token: token, operation: operation) }
                }
            }
        } onCancel: {
            Task { await self.cancelOperation(token, operation: operation) }
        }
    }

    public func cancel() async { await stop(error: ResidentWorkerError.cancelled, graceful: false) }
    public func shutdown() async { await stop(error: ResidentWorkerError.cancelled, graceful: true) }

    private func cancelOperation(_ token: UUID, operation: UUID) async {
        guard token == generation, operation == activeOperation else { return }
        await cancel()
    }

    private func writeFailed(_ error: Error, token: UUID, operation: UUID) async {
        guard token == generation, operation == activeOperation else { return }
        await stop(error: error, graceful: false)
    }

    private func armTimeout(_ duration: Duration, token: UUID) {
        deadline?.cancel()
        let deadlineToken = UUID()
        deadlineID = deadlineToken
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            await self?.expired(token, deadlineToken: deadlineToken)
        }
    }
    private func expired(_ token: UUID, deadlineToken: UUID) async {
        guard token == generation, deadlineToken == deadlineID else { return }
        await stop(error: ResidentWorkerError.timeout, graceful: false)
    }

    private func streamFailed(_ token: UUID) async {
        guard token == generation else { return }
        await stop(error: ResidentWorkerError.invalidProtocol, graceful: false)
    }

    private func receive(_ data: Data, generation token: UUID) async {
        guard token == generation else { return }
        guard !data.isEmpty else {
            await stop(error: ResidentWorkerError.exited, graceful: false)
            return
        }
        buffer.append(data)
        guard buffer.count <= 4 * 1024 * 1024 else {
            await stop(error: ResidentWorkerError.invalidProtocol, graceful: false)
            return
        }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            do {
                if let waiter = readyWaiter {
                    let ready = try JSONDecoder().decode(WorkerReady.self, from: line)
                    guard ready.type == "ready", ready.protocolVersion == 1,
                          ready.pid > 0, ready.loadMS.isFinite, ready.loadMS >= 0 else { throw ResidentWorkerError.invalidProtocol }
                    readyInfo = ready
                    readyWaiter = nil
                    activeOperation = nil
                    deadline?.cancel()
                    deadlineID = UUID()
                    waiter.resume(returning: ready)
                } else {
                    guard let response = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let id = response["request_id"] as? String, let responseID = UUID(uuidString: id) else {
                        throw ResidentWorkerError.invalidProtocol
                    }
                    guard responseID == requestID, let waiter = resultWaiter else { continue }
                    let result = response["result"] as? [String: Any]
                    let errorCode = response["error_code"] as? String
                    guard (result != nil) != (errorCode != nil) else {
                        throw ResidentWorkerError.invalidProtocol
                    }
                    resultWaiter = nil
                    activeOperation = nil
                    requestID = nil
                    deadline?.cancel()
                    deadlineID = UUID()
                    if let code = errorCode { waiter.resume(throwing: ResidentWorkerError.worker(code)) }
                    else if result != nil { waiter.resume(returning: line) }
                    else { waiter.resume(throwing: ResidentWorkerError.invalidProtocol) }
                }
            } catch {
                await stop(error: ResidentWorkerError.invalidProtocol, graceful: false)
                return
            }
        }
    }

    private func stop(error: Error, graceful: Bool) async {
        if let cleanup { _ = await cleanup.value; return }
        generation = UUID()
        deadline?.cancel()
        deadline = nil
        readyInfo = nil
        requestID = nil
        activeOperation = nil
        buffer.removeAll()
        let ready = readyWaiter
        let result = resultWaiter
        readyWaiter = nil
        resultWaiter = nil
        output?.readabilityHandler = nil
        reader?.cancel()
        reader = nil
        try? input?.close()
        try? output?.close()
        input = nil
        output = nil
        inputPipe = nil
        outputPipe = nil
        let child = process
        process = nil
        let task = Task.detached {
            guard let child else { return true }
            if !graceful, child.isRunning { child.terminate() }
            let limit = ContinuousClock.now.advanced(by: .milliseconds(300))
            while child.isRunning, ContinuousClock.now < limit {
                try? await Task.sleep(for: .milliseconds(10))
            }
            if child.isRunning { _ = kill(child.processIdentifier, SIGKILL) }
            // Foundation reaps children before isRunning becomes false. Its
            // waitUntilExit run-loop wait can hang when called on a Swift task.
            let reapLimit = ContinuousClock.now.advanced(by: .seconds(2))
            while child.isRunning, ContinuousClock.now < reapLimit {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return !child.isRunning
        }
        cleanup = task
        let reaped = await task.value
        if reaped, let child { lastExitStatus = child.terminationStatus }
        // Retain an unresponsive child so start cannot create a second worker.
        if !reaped { process = child }
        cleanup = nil
        let outcome = reaped ? error : ResidentWorkerError.terminationFailed
        ready?.resume(throwing: outcome)
        result?.resume(throwing: outcome)
    }
}
