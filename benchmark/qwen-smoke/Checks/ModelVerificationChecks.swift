import Foundation

@main
struct ModelVerificationChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = root.appendingPathComponent("model")
        try FileManager.default.createDirectory(at: model, withIntermediateDirectories: true)
        let manifest = root.appendingPathComponent("manifest.json")
        let payload = Data("abc".utf8)
        let hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let requiredFiles = ["config.json", "merges.txt", "model.safetensors", "model.safetensors.index.json", "tokenizer_config.json", "vocab.json"]
        func writeManifest(revision: String = SmokeContract.modelRevision, path: String = "model.safetensors", bytes: Int = 3, sha: String? = nil) throws {
            let files: [[String: Any]] = requiredFiles.map { name in
                ["path": name == "model.safetensors" ? path : name,
                 "size_bytes": name == "model.safetensors" ? bytes : 3,
                 "sha256": name == "model.safetensors" ? (sha ?? hash) : hash]
            }
            let value: [String: Any] = ["candidates": [[
                "id": SmokeContract.engine,
                "engine": ["source_revision": SmokeContract.engineRevision],
                "model": ["repository": SmokeContract.modelID, "revision": revision,
                          "files": files]
            ]]]
            try JSONSerialization.data(withJSONObject: value).write(to: manifest)
        }
        func verify() throws -> VerifiedModel {
            try ModelVerifier.verify(manifestURL: manifest, directory: model)
        }
        func rejects(_ label: String, _ body: () throws -> Void) throws {
            do { try body() } catch { print("PASS \(label)"); return }
            throw CheckFailure.acceptedInvalidModel(label)
        }
        try writeManifest()
        try rejects("missing file") { _ = try verify() }
        for file in requiredFiles { try payload.write(to: model.appendingPathComponent(file)) }
        let verified = try verify()
        guard verified.revision == SmokeContract.modelRevision else { throw CheckFailure.wrongRevision }
        print("PASS valid bytes and revision")
        var incomplete = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [String: Any]
        var candidates = incomplete["candidates"] as! [[String: Any]]
        var modelEntry = candidates[0]["model"] as! [String: Any]
        modelEntry["files"] = (modelEntry["files"] as! [[String: Any]]).filter { $0["path"] as? String != "merges.txt" }
        candidates[0]["model"] = modelEntry
        incomplete["candidates"] = candidates
        try JSONSerialization.data(withJSONObject: incomplete).write(to: manifest)
        try rejects("incomplete manifest") { _ = try verify() }
        try writeManifest()
        try Data("abd".utf8).write(to: model.appendingPathComponent("model.safetensors"))
        try rejects("same size wrong hash") { _ = try verify() }
        try payload.write(to: model.appendingPathComponent("model.safetensors"))
        try writeManifest(revision: "wrong-revision")
        try rejects("wrong revision") { _ = try verify() }
        try writeManifest(bytes: 4)
        try rejects("wrong size") { _ = try verify() }
        try writeManifest(path: "../outside")
        try rejects("path traversal") { _ = try verify() }
        try writeManifest(sha: "not-a-hash")
        try rejects("malformed hash") { _ = try verify() }
        try writeManifest()
        try Data("extra".utf8).write(to: model.appendingPathComponent("extra.safetensors"))
        try rejects("unlisted weights") { _ = try verify() }
        try FileManager.default.removeItem(at: model.appendingPathComponent("extra.safetensors"))
        try FileManager.default.removeItem(at: model.appendingPathComponent("model.safetensors"))
        let outside = root.appendingPathComponent("outside")
        try payload.write(to: outside)
        try FileManager.default.createSymbolicLink(at: model.appendingPathComponent("model.safetensors"), withDestinationURL: outside)
        try rejects("symlink") { _ = try verify() }
        let configuration = try SmokeConfiguration.parse(arguments: ["--prepare-only", "--manifest", "/tmp/pinned.json"])
        guard configuration.manifestPath == "/tmp/pinned.json" else { throw CheckFailure.wrongRevision }
        print("PASS explicit manifest argument")
        print("All 11 model verification checks passed")
    }

    enum CheckFailure: Error {
        case acceptedInvalidModel(String)
        case wrongRevision
    }
}
