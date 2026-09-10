import Foundation
import VoxInkCore

@main struct SpeechCheck {
    private struct Result: Encodable {
        let sample: String
        let assessment: SpeechActivityAssessment
        let milliseconds: Double
    }
    static func main() async throws {
        guard CommandLine.arguments.count > 1 else {
            throw SpeechActivityError.invalidAudio
        }
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            let start = ContinuousClock.now
            let assessment = try await SpeechActivityDetector.assess(url: url)
            let duration = start.duration(to: .now).components
            let milliseconds = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
            let output = Result(sample: url.lastPathComponent, assessment: assessment, milliseconds: milliseconds)
            FileHandle.standardOutput.write(try JSONEncoder().encode(output) + Data([10]))
        }
    }
}
