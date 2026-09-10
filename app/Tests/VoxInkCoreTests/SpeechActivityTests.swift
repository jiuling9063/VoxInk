import Foundation
import Testing
@testable import VoxInkCore

struct SpeechActivityTests {
    @Test func classificationThresholdDoesNotUseAverageLoudnessOrDropBriefSpeech() throws {
        var evidence = SpeechActivityEvidence()
        for _ in 0..<100 { evidence.record(confidence: 0.1) }
        evidence.record(confidence: 0.5)
        evidence.completed = true
        #expect(try evidence.assessment().hasSpeech)
        var noise = SpeechActivityEvidence()
        noise.record(confidence: 0.499); noise.completed = true
        #expect(try !noise.assessment().hasSpeech)
    }

    @Test func failedOrIncompleteAnalysisIsNotMisreportedAsSilence() {
        for confidence in [Double.nan, .infinity, -0.1, 1.1] {
            var evidence = SpeechActivityEvidence()
            evidence.record(confidence: confidence); evidence.completed = true
            #expect(throws: SpeechActivityError.analysisFailed) { try evidence.assessment() }
        }
        var evidence = SpeechActivityEvidence()
        #expect(throws: SpeechActivityError.noResults) { try evidence.assessment() }
        evidence.record(confidence: 0.9)
        #expect(throws: SpeechActivityError.noResults) { try evidence.assessment() }
        evidence.completed = true; evidence.fail()
        #expect(throws: SpeechActivityError.analysisFailed) { try evidence.assessment() }
    }

    @Test func reproducedNoiseIsRejectedWithoutChangingTheFile() async throws {
        let url = try #require(Bundle.module.url(forResource: "noise-regression", withExtension: "wav", subdirectory: "Fixtures"))
        let before = try Data(contentsOf: url)
        #expect(try AudioFilePreparation.containsSignal(url: url))
        let result = try await SpeechActivityDetector.assess(url: url)
        #expect(!result.hasSpeech)
        #expect(result.windowsAnalyzed > 0)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func cancelledRequestDoesNotAnalyzeOrReturnANonSpeechDecision() async {
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await SpeechActivityDetector.assess(url: URL(fileURLWithPath: "/must-not-read.wav"))
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func missingAudioDoesNotBecomeANonSpeechDecision() async {
        await #expect(throws: SpeechActivityError.invalidAudio) {
            try await SpeechActivityDetector.assess(url: URL(fileURLWithPath: "/no-such-voxink-file.wav"))
        }
    }
}
