import AVFoundation
import Foundation

public enum AudioCaptureError: Error, Equatable, Sendable {
    case alreadyRecording
    case notRecording
    case recordingFailed
    case invalidAudio
    case emptyAudio
    case durationLimitExceeded
    case conversionFailed
}

public struct AudioCaptureSample: Equatable, Sendable {
    public let elapsed: TimeInterval
    public let level: Float

    public init(elapsed: TimeInterval, level: Float) {
        self.elapsed = elapsed
        self.level = level
    }
}

@MainActor
public final class AudioCapture {
    public var isRecording: Bool { recorder?.isRecording ?? false }

    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var lastElapsed: TimeInterval = 0

    public init() {}

    public func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func start() throws {
        guard recorder == nil else { throw AudioCaptureError.alreadyRecording }

        let outputURL = try AudioTemporaryStorage.makeOutputURL()
        do {
            let recorder = try AVAudioRecorder(
                url: outputURL,
                settings: AudioTemporaryStorage.outputSettings
            )
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record(forDuration: AudioTemporaryStorage.maximumDuration) else {
                throw AudioCaptureError.recordingFailed
            }
            self.recorder = recorder
            recordingURL = outputURL
            lastElapsed = 0
        } catch {
            AudioFilePreparation.cleanup(url: outputURL)
            throw error
        }
    }

    public func sample() -> AudioCaptureSample {
        guard let recorder else {
            return AudioCaptureSample(elapsed: 0, level: 0)
        }
        recorder.updateMeters()
        lastElapsed = min(max(lastElapsed, recorder.currentTime), AudioTemporaryStorage.maximumDuration)
        let decibels = recorder.averagePower(forChannel: 0)
        let level = min(max((decibels + 60) / 60, 0), 1)
        return AudioCaptureSample(elapsed: lastElapsed, level: level)
    }

    public func stop() throws -> URL {
        guard let recorder, let recordingURL else {
            throw AudioCaptureError.notRecording
        }
        recorder.stop()
        defer {
            self.recorder = nil
            self.recordingURL = nil
        }

        do {
            guard FileManager.default.fileExists(atPath: recordingURL.path) else {
                throw AudioCaptureError.recordingFailed
            }
            try AudioTemporaryStorage.secureFile(at: recordingURL)
            return recordingURL
        } catch {
            AudioFilePreparation.cleanup(url: recordingURL)
            throw error
        }
    }

    public func cancel() {
        recorder?.stop()
        recorder = nil
        if let recordingURL {
            AudioFilePreparation.cleanup(url: recordingURL)
        }
        recordingURL = nil
    }
}

