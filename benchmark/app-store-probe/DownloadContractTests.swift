import Foundation

@main struct DownloadContractTests {
    static func main() throws {
        var checks = 0
        func expect(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        func rejected(_ message: String, _ operation: () throws -> Void) {
            do { try operation(); preconditionFailure(message) }
            catch { checks += 1 }
        }
        let fixture = DownloadFixture(download_url: URL(string: "https://huggingface.co/example/model/resolve/pinned/config.json")!,
                                      size_bytes: 3,
                                      sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        try fixture.validate()
        try fixture.verify(Data("abc".utf8))
        checks += 2
        rejected("same-size tampering accepted") { try fixture.verify(Data("abd".utf8)) }
        rejected("truncated download accepted") { try fixture.verify(Data("ab".utf8)) }
        rejected("oversized download accepted") { try fixture.verify(Data("abcd".utf8)) }
        for address in ["http://huggingface.co/config.json", "https://huggingface.co.evil.example/config.json",
                        "https://example.com/config.json", "file:///tmp/config.json",
                        "https://user:password@huggingface.co/config.json", "https://huggingface.co:444/config.json"] {
            expect(!DownloadFixture.allowsRequest(to: URL(string: address)), "unsafe redirect accepted: \(address)")
        }
        expect(!DownloadFixture.allowsRequest(to: nil), "missing URL accepted")
        expect(DownloadFixture.allowsRequest(to: fixture.download_url), "pinned URL rejected")
        for size in [0, 65_537] {
            rejected("invalid size accepted") {
                try DownloadFixture(download_url: fixture.download_url, size_bytes: size, sha256: fixture.sha256).validate()
            }
        }
        rejected("invalid digest accepted") {
            try DownloadFixture(download_url: fixture.download_url, size_bytes: 3, sha256: "invalid").validate()
        }
        rejected("executable fixture accepted") {
            try DownloadFixture(download_url: URL(string: "https://huggingface.co/example/run.py")!,
                                size_bytes: 3, sha256: fixture.sha256).validate()
        }
        print("PASS \(checks) download contract checks (offline)")
    }
}
