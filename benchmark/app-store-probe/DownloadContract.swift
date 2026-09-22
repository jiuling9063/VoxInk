import CryptoKit
import Foundation
import Security
import Darwin

@objc protocol ProbeDownloadService {
    // Only a fixed, pinned config may be downloaded. No URL, upload data or output path crosses XPC.
    func downloadConfiguration(to destination: FileHandle,
                               reply: @escaping @Sendable (String?, NSError?) -> Void)
}

struct DownloadFixture: Decodable, Sendable {
    let download_url: URL
    let size_bytes: Int
    let sha256: String

    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "download-fixture", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let fixture = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try fixture.validate()
        return fixture
    }

    static func allowsRequest(to url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == "huggingface.co"
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    func validate() throws {
        guard Self.allowsRequest(to: download_url), download_url.path.hasSuffix("/config.json"),
              (1...65_536).contains(size_bytes), sha256.count == 64,
              sha256.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func verify(_ data: Data) throws {
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == size_bytes, actual == sha256 else { throw CocoaError(.fileReadCorruptFile) }
    }
}

func entitlementEnabled(_ key: String) -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    return (SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? NSNumber)?.boolValue == true
}

// Loopback port 9 needs no external traffic. EPERM/EACCES distinguishes sandbox denial
// from ECONNREFUSED on an unrestricted process without a listener.
func networkConnectError() -> Int32 {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return errno }
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(9).bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    return result == 0 ? 0 : errno
}
