import Foundation

@main
struct JSONOutputChecks {
    static func main() throws {
        let output = try JSONOutput()
        print("upstream diagnostic")
        try output.write(["status": "ok"])
    }
}
