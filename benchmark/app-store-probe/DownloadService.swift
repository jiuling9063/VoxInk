import Foundation

private final class DownloadService: NSObject, ProbeDownloadService {
    let job = DownloadJob()

    func downloadConfiguration(to destination: FileHandle,
                               reply: @escaping @Sendable (String?, NSError?) -> Void) {
        let accepted = job.start {
            defer { try? destination.close() }
            do {
                let fixture = try DownloadFixture.load()
                let count = try await DownloadTransfer().write(fixture, to: destination)
                reply("XPC pid=\(ProcessInfo.processInfo.processIdentifier) sandbox=\(entitlementEnabled("com.apple.security.app-sandbox")) network.client=\(entitlementEnabled("com.apple.security.network.client")) bytes=\(count)", nil)
            } catch { reply(nil, error as NSError) }
        }
        if !accepted {
            try? destination.close()
            reply(nil, CocoaError(.xpcConnectionInvalid) as NSError)
        }
    }
}

private final class Listener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ProbeDownloadService.self)
        let service = DownloadService()
        connection.exportedObject = service
        connection.invalidationHandler = { service.job.cancel() }
        connection.interruptionHandler = { service.job.cancel() }
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
