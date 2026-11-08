import AVFoundation
import AudioToolbox
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
    public var deviceUID: String?
    private let worker = DispatchQueue(label: "local.voxink.audio-capture", qos: .userInitiated)
    private var session: CaptureSession?
    private var started = false

    public init() {}

    public func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    public var isRecording: Bool {
        guard started, let session else { return false }
        return worker.sync { session.isRecording }
    }

    public func start() async throws {
        guard session == nil else { throw AudioCaptureError.alreadyRecording }
        try Task.checkCancellation()
        let next = CaptureSession()
        let device = deviceUID
        session = next
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                worker.async { [worker] in
                    continuation.resume(with: Result { try next.start(deviceUID: device) })
                }
            }
            try Task.checkCancellation()
            guard session === next else { throw CancellationError() }
            started = true
        } catch {
            if session === next { cancel() }
            throw error
        }
    }

    public func sample() -> AudioCaptureSample {
        guard started, let session else { return .init(elapsed: 0, level: 0) }
        return worker.sync { session.sample() }
    }

    public func stop() async throws -> URL {
        guard started, let session else { throw AudioCaptureError.notRecording }
        self.session = nil
        started = false
        return try await withCheckedThrowingContinuation { continuation in
            worker.async {
                continuation.resume(with: Result { try session.stop() })
            }
        }
    }

    public func cancel() {
        guard let session else { return }
        self.session = nil
        started = false
        // FIFO teardown runs before any subsequent start, including after a quick key release.
        worker.async { session.cancel() }
    }

    public func finishPendingCleanup() async {
        await withCheckedContinuation { continuation in
            worker.async { continuation.resume() }
        }
    }
}

// The capture worker owns the AudioQueue lifecycle. Disposal waits for Core Audio's callbacks,
// so those callbacks must run independently of the worker that disposes the queue.
private final class CaptureSession: @unchecked Sendable {
    private var queue: AudioQueueRef?
    private var file: AudioFileID?
    private var recordingURL: URL?
    private let callbacks = DispatchQueue(label: "local.voxink.audio-input-buffers", qos: .userInitiated)
    // Accessed on callbacks. The file is opened before callback registration and closed after disposal.
    private var shouldReenqueue = true
    private var bytes: Int64 = 0
    private var writeFailed = false
    private static let maximumBytes: Int64 = 60 * 16_000 * 2

    var isRecording: Bool {
        guard let queue, !callbacks.sync(execute: { writeFailed }) else { return false }
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: running))
        return AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &running, &size) == noErr && running != 0
    }

    func start(deviceUID: String?) throws {
        guard queue == nil else { throw AudioCaptureError.alreadyRecording }
        let url = try AudioTemporaryStorage.makeOutputURL()
        recordingURL = url
        var format = AudioStreamBasicDescription(mSampleRate: 16_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
            mBitsPerChannel: 16, mReserved: 0)
        do {
            try check(AudioFileCreateWithURL(url as CFURL, kAudioFileWAVEType, &format, .eraseFile, &file))
            try AudioTemporaryStorage.secureFile(at: url)
            try check(AudioQueueNewInputWithDispatchQueue(&queue, &format, 0, callbacks) { [weak self] queue, buffer, _, _, _ in
                guard let self, let file = self.file else { return }
                var count = min(buffer.pointee.mAudioDataByteSize, UInt32(Self.maximumBytes - self.bytes))
                if count > 0 {
                    guard AudioFileWriteBytes(file, false, self.bytes, &count, buffer.pointee.mAudioData) == noErr else {
                        self.writeFailed = true
                        return
                    }
                    self.bytes += Int64(count)
                }
                if self.shouldReenqueue, self.bytes < Self.maximumBytes, AudioQueueEnqueueBuffer(queue, buffer, 0, nil) != noErr {
                    self.writeFailed = true
                }
            })
            guard let queue else { throw AudioCaptureError.recordingFailed }
            if let deviceUID {
                let string = deviceUID as CFString
                try withExtendedLifetime(string) {
                    var uid = Unmanaged.passUnretained(string).toOpaque()
                    try check(AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, &uid, UInt32(MemoryLayout.size(ofValue: uid))))
                }
            }
            var metering: UInt32 = 1
            try check(AudioQueueSetProperty(queue, kAudioQueueProperty_EnableLevelMetering, &metering, 4))
            for _ in 0..<3 {
                var buffer: AudioQueueBufferRef?
                try check(AudioQueueAllocateBuffer(queue, 1_024, &buffer))
                guard let buffer else { throw AudioCaptureError.recordingFailed }
                try check(AudioQueueEnqueueBuffer(queue, buffer, 0, nil))
            }
            try check(AudioQueueStart(queue, nil))
        } catch {
            cancel()
            throw error
        }
    }

    func sample() -> AudioCaptureSample {
        var meter = AudioQueueLevelMeterState()
        var size = UInt32(MemoryLayout.size(ofValue: meter))
        if let queue { AudioQueueGetProperty(queue, kAudioQueueProperty_CurrentLevelMeter, &meter, &size) }
        return .init(elapsed: callbacks.sync { Double(bytes) / 32_000 }, level: min(1, max(0, meter.mPeakPower)))
    }

    func stop() throws -> URL {
        guard let url = recordingURL else { throw AudioCaptureError.notRecording }
        close()
        recordingURL = nil
        return url
    }

    func cancel() {
        close()
        if let recordingURL { AudioFilePreparation.cleanup(url: recordingURL) }
        recordingURL = nil
    }

    private func close() {
        if let queue {
            callbacks.sync { shouldReenqueue = false }
            AudioQueueDispose(queue, true)
            self.queue = nil
        }
        callbacks.sync {
            if let file { AudioFileClose(file); self.file = nil }
        }
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw AudioCaptureError.recordingFailed }
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
