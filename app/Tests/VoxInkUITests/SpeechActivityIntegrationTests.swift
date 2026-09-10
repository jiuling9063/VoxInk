import Foundation
import AVFoundation
import Testing
import VoxInkCore
@testable import VoxInkUI

private actor ActivityFailureService: TranscriptionService {
    func prepare() async throws {}
    func transcribe(url: URL) async throws -> String { throw SpeechActivityError.unavailable }
    func cancel() async {}
}

@MainActor struct SpeechActivityIntegrationTests {
    @Test func rejectedSignalStopsBeforeModelLoading() async throws {
        let url = try signalFixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = try Data(contentsOf: url)
        let service = QwenTranscriptionService(resources: nil, speechDetector: { input in
            #expect(input == url)
            return false
        })
        await #expect(throws: QwenTranscriptionService.ServiceError.noSpeechDetected) { try await service.transcribe(url: url) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func acceptedSignalReachesModelPreparationAndDetectorFailureDoesNot() async throws {
        let url = try signalFixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let accepted = QwenTranscriptionService(resources: nil, speechDetector: { _ in true })
        await #expect(throws: QwenTranscriptionService.ServiceError.missingBundle) { try await accepted.transcribe(url: url) }
        let failed = QwenTranscriptionService(resources: nil, speechDetector: { _ in throw SpeechActivityError.analysisFailed })
        await #expect(throws: SpeechActivityError.analysisFailed) { try await failed.transcribe(url: url) }
    }
    @Test func unavailableDetectorOffersRetryWithoutBlamingTheModel() async {
        let store = AppStore(service: ActivityFailureService(), preferences: nil)
        await store.transcribePrepared(URL(fileURLWithPath: "/fixture.wav"))
        #expect(store.phase == .failed)
        #expect(store.recovery == .recordAgain)
        #expect(store.modelState != .failed)
        #expect(store.transcript.isEmpty)
        #expect(store.status.contains("语音检测"))
    }

    private func signalFixture() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("signal.wav")
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000))
        buffer.frameLength = 8000
        buffer.floatChannelData?[0].initialize(repeating: 0.001, count: 8000)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
}
