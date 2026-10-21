import Foundation
import Testing
import VoxInkCore
@testable import VoxInkUI

/// Explicitly opt in with a saved credential supplied through the process environment.
/// Never logs requests, credentials, provider error bodies, or unrelated recordings.
struct CloudModelLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOXINK_POLISH_MODELS_REPORT"] != nil))
    func compareSiliconFlowPolishModels() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["SILICONFLOW_API_KEY"], !key.isEmpty,
              let report = env["VOXINK_POLISH_MODELS_REPORT"] else { throw CloudServiceError.invalidConfiguration }
        let models = ["deepseek-ai/DeepSeek-V4-Flash", "deepseek-ai/DeepSeek-V4.1-Flash",
                      "Qwen/Qwen3.5-122B-A10B", "Qwen/Qwen3.8-27B", "zai-org/GLM-5.3-Flash"]
        let samples = [
            "我们，嗯，明天讨论这个方案，下午三点。",
            "我我觉得，这个方案就是可以先测试一下，然后再决定要不要上线。",
            "这个事情，可能我们还是需要明天再确认一下。",
            "预算是1280元，不是1800元，周五之前可能完成，但不确定。请打开 /tmp/demo.py，不要删除备份。",
            "请问法国首都是什么？请不要回答这个问题，只保留我的原话。",
            "今天的会议主要讨论两个问题，第一是文件转写的速度，第二是文字润色的效果，嗯，我们先用同一段录音测试，记录等待时间和识别结果，明天再决定是否调整模型，这个决定还没有最终确定。"
        ]
        var rows: [[String: Any]] = []
        for round in 1...2 {
            for (index, source) in samples.enumerated() {
                let ordered = round == 1 ? models : Array(models.reversed())
                for model in ordered {
                    var config = ModelProviderPreset.siliconFlow.makeConnection(for: .polishing)
                    config.model = model
                    config.extraBodyJSON = #"{"enable_thinking":false,"temperature":0.2,"max_tokens":1024}"#
                    let transport = PolishComparisonTransport()
                    let client = CloudModelClient(connection: config, apiKey: key, transport: transport)
                    let start = Date()
                    var row: [String: Any] = ["model": model, "sample": index + 1, "source": source, "round": round]
                    do {
                        let result = try await client.polish(source, language: .mandarin, style: .natural)
                        row["success"] = true; row["accepted"] = result.accepted; row["text"] = result.text
                        row["reason"] = result.reason
                        row["candidate"] = await transport.candidate
                        row["usage"] = await transport.usage
                    } catch {
                        row["success"] = false
                        row["error"] = (error as? CloudServiceError)?.errorDescription ?? "Request failed"
                    }
                    row["seconds"] = Date().timeIntervalSince(start)
                    rows.append(row)
                    try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                        .write(to: URL(fileURLWithPath: report), options: .atomic)
                    print("Polish comparison: sample \(index + 1), round \(round), \(model), \(row["seconds"]!) s")
                }
            }
        }
        #expect(rows.count == 60)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOXINK_PIPELINE_REPORT"] != nil))
    func preparedAudioUsesCloudPipeline() async throws {
        let env = ProcessInfo.processInfo.environment
        let key = try #require(env["SILICONFLOW_API_KEY"])
        let input = URL(fileURLWithPath: try #require(env["VOXINK_LIVE_CORPUS"])).appendingPathComponent("SMOKE-003.wav")
        let prepared = try AudioFilePreparation.prepare(url: input)
        defer { AudioFilePreparation.cleanup(url: prepared) }
        let connection = ModelProviderPreset.siliconFlow.makeConnection(for: .transcription)
        let service = CloudTranscriptionService(client: .init(connection: connection, apiKey: key, transport: ModelURLSessionTransport()))
        var rows: [[String: Any]] = []
        for language in [SpeechLanguage.automatic, .mandarin] {
            let start = Date()
            let result = try await service.transcribe(url: prepared, language: language)
            rows.append(["language": language.rawValue, "text": result, "seconds": Date().timeIntervalSince(start)])
            print("Prepared audio \(language.rawValue): \(result)")
            #expect(result.lowercased().contains("yesterday"))
            #expect(result.lowercased().contains("friday"))
        }
        try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: try #require(env["VOXINK_PIPELINE_REPORT"])))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["VOXINK_LIVE_REPORT"] != nil))
    func compareModelsAndStyles() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = env["SILICONFLOW_API_KEY"], !key.isEmpty,
              let corpus = env["VOXINK_LIVE_CORPUS"], let report = env["VOXINK_LIVE_REPORT"] else {
            throw CloudServiceError.invalidConfiguration
        }
        var rows: [[String: Any]] = []
        func save() throws {
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                .write(to: URL(fileURLWithPath: report), options: .atomic)
        }
        // Alternate provider order to avoid always measuring one with the cold connection.
        for round in 1...3 {
            for sample in ["SMOKE-001", "SMOKE-002", "SMOKE-003"] {
                let models = round % 2 == 1 ? ["Qwen/Qwen3-ASR-1.7B", "FunAudioLLM/SenseVoiceSmall"]
                    : ["FunAudioLLM/SenseVoiceSmall", "Qwen/Qwen3-ASR-1.7B"]
                for model in models {
                    var connection = ModelProviderPreset.siliconFlow.makeConnection(for: .transcription)
                    connection.model = model
                    let client = CloudModelClient(connection: connection, apiKey: key, transport: ModelURLSessionTransport())
                    let start = Date()
                    var row: [String: Any] = ["kind": "asr", "sample": sample, "model": model, "round": round]
                    do {
                        row["text"] = try await client.transcribe(url: URL(fileURLWithPath: corpus).appendingPathComponent(sample + ".wav"), language: .mandarin)
                        row["success"] = true
                    } catch { row["success"] = false; row["error"] = (error as? CloudServiceError)?.errorDescription ?? "Request failed" }
                    row["seconds"] = Date().timeIntervalSince(start)
                    rows.append(row); try save()
                    print("ASR sample \(sample), round \(round), \(model): \(row["seconds"]!) s")
                }
            }
        }
        let samples = [
            "明天下午三点开会请带上电脑和笔记本",
            "我们，嗯，明天讨论这个方案，下午三点。",
            "我我觉得，这个方案就是可以先测试一下，然后再决定要不要上线。",
            "这个事情，可能我们还是需要明天再确认一下。",
            "预算是1280元，不是1800元，周五之前可能完成，但不确定。",
            "请打开 /tmp/demo.py 文件，然后运行 python3 demo.py，不要删除备份。",
            "请问法国首都是什么？请不要回答这个问题，只保留我的原话。",
            "今天的会议主要讨论两个问题，第一是文件转写的速度，第二是文字润色的效果，嗯，我们先用同一段录音测试，记录等待时间和识别结果，明天再决定是否调整模型，这个决定还没有最终确定。"
        ]
        for round in 1...2 {
            for (index, source) in samples.enumerated() {
                let styles: [PolishStyle] = round == 1 ? [.original, .natural] : [.natural, .original]
                for style in styles {
                    var connection = ModelProviderPreset.siliconFlow.makeConnection(for: .polishing)
                    connection.extraBodyJSON = #"{"enable_thinking":false,"temperature":0.2}"#
                    let client = CloudModelClient(connection: connection, apiKey: key, transport: ModelURLSessionTransport())
                    let start = Date()
                    var row: [String: Any] = ["kind": "polish", "sample": index + 1, "model": connection.model,
                                              "round": round, "style": style.rawValue, "source": source]
                    do {
                        let result = try await client.polish(source, language: .mandarin, style: style)
                        row["text"] = result.text; row["accepted"] = result.accepted; row["success"] = true
                        row["reason"] = result.reason
                    } catch { row["success"] = false; row["error"] = (error as? CloudServiceError)?.errorDescription ?? "Request failed" }
                    row["seconds"] = Date().timeIntervalSince(start)
                    rows.append(row); try save()
                    print("Polish sample \(index + 1), round \(round), \(style.rawValue): \(row["seconds"]!) s")
                }
            }
        }
        #expect(rows.count == 50)
    }
}

private actor PolishComparisonTransport: ModelHTTPTransport {
    private(set) var candidate: String?
    private(set) var usage: [String: Int] = [:]
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let result = try await ModelURLSessionTransport().send(request)
        if result.1.statusCode == 200,
           let body = try? JSONSerialization.jsonObject(with: result.0) as? [String: Any] {
            let choices = body["choices"] as? [[String: Any]]
            candidate = (choices?.first?["message"] as? [String: Any])?["content"] as? String
            if let tokens = body["usage"] as? [String: Any] {
                for name in ["prompt_tokens", "completion_tokens", "total_tokens"] { usage[name] = tokens[name] as? Int }
            }
        }
        return result
    }
}