public enum AudioFilePreparation {
    /// Reject only digital silence. This is not a voice detector or a loudness threshold.
    public static func containsSignal(url: URL) throws -> Bool {
        guard url.isFileURL else { throw AudioCaptureError.invalidAudio }
        let source = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard source.fileFormat.sampleRate > 0 else { throw AudioCaptureError.invalidAudio }
        guard Double(source.length) / source.fileFormat.sampleRate <= AudioTemporaryStorage.maximumDuration else {
            throw AudioCaptureError.durationLimitExceeded
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 4_096) else {
            throw AudioCaptureError.conversionFailed
        }
        while source.framePosition < source.length {
            try source.read(into: buffer)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
                throw AudioCaptureError.conversionFailed
            }
            for channel in 0..<Int(source.processingFormat.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let value = channels[channel][frame]
                    guard value.isFinite else { throw AudioCaptureError.invalidAudio }
                    if value != 0 { return true }
                }
            }
        }
        return false
    }

    public static func prepare(url: URL) throws -> URL {
        guard url.isFileURL else { throw AudioCaptureError.invalidAudio }
        let source: AVAudioFile
        do {
            source = try AVAudioFile(forReading: url)
        } catch {
            throw AudioCaptureError.invalidAudio
        }
        guard source.length > 0, source.fileFormat.sampleRate > 0 else {
            throw AudioCaptureError.emptyAudio
        }

        let duration = Double(source.length) / source.fileFormat.sampleRate
        guard duration <= AudioTemporaryStorage.maximumDuration else {
            throw AudioCaptureError.durationLimitExceeded
        }

        let outputURL = try AudioTemporaryStorage.makeOutputURL()
        do {
            try convert(source: source, to: outputURL)
            try AudioTemporaryStorage.secureFile(at: outputURL)
            return outputURL
        } catch let error as AudioCaptureError {
            cleanup(url: outputURL)
            throw error
        } catch {
            cleanup(url: outputURL)
            throw AudioCaptureError.conversionFailed
        }
    }

    public static func cleanup(url: URL) {
        let directory = url.standardizedFileURL.deletingLastPathComponent()
        guard AudioTemporaryStorage.owns(directory: directory) else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    public static func purgeExpiredTemporaryAudio() throws {
        try purgeExpiredTemporaryAudio(in: AudioTemporaryStorage.root, now: Date())
    }

    static func purgeExpiredTemporaryAudio(in root: URL, now: Date) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return }
        guard try manager.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw AudioCaptureError.invalidAudio
        }
        for directory in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard UUID(uuidString: directory.lastPathComponent) != nil else { continue }
            let attributes = try manager.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else { continue }
            let children = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard children.count <= 1, children.allSatisfy({ $0.lastPathComponent == "audio.wav" }) else { continue }
            var dates = [attributes[.creationDate], attributes[.modificationDate]].compactMap { $0 as? Date }
            if let audio = children.first {
                let file = try manager.attributesOfItem(atPath: audio.path)
                guard file[.type] as? FileAttributeType == .typeRegular else { continue }
                dates.append(contentsOf: [file[.creationDate], file[.modificationDate]].compactMap { $0 as? Date })
            }
            guard let newest = dates.max(), newest <= now.addingTimeInterval(-86_400) else { continue }
            try manager.removeItem(at: directory)
        }
    }

    private static func convert(source: AVAudioFile, to outputURL: URL) throws {
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ), let converter = AVAudioConverter(from: source.processingFormat, to: outputFormat) else {
            throw AudioCaptureError.conversionFailed
        }

        let output = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        let capacity: AVAudioFrameCount = 4_096
        var inputReachedEnd = false
        var readError: Error?
        var conversionError: NSError?

        conversionLoop: while true {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
                throw AudioCaptureError.conversionFailed
            }
            conversionError = nil
            let status = converter.convert(to: buffer, error: &conversionError) { requestedPackets, statusPointer in
                if inputReachedEnd {
                    statusPointer.pointee = .endOfStream
                    return nil
                }
                let remaining = source.length - source.framePosition
                if remaining <= 0 {
                    inputReachedEnd = true
                    statusPointer.pointee = .endOfStream
                    return nil
                }
                let frameCount = min(requestedPackets, AVAudioFrameCount(remaining))
                guard let input = AVAudioPCMBuffer(
                    pcmFormat: source.processingFormat,
                    frameCapacity: frameCount
                ) else {
                    statusPointer.pointee = .noDataNow
                    return nil
                }
                do {
                    try source.read(into: input, frameCount: frameCount)
                    if input.frameLength == 0 {
                        inputReachedEnd = true
                        statusPointer.pointee = .endOfStream
                        return nil
                    }
                    statusPointer.pointee = .haveData
                    return input
                } catch {
                    readError = error
                    inputReachedEnd = true
                    statusPointer.pointee = .endOfStream
                    return nil
                }
            }

            if readError != nil {
                throw AudioCaptureError.conversionFailed
            }
            if conversionError != nil {
                throw AudioCaptureError.conversionFailed
            }
            if status == .error {
                throw AudioCaptureError.conversionFailed
            }
            if buffer.frameLength > 0 {
                try output.write(from: buffer)
            }
            if status == .endOfStream {
                break conversionLoop
            }
        }

        guard output.length > 0 else { throw AudioCaptureError.emptyAudio }
    }
}

private enum AudioTemporaryStorage {
    static let maximumDuration: TimeInterval = 60
    static let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("com.voxink.audio", isDirectory: true)
        .standardizedFileURL

    static var outputSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
    }

    static func makeOutputURL() throws -> URL {
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return directory.appendingPathComponent("audio.wav")
    }

    static func secureFile(at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func owns(directory: URL) -> Bool {
        let candidate = directory.standardizedFileURL
        return candidate.deletingLastPathComponent() == root && UUID(uuidString: candidate.lastPathComponent) != nil
    }
}
