import AVFoundation
import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

@MainActor private final class SilenceResultService: TranscriptionService {
    var silent = false
    func prepare() async throws {}
    func transcribe(url: URL) async throws -> String {
        if silent { throw QwenTranscriptionService.ServiceError.noSpeech }
        return "保留上一次结果。"
    }
    func cancel() async {}
}

@MainActor struct SilentAudioTests {
    @Test func silencePreservesPreviousTextAndExplainsNoInput() async {
        let service = SilenceResultService()
        let store = AppStore(service: service, preferences: nil, audioCleaner: { _ in })
        await store.transcribePrepared(URL(fileURLWithPath: "/fixture.wav"))
        service.silent = true
        await store.transcribePrepared(URL(fileURLWithPath: "/fixture.wav"))
        #expect(store.phase == .ready)
        #expect(store.transcript == "保留上一次结果。")
        #expect(store.status.contains("没有检测到有效音频"))
    }

    private func audio(seconds: Int, lastSample: Float = 0) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("silence.wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let frames = AVAudioFrameCount(seconds * 16_000)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let channel = try #require(buffer.floatChannelData?[0])
        channel.update(repeating: 0, count: Int(frames))
        channel[Int(frames)-1] = lastSample
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    @Test(arguments: [1, 60]) func pureSilenceIsRejectedBeforeWorkerStarts(seconds: Int) async throws {
        let url = try audio(seconds: seconds)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = QwenTranscriptionService(resources: nil)
        do {
            _ = try await service.transcribe(url: url)
            Issue.record("Pure silence must not produce a transcript")
        } catch {
            #expect(error as? QwenTranscriptionService.ServiceError == .noSpeech)
        }
    }

    @Test func faintSignalAtEndStillReachesSpeechDetection() async throws {
        let url = try audio(seconds: 60, lastSample: 1 / 32_768)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = QwenTranscriptionService(resources: nil, speechDetector: { input in
            #expect(input == url)
            return true
        })
        do {
            _ = try await service.transcribe(url: url)
            Issue.record("The missing Worker bundle should be reported")
        } catch {
            #expect(error as? QwenTranscriptionService.ServiceError == .missingBundle)
        }
    }
}
