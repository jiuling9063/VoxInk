import AVFoundation
import Foundation
import SoundAnalysis

public enum SpeechActivityError: Error, Equatable, Sendable {
    case unavailable, invalidAudio, analysisFailed, noResults
}

public struct SpeechActivityAssessment: Codable, Equatable, Sendable {
    public let hasSpeech: Bool
    public let maximumConfidence: Double
    public let windowsAnalyzed: Int
}

struct SpeechActivityEvidence {
    private(set) var maximumConfidence = 0.0
    private(set) var windowsAnalyzed = 0
    private(set) var failed = false
    var completed = false

    mutating func record(confidence: Double) {
        guard confidence.isFinite, (0...1).contains(confidence) else { failed = true; return }
        maximumConfidence = max(maximumConfidence, confidence)
        windowsAnalyzed += 1
    }
    mutating func fail() { failed = true }
    func assessment() throws -> SpeechActivityAssessment {
        guard !failed else { throw SpeechActivityError.analysisFailed }
        guard completed, windowsAnalyzed > 0 else { throw SpeechActivityError.noResults }
        return SpeechActivityAssessment(hasSpeech: maximumConfidence >= 0.5,
                                        maximumConfidence: maximumConfidence, windowsAnalyzed: windowsAnalyzed)
    }
}

private final class ActivityObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var evidence = SpeechActivityEvidence()
    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else {
            lock.withLock { evidence.fail() }; return
        }
        let confidence = result.classifications.filter { $0.identifier == "speech" || $0.identifier == "whispering" }
            .map(\.confidence).max() ?? .nan
        lock.withLock { evidence.record(confidence: confidence) }
    }
    func request(_ request: SNRequest, didFailWithError error: Error) { lock.withLock { evidence.fail() } }
    func requestDidComplete(_ request: SNRequest) { lock.withLock { evidence.completed = true } }
    func assessment() throws -> SpeechActivityAssessment { try lock.withLock { try evidence.assessment() } }
}

public enum SpeechActivityDetector {
    public static func assess(url: URL) async throws -> SpeechActivityAssessment {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) { try analyze(url: url) }
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: { task.cancel() }
    }

    private static func analyze(url: URL) throws -> SpeechActivityAssessment {
        try Task.checkCancellation()
        guard url.isFileURL else { throw SpeechActivityError.invalidAudio }
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) }
        catch { throw SpeechActivityError.invalidAudio }
        let format = file.processingFormat
        guard format.sampleRate == 16_000, format.channelCount == 1,
              file.length > 0, file.length <= 960_000 else { throw SpeechActivityError.invalidAudio }
        let request: SNClassifySoundRequest
        do { request = try SNClassifySoundRequest(classifierIdentifier: .version1) }
        catch { throw SpeechActivityError.unavailable }
        guard Set(["speech", "whispering"]).isSubset(of: Set(request.knownClassifications)) else {
            throw SpeechActivityError.unavailable
        }
        request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 16_000)
        request.overlapFactor = 0.5
        guard abs(request.windowDuration.seconds - 0.5) < 0.001 else { throw SpeechActivityError.unavailable }
        let observer = ActivityObserver()
        let analyzer = SNAudioStreamAnalyzer(format: format)
        do { try analyzer.add(request, withObserver: observer) }
        catch { throw SpeechActivityError.unavailable }
        defer { analyzer.removeAllRequests() }
        var position: AVAudioFramePosition = 0
        while file.framePosition < file.length {
            try Task.checkCancellation()
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096) else {
                throw SpeechActivityError.analysisFailed
            }
            do { try file.read(into: buffer) } catch { throw SpeechActivityError.invalidAudio }
            guard buffer.frameLength > 0, let samples = buffer.floatChannelData?[0],
                  UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)).allSatisfy(\.isFinite) else {
                throw SpeechActivityError.invalidAudio
            }
            analyzer.analyze(buffer, atAudioFramePosition: position)
            position += AVAudioFramePosition(buffer.frameLength)
        }
        try Task.checkCancellation()
        // Complete the final classifier window only; the file passed to ASR is never changed.
        guard let padding = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000),
              let samples = padding.floatChannelData?[0] else { throw SpeechActivityError.analysisFailed }
        padding.frameLength = 8000
        samples.initialize(repeating: 0, count: 8000)
        analyzer.analyze(padding, atAudioFramePosition: position)
        analyzer.completeAnalysis()
        try Task.checkCancellation()
        return try observer.assessment()
    }
}
