import Foundation

private final class TransferState: @unchecked Sendable {
    private let lock = NSLock()
    private var startedCount = 0
    private var stoppedCount = 0
    private var cancellationCount = 0
    var counts: (started: Int, stopped: Int, cancelled: Int) {
        lock.withLock { (startedCount, stoppedCount, cancellationCount) }
    }
    func started() { lock.withLock { startedCount += 1 } }
    func stopped() { lock.withLock { stoppedCount += 1 } }
    func cancelled() { lock.withLock { cancellationCount += 1 } }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    static let state = TransferState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.started()
        let mode = request.url!.deletingLastPathComponent().lastPathComponent
        if mode == "offline" || mode == "timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(mode == "offline" ? .notConnectedToInternet : .timedOut))
            return
        }
        let code = mode == "503" ? 503 : (mode == "404" ? 404 : 200)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code,
                            httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        if mode == "pending" { return }
        let body = mode == "corrupt" ? "abd" : mode == "truncated" ? "ab" : mode == "oversized" ? "abcd" : "abc"
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { Self.state.stopped() }
}

@main struct DownloadTransferTests {
    static func fixture(_ mode: String) -> DownloadFixture {
        .init(download_url: URL(string: "https://huggingface.co/fixture/\(mode)/config.json")!, size_bytes: 3,
              sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    static func transfer() -> DownloadTransfer {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        return DownloadTransfer(configuration: configuration)
    }

    static func waitUntil(_ predicate: @Sendable () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        precondition(predicate(), "timed out waiting for test event")
    }

    static func main() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent("voxink-transfer-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("output")
        let oldData = Data("existing verified data".utf8)
        var checks = 0
        for mode in ["503", "404", "corrupt", "truncated", "oversized", "offline", "timeout"] {
            try oldData.write(to: file)
            let handle = try FileHandle(forWritingTo: file)
            do {
                _ = try await transfer().write(fixture(mode), to: handle)
                preconditionFailure("failed transfer reported success: \(mode)")
            } catch {
                let expectedCode: Int
                switch mode {
                case "503", "404": expectedCode = URLError.badServerResponse.rawValue
                case "oversized": expectedCode = URLError.dataLengthExceedsMaximum.rawValue
                case "offline": expectedCode = URLError.notConnectedToInternet.rawValue
                case "timeout": expectedCode = URLError.timedOut.rawValue
                default: expectedCode = CocoaError.fileReadCorruptFile.rawValue
                }
                precondition((error as NSError).code == expectedCode, "unexpected error for \(mode): \(error)")
            }
            try handle.close()
            let unchanged = try Data(contentsOf: file)
            precondition(unchanged == oldData, "failed transfer changed destination")
            checks += 1
        }
        try Data().write(to: file)
        let handle = try FileHandle(forWritingTo: file)
        let previous = FixtureProtocol.state.counts
        let pending = Task { try await transfer().write(fixture("pending"), to: handle) }
        try await waitUntil { FixtureProtocol.state.counts.started > previous.started }
        pending.cancel()
        do { _ = try await pending.value; preconditionFailure("cancelled transfer succeeded") }
        catch { precondition(error is CancellationError || (error as NSError).code == URLError.cancelled.rawValue) }
        try await waitUntil { FixtureProtocol.state.counts.stopped > previous.stopped }
        let cancelledData = try Data(contentsOf: file)
        precondition(cancelledData.isEmpty, "cancelled transfer wrote bytes")
        checks += 1
        let count = try await transfer().write(fixture("success"), to: handle)
        try handle.close()
        let recoveredData = try Data(contentsOf: file)
        precondition(count == 3 && recoveredData == Data("abc".utf8), "retry did not recover")
        checks += 1

        let readOnly = try FileHandle(forReadingFrom: file)
        do { _ = try await transfer().write(fixture("success"), to: readOnly); preconditionFailure("read-only descriptor accepted") }
        catch {
            let preservedData = try Data(contentsOf: file)
            precondition(preservedData == Data("abc".utf8))
        }
        try readOnly.close()
        checks += 1

        let job = DownloadJob()
        let status = TransferState()
        precondition(job.start {
            status.started()
            do { try await Task.sleep(for: .seconds(30)) }
            catch is CancellationError { status.cancelled() }
            catch { preconditionFailure("unexpected task failure") }
        })
        try await waitUntil { status.counts.started == 1 }
        precondition(!job.start { preconditionFailure("duplicate request accepted") })
        checks += 1
        job.cancel()
        job.cancel()
        try await waitUntil { status.counts.cancelled == 1 }
        precondition(!job.start { preconditionFailure("invalidated connection reused") })
        checks += 1
        let invalidated = DownloadJob()
        invalidated.cancel()
        precondition(!invalidated.start { preconditionFailure("request started after connection invalidation") })
        checks += 1
        print("PASS \(checks) transfer failure, cancellation, retry and job lifecycle scenarios (URLProtocol, no network)")
    }
}
