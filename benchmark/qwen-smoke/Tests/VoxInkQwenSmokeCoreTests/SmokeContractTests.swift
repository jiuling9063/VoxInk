import Foundation
import Testing
@Test func simplifiedOutputIsOptInAndBaselineHasNoPrompt() throws {
    #expect(try SmokeConfiguration.parse(arguments: ["--resident"]).transcriptionContext == nil)
    let app = try SmokeConfiguration.parse(arguments: ["--resident", "--simplified-output"])
    #expect(app.transcriptionContext?.contains("简体中文") == true)
}
@testable import VoxInkQwenSmokeCore

@Test func prepareOnlyDoesNotRequireAudio() throws {
    let configuration = try SmokeConfiguration.parse(arguments: ["--prepare-only"])
    #expect(configuration.prepareOnly)
    #expect(configuration.audioPath == nil)
}

@Test func transcriptionRequiresAudio() {
    #expect(throws: SmokeConfigurationError.missingAudio) {
        try SmokeConfiguration.parse(arguments: [])
    }
}

@Test func parsesExplicitEvidenceFields() throws {
    let configuration = try SmokeConfiguration.parse(arguments: [
        "--audio", "/tmp/sample.wav",
        "--sample-id", "S0001",
        "--device-profile", "m4-dev",
    ])
    #expect(configuration.audioPath == "/tmp/sample.wav")
    #expect(configuration.sampleID == "S0001")
    #expect(configuration.deviceProfile == "m4-dev")
    #expect(!configuration.prepareOnly)
}

@Test func encodesContractKeysAsJSONL() throws {
    let result = SmokeResult(
        runID: "run-1",
        sampleID: "S0001",
        engine: SmokeContract.engine,
        engineVersion: SmokeContract.engineRevision,
        modelRevision: SmokeContract.modelRevision,
        deviceProfile: "m4-dev",
        language: "zh",
        rawText: "测试",
        loadMs: 10,
        transcribeMs: 20,
        peakRSSBytes: 30,
        success: true,
        errorCode: nil
    )
    let line = try JSONLineEncoder.encode(result)
    let object = try #require(
        JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
    )
    #expect(object["model_revision"] as? String == SmokeContract.modelRevision)
    #expect(object["raw_text"] as? String == "测试")
    #expect(object["success"] as? Bool == true)
}

@Test func batchPlanDoesNotRequireSingleAudio() throws {
    let config = try SmokeConfiguration.parse(arguments: ["--batch-plan", "/tmp/plan.json"])
    #expect(config.batchPlan == "/tmp/plan.json")
    #expect(config.audioPath == nil)
    #expect(throws: SmokeConfigurationError.missingValue("--batch-plan")) {
        try SmokeConfiguration.parse(arguments: ["--batch-plan"])
    }
}

@Test func residentModeLoadsWithoutSingleAudio() throws {
    let config = try SmokeConfiguration.parse(arguments: ["--resident"])
    #expect(config.resident)
    #expect(config.audioPath == nil)
    for conflicting in [["--resident", "--prepare-only"], ["--resident", "--audio", "/tmp/a.wav"], ["--resident", "--batch-plan", "/tmp/plan.json"]] {
        #expect(throws: (any Error).self) { try SmokeConfiguration.parse(arguments: conflicting) }
    }
}
