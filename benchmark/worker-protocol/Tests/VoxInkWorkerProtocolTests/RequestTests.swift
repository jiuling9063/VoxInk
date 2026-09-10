import Foundation
import Testing
@testable import VoxInkWorkerProtocol

@Test func decodesUnicodeAudioPath() throws {
    let request = try ResidentRequest.decode(Data(#"{"request_id":"one","sample_id":"S1","audio_path":"/tmp/语音.wav"}"#.utf8))
    #expect(request.request_id == "one")
    #expect(request.audio_path == "/tmp/语音.wav")
}

@Test func rejectsAmbiguousIdentifiersAndRelativePaths() {
    for line in [
        #"{"request_id":"","sample_id":"S1","audio_path":"/tmp/a.wav"}"#,
        #"{"request_id":"one","sample_id":"","audio_path":"/tmp/a.wav"}"#,
        #"{"request_id":"one","sample_id":"S1","audio_path":"relative.wav"}"#,
        #"{"request_id":"one","sample_id":"S1","audio_path":"/tmp/../private.wav"}"#
    ] {
        #expect(throws: (any Error).self) { try ResidentRequest.decode(Data(line.utf8)) }
    }
}

@Test func frameLimitRejectsUnboundedInput() {
    #expect(throws: (any Error).self) { try ResidentRequest.decode(Data(repeating: 32, count: 65537)) }
}
