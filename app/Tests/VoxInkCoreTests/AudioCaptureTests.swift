import AVFoundation
import Foundation
import Testing
@testable import VoxInkCore

@Test func preparesStereoAudioAsPrivateMono16kWAV() throws {
    let source = try makePCMFixture(sampleRate: 44_100, channels: 2, duration: 0.25)
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

    let prepared = try AudioFilePreparation.prepare(url: source)
    defer { AudioFilePreparation.cleanup(url: prepared) }

    let file = try AVAudioFile(forReading: prepared)
    #expect(prepared.pathExtension.lowercased() == "wav")
    #expect(file.fileFormat.sampleRate == 16_000)
    #expect(file.fileFormat.channelCount == 1)
    #expect(file.fileFormat.commonFormat == .pcmFormatInt16)
    #expect(abs(Int(file.length) - 4_000) <= 2)
    #expect((try prepared.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 44)
    #expect((try FileManager.default.attributesOfItem(atPath: prepared.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect((try FileManager.default.attributesOfItem(atPath: prepared.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
}

@Test func rejectsAudioLongerThanSixtySeconds() throws {
    let source = try makePCMFixture(sampleRate: 16_000, channels: 1, duration: 60.01)
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

    #expect(throws: AudioCaptureError.durationLimitExceeded) {
        try AudioFilePreparation.prepare(url: source)
    }
}

@Test func rejectsEmptyAndInvalidInput() throws {
    let directory = try makePrivateFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let empty = directory.appendingPathComponent("empty.wav")
    let invalid = directory.appendingPathComponent("invalid.m4a")
    try Data().write(to: empty)
    try Data("not audio".utf8).write(to: invalid)

    #expect(throws: AudioCaptureError.self) { try AudioFilePreparation.prepare(url: empty) }
    #expect(throws: AudioCaptureError.self) { try AudioFilePreparation.prepare(url: invalid) }
}

@Test func preparationDoesNotModifyOriginalAndCleanupIsScoped() throws {
    let source = try makePCMFixture(sampleRate: 8_000, channels: 1, duration: 0.1)
    let original = try Data(contentsOf: source)
    defer { try? FileManager.default.removeItem(at: source.deletingLastPathComponent()) }

    let prepared = try AudioFilePreparation.prepare(url: source)
    #expect(try Data(contentsOf: source) == original)
    AudioFilePreparation.cleanup(url: source)
    #expect(FileManager.default.fileExists(atPath: source.path))
    AudioFilePreparation.cleanup(url: prepared)
    #expect(!FileManager.default.fileExists(atPath: prepared.deletingLastPathComponent().path))
}

@Test @MainActor func newCaptureIsIdleAndCanBeCancelledSafely() {
    let capture = AudioCapture()
    #expect(!capture.isRecording)
    #expect(capture.sample().elapsed == 0)
    #expect(capture.sample().level == 0)
    capture.cancel()
    #expect(!capture.isRecording)
}

private func makePCMFixture(sampleRate: Double, channels: AVAudioChannelCount, duration: Double) throws -> URL {
    let directory = try makePrivateFixtureDirectory()
    let url = directory.appendingPathComponent("fixture.wav")
    let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: channels,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let frameCount = AVAudioFrameCount(sampleRate * duration)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount))
    buffer.frameLength = frameCount
    try file.write(from: buffer)
    return url
}

private func makePrivateFixtureDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url,
                                            withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    return url
}
