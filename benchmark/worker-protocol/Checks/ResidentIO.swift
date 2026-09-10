import Foundation
import Darwin

@main
struct ResidentIOCheck {
    static func main() throws {
        if ProcessInfo.processInfo.environment["VOXINK_EXIT_DELAY"] == "1" {
            atexit { sleep(2) }
        }
        let input = ResidentInput()
        while true {
            let request = try input.next()
            FileHandle.standardOutput.write(Data((request.request_id + "\n").utf8))
            if request.sample_id == "slow" { Thread.sleep(forTimeInterval: 30) }
        }
    }
}
