import Darwin
import Foundation
import Hub
import Tokenizers
import WhisperKit
import VoxInkWorkerProtocol

// Internal CLI: the Python entrypoint verifies pinned assets before and after execution.
@main
struct Command {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard args.count == 3 || (args.count == 4 && args[2] == "--batch-plan") else { throw Failure.arguments }
            let fd = dup(STDOUT_FILENO)
            guard fd >= 0 else { throw Failure.output }
            guard dup2(STDERR_FILENO, STDOUT_FILENO) >= 0 else {
                close(fd)
                throw Failure.output
            }
            let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            let resident = args.count == 3 && args[2] == "--resident"
            let residentInput = resident ? ResidentInput() : nil
            let batch = args.count == 4
            let jobs = batch
                ? try JSONDecoder().decode([BatchRequest].self, from: Data(contentsOf: URL(fileURLWithPath: args[3])))
                : [BatchRequest(request_id: "single", audio_path: args[2])]
            guard !jobs.isEmpty else { throw Failure.arguments }
            let start = ContinuousClock.now
            let tokenizerURL = URL(fileURLWithPath: args[1])
            let local = LanguageModelConfigurationFromHub(modelFolder: tokenizerURL)
            guard let config = try await local.tokenizerConfig else { throw Failure.tokenizer }
            _ = try PreTrainedTokenizer(tokenizerConfig: config, tokenizerData: try await local.tokenizerData)
            let model = try await WhisperKit(WhisperKitConfig(
                modelFolder: args[0], tokenizerFolder: tokenizerURL,
                verbose: false, prewarm: false, load: false, download: false
            ))
            try await model.loadModels()
            // Pre-injecting a tokenizer skips upstream multilingual initialization.
            guard model.textDecoder.isModelMultilingual,
                  model.tokenizer?.convertTokenToId("<|zh|>") != nil else {
                throw Failure.tokenizer
            }
            let loadMS = milliseconds(start)
            if resident {
                var ready = try JSONEncoder().encode(ResidentReady(loadMilliseconds: loadMS))
                ready.append(10)
                try output.write(contentsOf: ready)
            }
            var index = 0
            while true {
                let request: BatchRequest
                if let residentInput {
                    let next = try residentInput.next()
                    request = BatchRequest(request_id: next.request_id, audio_path: next.audio_path)
                } else {
                    guard index < jobs.count else { break }
                    request = jobs[index]
                    index += 1
                }
                do {
                    let audio = try AudioProcessor.loadAudioAsFloatArray(fromPath: request.audio_path)
                    if ProcessInfo.processInfo.environment["VOXINK_WORKER_PHASES"] == "1" {
                        FileHandle.standardError.write(Data("VOXINK_PHASE transcribing\n".utf8))
                    }
                    let transcribeStart = ContinuousClock.now
                    let results: [TranscriptionResult] = try await model.transcribe(
                        audioArray: audio,
                        decodeOptions: DecodingOptions(language: "zh", temperature: 0,
                            detectLanguage: false, skipSpecialTokens: true, withoutTimestamps: true)
                    )
                    let elapsed = milliseconds(transcribeStart)
                    let text = results.map(\.text).joined()
                    var usage = rusage()
                    guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw Failure.metrics }
                    let row = Result(raw_text: text, load_ms: loadMS, transcribe_ms: elapsed,
                                     peak_rss_bytes: UInt64(max(usage.ru_maxrss, 0)),
                                     success: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    var data = (batch || resident)
                        ? try JSONEncoder().encode(BatchResponse(request_id: request.request_id, result: row, error_code: nil))
                        : try JSONEncoder().encode(row)
                    data.append(10)
                    try output.write(contentsOf: data)
                } catch {
                    guard batch || resident else { throw error }
                    var data = try JSONEncoder().encode(BatchResponse(request_id: request.request_id, result: nil, error_code: "audio_or_inference_failed"))
                    data.append(10)
                    try output.write(contentsOf: data)
                }
            }
        } catch {
            FileHandle.standardError.write(Data("Whisper smoke failed: \(error)\n".utf8))
            exit(1)
        }
    }
    static func milliseconds(_ start: ContinuousClock.Instant) -> Int {
        let d = start.duration(to: .now).components
        return Int(d.seconds * 1000 + d.attoseconds / 1_000_000_000_000_000)
    }
    struct BatchRequest: Decodable {
        let request_id: String
        let audio_path: String
    }
    struct BatchResponse: Encodable {
        let request_id: String
        let result: Result?
        let error_code: String?
    }
    enum Failure: Error { case arguments, output, tokenizer, metrics }
    struct Result: Encodable {
        let raw_text: String
        let load_ms: Int
        let transcribe_ms: Int
        let peak_rss_bytes: UInt64
        let success: Bool
    }
}
