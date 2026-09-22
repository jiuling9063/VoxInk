import Foundation

private final class DownloadRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(DownloadFixture.allowsRequest(to: request.url) ? request : nil)
    }
}

struct DownloadTransfer {
    let configuration: URLSessionConfiguration

    init(configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
    }

    func write(_ fixture: DownloadFixture, to destination: FileHandle) async throws -> Int {
        try Task.checkCancellation()
        try fixture.validate()
        let configuration = configuration.copy() as! URLSessionConfiguration
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: DownloadRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: fixture.download_url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              DownloadFixture.allowsRequest(to: response.url) else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < fixture.size_bytes else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        try fixture.verify(data)
        try Task.checkCancellation()
        try destination.write(contentsOf: data)
        try destination.synchronize()
        return data.count
    }
}

// XPC callbacks can arrive on different queues. Keep the connection's task under
// one lock so invalidation also cancels a request racing with its creation.
final class DownloadJob: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var invalidated = false

    func start(_ operation: @escaping @Sendable () async -> Void) -> Bool {
        lock.withLock {
            guard !invalidated, task == nil else { return false }
            task = Task {
                await operation()
                lock.withLock { task = nil }
            }
            return true
        }
    }

    func cancel() {
        let current = lock.withLock { invalidated = true; return task }
        current?.cancel()
    }
}
