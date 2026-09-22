import Foundation
import Darwin

@MainActor private final class DownloadRequest {
    private var continuation: CheckedContinuation<String, Error>?
    private var connection: NSXPCConnection?
    private var timeout: Task<Void, Never>?

    func run(to destination: FileHandle) async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                let connection = NSXPCConnection(serviceName: "local.voxink.sandbox-probe.download")
                self.connection = connection
                connection.remoteObjectInterface = NSXPCInterface(with: ProbeDownloadService.self)
                connection.invalidationHandler = { [weak self] in
                    Task { @MainActor in self?.finish(.failure(CocoaError(.xpcConnectionInvalid))) }
                }
                connection.interruptionHandler = { [weak self] in
                    Task { @MainActor in self?.finish(.failure(CocoaError(.xpcConnectionInterrupted))) }
                }
                connection.resume()
                timeout = Task {
                    do { try await Task.sleep(for: .seconds(35)) } catch { return }
                    finish(.failure(URLError(.timedOut)))
                }
                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] error in
                    Task { @MainActor in self?.finish(.failure(error)) }
                }) as? ProbeDownloadService else {
                    finish(.failure(CocoaError(.xpcConnectionInvalid))); return
                }
                proxy.downloadConfiguration(to: destination) { [weak self] message, error in
                    Task { @MainActor in
                        if let error { self?.finish(.failure(error)) }
                        else if let message { self?.finish(.success(message)) }
                        else { self?.finish(.failure(CocoaError(.coderInvalidValue))) }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in self.finish(.failure(CancellationError())) }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel(); timeout = nil
        connection?.invalidate(); connection = nil
        continuation.resume(with: result)
    }
}

extension Probe {
    private var downloadedConfig: URL {
        URL.applicationSupportDirectory.appendingPathComponent("VoxInkSandboxProbe/download-fixture/config.json")
    }

    func cachedDownloadTest() {
        guard !busy else { return }
        do {
            let data = try Data(contentsOf: downloadedConfig)
            try DownloadFixture.load().verify(data)
            record("PASS persisted config: \(data.count) bytes, pinned SHA256 matches; no network request")
        } catch { record("FAIL persisted config: \(error.localizedDescription)") }
    }

    func networkTests() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            record("MAIN pid=\(ProcessInfo.processInfo.processIdentifier) sandbox=\(entitlementEnabled("com.apple.security.app-sandbox")) network.client=\(entitlementEnabled("com.apple.security.network.client"))")
            let before = networkConnectError()
            record("MAIN before XPC: loopback connect errno=\(before) (EPERM=1, EACCES=13)")
            do {
                guard entitlementEnabled("com.apple.security.app-sandbox"),
                      !entitlementEnabled("com.apple.security.network.client"), [EPERM, EACCES].contains(before) else {
                    throw CocoaError(.executableNotLoadable)
                }
                let destination = downloadedConfig
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".partial")
                let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
                guard descriptor >= 0 else { throw POSIXError(.EIO) }
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
                let status = try await DownloadRequest().run(to: handle)
                try handle.close()
                let data = try Data(contentsOf: temporary)
                try DownloadFixture.load().verify(data)
                try data.write(to: destination, options: .atomic)
                record("PASS \(status); received through write-only file descriptor, verified again by main")
                let after = networkConnectError()
                record("MAIN after XPC: loopback connect errno=\(after)")
                guard [EPERM, EACCES].contains(after) else { throw CocoaError(.executableNotLoadable) }
                if let resources = Bundle.main.resourceURL {
                    await child("Inherited Python network denial", executable: resources.appendingPathComponent("PolishRuntime/bin/python3.12"),
                                arguments: ["-B", "-E", "-s", "-c", "import socket,errno; s=socket.socket(); s.settimeout(3); r=s.connect_ex(('127.0.0.1',9)); s.close(); print('CHILD connect errno='+str(r)); assert r in (errno.EPERM,errno.EACCES)"])
                }
                record("Saved pinned config in probe container; quit, reopen and use 读取已下载样例 to verify persistence")
            } catch { record("FAIL download isolation: \(error.localizedDescription)") }
        }
    }
}
