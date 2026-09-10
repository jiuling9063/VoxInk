import AudioCommon
import Darwin
import Foundation
import Qwen3ASR
import VoxInkWorkerProtocol
import VoxInkQwenSmokeCore

@main
struct VoxInkQwenSmokeCommand {
    static func main() async {
        do {
            let output = try JSONOutput()
            let configuration = try SmokeConfiguration.parse(
                arguments: Array(CommandLine.arguments.dropFirst())
            )
            try await run(configuration, output: output)
        } catch {
            FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run(_ configuration: SmokeConfiguration, output: JSONOutput) async throws {
        let residentInput = configuration.resident ? ResidentInput() : nil
        let requests: [BatchRequest]?
        if let plan = configuration.batchPlan {
            requests = try JSONDecoder().decode([BatchRequest].self, from: Data(contentsOf: URL(fileURLWithPath: plan)))
            guard let requests, !requests.isEmpty else { throw SmokeConfigurationError.emptyValue("--batch-plan") }
        } else { requests = nil }
        let manifestURL = URL(fileURLWithPath: configuration.manifestPath)
        let directory = try HuggingFaceDownloader.getCacheDirectory(for: SmokeContract.modelID)
        let verified = try ModelVerifier.verify(manifestURL: manifestURL, directory: directory)
        let loadStart = ContinuousClock.now
        let model = try await Qwen3ASRModel.fromPretrained(
            modelId: SmokeContract.modelID,
            progressHandler: { progress, stage in
                let percent = Int((progress * 100).rounded())
                FileHandle.standardError.write(Data("MODEL \(percent)% \(stage)\n".utf8))
            }
        )
        let loadMs = elapsedMilliseconds(since: loadStart)
        // The pinned upstream loader may refresh its cache. Never label changed bytes as the pinned revision.
        let afterLoad = try ModelVerifier.verify(manifestURL: manifestURL, directory: directory)
        guard afterLoad == verified else {
            throw ModelVerifier.VerificationError.identityMismatch
        }

        if configuration.prepareOnly {
            let result = ModelPreparationResult(
                status: "model_loaded_manifest_verified",
                engine: SmokeContract.engine,
                engineVersion: SmokeContract.engineRevision,
                modelID: SmokeContract.modelID,
                modelRevision: verified.revision,
                loadMs: loadMs,
                peakRSSBytes: peakResidentBytes()
            )
            try output.write(result)
            return
        }

        if configuration.resident { try output.write(ResidentReady(loadMilliseconds: loadMs)) }
        let jobs = requests ?? [BatchRequest(request_id: "single", sample_id: configuration.sampleID,
                                             audio_path: configuration.audioPath ?? "")]
        var index = 0
        var contextTokenizer: Qwen3Tokenizer?
        while true {
            let request: BatchRequest
            if let residentInput {
                let next = try residentInput.next()
                request = BatchRequest(request_id: next.request_id, sample_id: next.sample_id, audio_path: next.audio_path)
            } else {
                guard index < jobs.count else { break }
                request = jobs[index]
                index += 1
            }
            do {
                let words = request.hotwords ?? []
                guard words.isEmpty || (configuration.experimentalHotwords && !configuration.simplifiedOutput) else {
                    throw HotwordError.incompatiblePrompt
                }
                if !words.isEmpty, contextTokenizer == nil {
                    let tokenizer = Qwen3Tokenizer()
                    try tokenizer.load(from: directory.appendingPathComponent("vocab.json"))
                    contextTokenizer = tokenizer
                }
                let hints = try HotwordContext.make(words: words) { contextTokenizer?.encode($0).count ?? 0 }
                let audioURL = URL(fileURLWithPath: request.audio_path)
                guard FileManager.default.fileExists(atPath: audioURL.path) else {
                    throw CocoaError(.fileNoSuchFile)
                }

                let audio = try AudioFileLoader.load(url: audioURL, targetSampleRate: SmokeContract.sampleRate)
                if ProcessInfo.processInfo.environment["VOXINK_WORKER_PHASES"] == "1" {
                    FileHandle.standardError.write(Data("VOXINK_PHASE transcribing\n".utf8))
                }
                let transcribeStart = ContinuousClock.now
                let rawText = model.transcribe(audio: audio, sampleRate: SmokeContract.sampleRate,
                    language: SmokeContract.language, context: hints.text ?? configuration.transcriptionContext)
                let transcribeMs = elapsedMilliseconds(since: transcribeStart)

                let result = SmokeResult(
                    runID: UUID().uuidString.lowercased(),
                    sampleID: request.sample_id,
                    engine: SmokeContract.engine,
                    engineVersion: SmokeContract.engineRevision,
                    modelRevision: verified.revision,
                    deviceProfile: configuration.deviceProfile,
                    language: SmokeContract.language,
                    rawText: rawText,
                    loadMs: loadMs,
                    transcribeMs: transcribeMs,
                    peakRSSBytes: peakResidentBytes(),
                    success: !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    errorCode: rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "empty_transcript"
                        : nil,
                    outputPolicy: configuration.simplifiedOutput ? "simplified_prompt_v1" : (hints.text == nil ? nil : "hotwords_v1"),
                    contextTokens: hints.tokenCount,
                    hotwordCount: hints.wordCount
                )
                if requests != nil || configuration.resident {
                    try output.write(BatchResponse(request_id: request.request_id, result: result, error_code: nil))
                } else { try output.write(result) }
            } catch is HotwordError {
                guard requests != nil || configuration.resident else { throw HotwordError.invalidWords }
                try output.write(BatchResponse(request_id: request.request_id, result: nil, error_code: "invalid_hotwords"))
            } catch {
                guard requests != nil || configuration.resident else { throw error }
                try output.write(BatchResponse(request_id: request.request_id, result: nil, error_code: "audio_or_inference_failed"))
            }
        }
    }

    struct BatchRequest: Decodable {
        let request_id: String
        let sample_id: String
        let audio_path: String
        var hotwords: [String]? = nil
    }
    struct BatchResponse: Encodable {
        let request_id: String
        let result: SmokeResult?
        let error_code: String?
    }

    private static func elapsedMilliseconds(since start: ContinuousClock.Instant) -> Int {
        let duration = start.duration(to: .now)
        return Int(duration.components.seconds * 1_000)
            + Int(duration.components.attoseconds / 1_000_000_000_000_000)
    }

    private static func peakResidentBytes() -> UInt64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return UInt64(max(usage.ru_maxrss, 0))
    }
}
