import Foundation

public enum SmokeContract {
    public static let engine = "qwen3-asr-0.6b-mlx-4bit"
    public static let engineRevision = "d603472b11c21f5fb6492e9448a04ee669d0bf64"
    public static let modelID = "aufklarer/Qwen3-ASR-0.6B-MLX-4bit"
    public static let modelRevision = "bc441bd1e4295c1f42d9879f056049a925b6e013"
    public static let language = "zh"
    public static let sampleRate = 16_000
}

public struct SmokeConfiguration: Equatable, Sendable {
    public let audioPath: String?
    public let sampleID: String
    public let deviceProfile: String
    public let prepareOnly: Bool
    public let resident: Bool
    public let batchPlan: String?
    public let manifestPath: String
    public let simplifiedOutput: Bool
    public let experimentalHotwords: Bool
    public var transcriptionContext: String? {
        simplifiedOutput ? "请使用简体中文逐字转录音频，保留英文、数字和原意，不要翻译、总结或补充内容。" : nil
    }

    public init(
        audioPath: String?,
        sampleID: String,
        deviceProfile: String,
        prepareOnly: Bool,
        manifestPath: String = "benchmark/model-manifest.json",
        batchPlan: String? = nil,
        resident: Bool = false,
        simplifiedOutput: Bool = false,
        experimentalHotwords: Bool = false
    ) {
        self.audioPath = audioPath
        self.sampleID = sampleID
        self.deviceProfile = deviceProfile
        self.prepareOnly = prepareOnly
        self.manifestPath = manifestPath
        self.batchPlan = batchPlan
        self.resident = resident
        self.simplifiedOutput = simplifiedOutput
        self.experimentalHotwords = experimentalHotwords
    }

    public static func parse(arguments: [String]) throws -> SmokeConfiguration {
        var resident = false
        var simplifiedOutput = false
        var experimentalHotwords = false
        var batchPlan: String?
        var audioPath: String?
        var sampleID = "SMOKE-QWEN-001"
        var deviceProfile = "unverified-device"
        var prepareOnly = false
        var manifestPath = "benchmark/model-manifest.json"
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--resident":
                resident = true
            case "--simplified-output":
                simplifiedOutput = true
            case "--experimental-hotwords":
                experimentalHotwords = true
            case "--batch-plan":
                batchPlan = try value(after: &index, in: arguments, option: "--batch-plan")
            case "--audio":
                audioPath = try value(after: &index, in: arguments, option: "--audio")
            case "--sample-id":
                sampleID = try value(after: &index, in: arguments, option: "--sample-id")
            case "--device-profile":
                deviceProfile = try value(after: &index, in: arguments, option: "--device-profile")
            case "--prepare-only":
                prepareOnly = true
            case "--manifest":
                manifestPath = try value(after: &index, in: arguments, option: "--manifest")
            default:
                throw SmokeConfigurationError.unknownArgument(arguments[index])
            }
            index += 1
        }

        guard !sampleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SmokeConfigurationError.emptyValue("--sample-id")
        }
        guard !deviceProfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SmokeConfigurationError.emptyValue("--device-profile")
        }
        if !prepareOnly, !resident, audioPath == nil, batchPlan == nil {
            throw SmokeConfigurationError.missingAudio
        }

        if resident && (prepareOnly || batchPlan != nil || audioPath != nil) {
            throw SmokeConfigurationError.unknownArgument("--resident cannot combine with single/batch modes")
        }
        if experimentalHotwords && (batchPlan == nil || resident || prepareOnly || simplifiedOutput) {
            throw SmokeConfigurationError.unknownArgument("--experimental-hotwords requires batch mode without other prompts")
        }
        return SmokeConfiguration(
            audioPath: audioPath,
            sampleID: sampleID,
            deviceProfile: deviceProfile,
            prepareOnly: prepareOnly,
            manifestPath: manifestPath,
            batchPlan: batchPlan,
            resident: resident,
            simplifiedOutput: simplifiedOutput,
            experimentalHotwords: experimentalHotwords
        )
    }

    private static func value(
        after index: inout Int,
        in arguments: [String],
        option: String
    ) throws -> String {
        index += 1
        guard index < arguments.count else {
            throw SmokeConfigurationError.missingValue(option)
        }
        let value = arguments[index]
        guard !value.hasPrefix("--") else {
            throw SmokeConfigurationError.missingValue(option)
        }
        return value
    }
}

