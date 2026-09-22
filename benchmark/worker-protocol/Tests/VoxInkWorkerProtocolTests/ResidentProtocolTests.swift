import Foundation
import Testing
@testable import VoxInkWorkerProtocol

@Test func supportedSpeechLanguagesPassAndUnknownValuesFail() throws {
    for language in ["auto", "zh", "yue", "en", "ja", "ko"] {
        let data = try JSONSerialization.data(withJSONObject: ["request_id": "one", "sample_id": "S1", "audio_path": "/tmp/test.wav", "language": language])
        #expect(try ResidentRequest.decode(data).language == language)
    }
    let data = Data(#"{"request_id":"one","sample_id":"S1","audio_path":"/tmp/test.wav","language":"invalid"}"#.utf8)
    #expect(throws: (any Error).self) { try ResidentRequest.decode(data) }
}
