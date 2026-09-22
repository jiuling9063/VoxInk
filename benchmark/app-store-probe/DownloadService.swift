import Foundation

private final class DownloadRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(DownloadFixture.allowsRequest(to: request.url) ? request : nil)
    }
}

private final class DownloadService: NSObject, ProbeDownloadService {
    func downloadConfiguration(to destination: FileHandle,
                               reply: @escaping @Sendable (String?, NSError?) -> Void) {
        Task {
            defer { try? destination.close() }
            do {
                let fixture = try DownloadFixture.load()
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 20
                configuration.timeoutIntervalForResource = 30
                configuration.httpCookieStorage = nil
                let session = URLSession(configuration: configuration, delegate: DownloadRedirectPolicy(), delegateQueue: nil)
                defer { session.invalidateAndCancel() }
                let (bytes, response) = try await session.bytes(from: fixture.download_url)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      DownloadFixture.allowsRequest(to: response.url) else {
                    throw URLError(.badServerResponse)
                }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < fixture.size_bytes else { throw URLError(.dataLengthExceedsMaximum) }
                    data.append(byte)
                }
                try fixture.verify(data)
                try destination.write(contentsOf: data)
                try destination.synchronize()
                reply("XPC pid=\(ProcessInfo.processInfo.processIdentifier) sandbox=\(entitlementEnabled("com.apple.security.app-sandbox")) network.client=\(entitlementEnabled("com.apple.security.network.client")) bytes=\(data.count)", nil)
            } catch { reply(nil, error as NSError) }
        }
    }
}

private final class Listener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ProbeDownloadService.self)
        connection.exportedObject = DownloadService()
        connection.resume()
        return true
    }
}

@main struct DownloadServiceMain {
    static func main() {
        let delegate = Listener()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        withExtendedLifetime(delegate) { listener.resume() }
    }
}
