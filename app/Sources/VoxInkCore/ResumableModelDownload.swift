import Foundation

public struct ResumableModelDownload: ModelDownloadTransport {
    private let configuration: URLSessionConfiguration
    public init(configuration: URLSessionConfiguration = .ephemeral) { self.configuration = configuration }

    public func download(_ file: ModelPackage.File, to partialURL: URL,
        progress: @escaping @Sendable (Int64) -> Void) async throws {
        let cancellation = DownloadCancellation()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                do {
                    let attempt = try DownloadAttempt(file: file, partial: partialURL, progress: progress, continuation: continuation)
                    attempt.start(configuration: configuration, cancellation: cancellation)
                } catch { continuation.resume(throwing: error) }
            }
        } onCancel: { cancellation.cancel() }
    }
}

// Cancellation may arrive on any executor; all delegate/file state below stays on a serial queue.
private final class DownloadCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false
    func install(_ task: URLSessionTask) {
        let shouldCancel = lock.withLock { self.task = task; return cancelled }
        if shouldCancel { task.cancel() }
    }
    func cancel() {
        let current = lock.withLock { cancelled = true; return task }
        current?.cancel()
    }
}

private final class DownloadAttempt: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let file: ModelPackage.File
    private let handle: FileHandle
    private let progress: @Sendable (Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var received: Int64
    private var failure: Error?
    private var acceptedResponse = false
    private var lastProgress: ContinuousClock.Instant?

    init(file: ModelPackage.File, partial: URL, progress: @escaping @Sendable (Int64) -> Void,
         continuation: CheckedContinuation<Void, Error>) throws {
        self.file = file
        self.handle = try ModelStorage.openPartial(partial)
        self.received = Int64(try handle.seekToEnd())
        self.progress = progress
        self.continuation = continuation
        super.init()
    }

    func start(configuration: URLSessionConfiguration, cancellation: DownloadCancellation) {
        let configured = configuration.copy() as! URLSessionConfiguration
        configured.urlCache = nil
        configured.urlCredentialStorage = nil
        configured.httpCookieStorage = nil
        configured.httpShouldSetCookies = false
        configured.timeoutIntervalForRequest = 30
        configured.timeoutIntervalForResource = 3_600
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configured, delegate: self, delegateQueue: queue)
        self.session = session
        var request = URLRequest(url: file.downloadURL)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if received > 0 { request.setValue("bytes=\(received)-", forHTTPHeaderField: "Range") }
        let task = session.dataTask(with: request)
        cancellation.install(task)
        task.resume()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let host = request.url?.host?.lowercased() ?? ""
        let allowed = request.url?.scheme == "https" &&
            (host == "huggingface.co" || host.hasSuffix(".huggingface.co") || host.hasSuffix(".hf.co"))
        if !allowed { failure = ModelInstallationError.response(response.statusCode) }
        completionHandler(allowed ? request : nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let http = response as? HTTPURLResponse else { throw ModelInstallationError.invalidRange }
            let encoding = http.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()
            guard encoding == nil || encoding == "identity" else { throw ModelInstallationError.invalidRange }
            switch http.statusCode {
            case 200:
                guard response.expectedContentLength <= file.sizeBytes else { throw ModelInstallationError.invalidRange }
                try handle.truncate(atOffset: 0)
                try handle.seek(toOffset: 0)
                received = 0
            case 206:
                let range = http.value(forHTTPHeaderField: "Content-Range") ?? ""
                let parts = range.replacingOccurrences(of: "bytes ", with: "").split(separator: "/")
                let bounds = parts.first?.split(separator: "-") ?? []
                guard range.hasPrefix("bytes "), parts.count == 2, bounds.count == 2,
                      Int64(parts[1]) == file.sizeBytes, Int64(bounds[0]) == received,
                      let end = Int64(bounds[1]), end >= received, end < file.sizeBytes else {
                    throw ModelInstallationError.invalidRange
                }
            default: throw ModelInstallationError.response(http.statusCode)
            }
            if response.expectedContentLength >= 0,
               response.expectedContentLength > file.sizeBytes - received { throw ModelInstallationError.invalidRange }
            acceptedResponse = true
            progress(received)
            completionHandler(.allow)
        } catch {
            failure = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard acceptedResponse, failure == nil else { return }
        do {
            guard Int64(data.count) <= file.sizeBytes - received else { throw ModelInstallationError.invalidRange }
            try handle.write(contentsOf: data)
            received += Int64(data.count)
            let now = ContinuousClock.now
            if lastProgress == nil || now - lastProgress! >= .milliseconds(100) || received == file.sizeBytes {
                lastProgress = now
                progress(received)
            }
        } catch { failure = error; dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        do { try handle.synchronize(); try handle.close() }
        catch { failure = failure ?? error }
        let finalError = failure ?? error ?? (received == file.sizeBytes && acceptedResponse ? nil : ModelInstallationError.incomplete)
        let pending = continuation
        continuation = nil
        session.finishTasksAndInvalidate()
        self.session = nil
        if let finalError { pending?.resume(throwing: finalError) }
        else { pending?.resume() }
    }
}