public enum SmokeConfigurationError: Error, Equatable, LocalizedError {
    case emptyValue(String)
    case missingAudio
    case missingValue(String)
    case unknownArgument(String)

    public var errorDescription: String? {
        switch self {
        case .emptyValue(let option):
            "\(option) cannot be empty"
        case .missingAudio:
            "--audio is required unless --prepare-only is used"
        case .missingValue(let option):
            "missing value for \(option)"
        case .unknownArgument(let argument):
            "unknown argument: \(argument)"
        }
    }
}

public struct SmokeResult: Codable, Equatable, Sendable {
    public let runID: String
    public let sampleID: String
    public let engine: String
    public let engineVersion: String
    public let modelRevision: String
    public let deviceProfile: String
    public let language: String
    public let rawText: String
    public let loadMs: Int
    public let transcribeMs: Int
    public let peakRSSBytes: UInt64
    public let success: Bool
    public let errorCode: String?
    public let outputPolicy: String?
    public let contextTokens: Int?
    public let hotwordCount: Int?

    public init(
        runID: String,
        sampleID: String,
        engine: String,
        engineVersion: String,
        modelRevision: String,
        deviceProfile: String,
        language: String,
        rawText: String,
        loadMs: Int,
        transcribeMs: Int,
        peakRSSBytes: UInt64,
        success: Bool,
        errorCode: String?,
        outputPolicy: String? = nil,
        contextTokens: Int? = nil,
        hotwordCount: Int? = nil
    ) {
        self.runID = runID
        self.sampleID = sampleID
        self.engine = engine
        self.engineVersion = engineVersion
        self.modelRevision = modelRevision
        self.deviceProfile = deviceProfile
        self.language = language
        self.rawText = rawText
        self.loadMs = loadMs
        self.transcribeMs = transcribeMs
        self.peakRSSBytes = peakRSSBytes
        self.success = success
        self.errorCode = errorCode
        self.outputPolicy = outputPolicy
        self.contextTokens = contextTokens
        self.hotwordCount = hotwordCount
    }

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case sampleID = "sample_id"
        case engine
        case engineVersion = "engine_version"
        case modelRevision = "model_revision"
        case deviceProfile = "device_profile"
        case language
        case rawText = "raw_text"
        case loadMs = "load_ms"
        case transcribeMs = "transcribe_ms"
        case peakRSSBytes = "peak_rss_bytes"
        case success
        case errorCode = "error_code"
        case outputPolicy = "output_policy"
        case contextTokens = "context_tokens"
        case hotwordCount = "hotword_count"
    }
}

public struct ModelPreparationResult: Codable, Equatable, Sendable {
    public let status: String
    public let engine: String
    public let engineVersion: String
    public let modelID: String
    public let modelRevision: String
    public let loadMs: Int
    public let peakRSSBytes: UInt64

    public init(
        status: String,
        engine: String,
        engineVersion: String,
        modelID: String,
        modelRevision: String,
        loadMs: Int,
        peakRSSBytes: UInt64
    ) {
        self.status = status
        self.engine = engine
        self.engineVersion = engineVersion
        self.modelID = modelID
        self.modelRevision = modelRevision
        self.loadMs = loadMs
        self.peakRSSBytes = peakRSSBytes
    }

    enum CodingKeys: String, CodingKey {
        case status
        case engine
        case engineVersion = "engine_version"
        case modelID = "model_id"
        case modelRevision = "model_revision"
        case loadMs = "load_ms"
        case peakRSSBytes = "peak_rss_bytes"
    }
}

public enum JSONLineEncoder {
    public static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let line = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return line
    }
}
