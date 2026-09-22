import AppKit
import AVFoundation
import Carbon
import Metal
import SwiftUI
import Security

@MainActor final class Probe: ObservableObject {
    @Published var lines = [String]()
    @Published var busy = false
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var audio: AVAudioRecorder?
    private var report: URL { URL.applicationSupportDirectory.appendingPathComponent("VoxInkSandboxProbe/results.txt") }
    func record(_ message: String) {
        lines.append(message)
        try? FileManager.default.createDirectory(at: report.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
    }
    func basic() {
        guard !busy else { return }
        record("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let task = SecTaskCreateFromSelf(nil)!
        let sandbox = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil)
        record("sandbox entitlement: \(String(describing: sandbox))")
        record("container home: \(NSHomeDirectory())")
        record("Metal device: \(MTLCreateSystemDefaultDevice()?.name ?? "unavailable")")
        record("microphone authorization: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (0=not determined, 3=authorized)")
        record("AX trusted: \(AXIsProcessTrusted()); event posting preflight: \(CGPreflightPostEventAccess())")
        record("Cross-app write: NOT TESTED; no input events sent and no Accessibility permission requested")
        if hotKey == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let context = Unmanaged.passUnretained(self).toOpaque()
            let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    Unmanaged<Probe>.fromOpaque(context).takeUnretainedValue().record("Carbon hotkey received")
                }
                return noErr
            }, 1, &event, context, &handler)
            let status = RegisterEventHotKey(UInt32(kVK_F18), UInt32(controlKey | optionKey | cmdKey),
                EventHotKeyID(signature: 0x56585052, id: 1), GetApplicationEventTarget(), 0, &hotKey)
            record("Carbon Ctrl+Option+Command+F18: handler=\(installed), registration=\(status)")
        }
        record("report: \(report.path)")
    }
    func modelTests() {
        guard !busy else { return }
        let chooser = NSOpenPanel()
        chooser.canChooseDirectories = true; chooser.canChooseFiles = false
        chooser.message = "选择 run_app_store_probe.sh 生成的 fixtures 目录，仅使用模型副本。"
        guard chooser.runModal() == .OK, let folder = chooser.url else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        busy = true
        Task {
            defer { if scoped { folder.stopAccessingSecurityScopedResource() }; busy = false }
            guard let resources = Bundle.main.resourceURL else { return }
            let python = resources.appendingPathComponent("PolishRuntime/bin/python3.12")
            await child("Existing sandbox-exec wrapper", executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                        arguments: ["-p", "(version 1)(allow default)(deny network*)", "/bin/echo", "wrapper-ok"])
            await child("Python + MLX GPU", executable: python, arguments: ["-B", "-E", "-s", "-c",
                "import mlx.core as mx; a=mx.array([1,2,3]); mx.eval(a); print('GPU',mx.default_device(),'SUM',mx.sum(a).item())"])
            let worker = resources.appendingPathComponent("Worker/voxink-qwen-smoke")
            var env = ProcessInfo.processInfo.environment
            env["QWEN3_CACHE_DIR"] = folder.appendingPathComponent("asr").path
            env["HF_HUB_OFFLINE"] = "1"; env["TRANSFORMERS_OFFLINE"] = "1"
            // Use a generated silent WAV only; no user audio or recognition text is logged.
            await child("ASR load + silence inference", executable: worker,
                arguments: ["--manifest", resources.appendingPathComponent("model-manifest.json").path,
                            "--audio", folder.appendingPathComponent("silence.wav").path], environment: env)
            await child("Polish load + fixed text inference", executable: python,
                arguments: ["-B", "-E", "-s", resources.appendingPathComponent("Polish/polish_worker.py").path,
                            folder.appendingPathComponent("polish").path],
                input: Data("\"今天今天我们开会。\"".utf8))
            record("Probe run complete; this is not App Store approval")
        }
    }
    func microphone() {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { record("Microphone capture blocked by permission"); return }
            let url = URL.temporaryDirectory.appendingPathComponent("probe-\(UUID()).wav")
            defer { audio?.stop(); audio = nil; try? FileManager.default.removeItem(at: url) }
            do {
                audio = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16])
                guard audio?.record() == true else { record("Microphone recorder start failed"); return }
                try await Task.sleep(for: .seconds(1))
                audio?.stop()
                let file = try AVAudioFile(forReading: url)
                record("Microphone: captured \(file.length) frames; temporary audio deleted")
            } catch { record("Microphone: \(error.localizedDescription)") }
        }
    }
    private func child(_ label: String, executable: URL, arguments: [String], environment: [String:String]? = nil, input: Data = Data()) async {
        record("START \(label)")
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: root) }
            let stdout = root.appendingPathComponent("stdout"), stderr = root.appendingPathComponent("stderr"), stdin = root.appendingPathComponent("stdin")
            try input.write(to: stdin); fm.createFile(atPath: stdout.path, contents: nil); fm.createFile(atPath: stderr.path, contents: nil)
            let out = try FileHandle(forWritingTo: stdout), err = try FileHandle(forWritingTo: stderr), source = try FileHandle(forReadingFrom: stdin)
            defer { try? out.close(); try? err.close(); try? source.close() }
            let process = Process(); process.executableURL = executable; process.arguments = arguments
            process.currentDirectoryURL = root; process.environment = environment
            process.standardOutput = out; process.standardError = err; process.standardInput = source
            let started = ContinuousClock.now
            try process.run()
            while process.isRunning && started.duration(to: .now) < .seconds(120) { try await Task.sleep(for: .milliseconds(100)) }
            if process.isRunning {
                process.terminate()
                try await Task.sleep(for: .seconds(1))
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                record("TIMEOUT \(label)")
            }
            while process.isRunning { try await Task.sleep(for: .milliseconds(50)) }
            let output = (try? String(contentsOf: stdout, encoding: .utf8)) ?? ""
            let errors = (try? String(contentsOf: stderr, encoding: .utf8)) ?? ""
            record("END \(label): exit=\(process.terminationStatus), reason=\(process.terminationReason.rawValue), time=\(started.duration(to: .now))\n\(output.prefix(3000))\n\(errors.suffix(2000))")
        } catch { record("FAIL \(label): \(error.localizedDescription)") }
    }
}
@main struct SandboxProbe: App {
    @StateObject private var probe = Probe()
    var body: some Scene {
        WindowGroup("VoxInk · App Store 沙盒验证") {
            VStack(alignment: .leading) {
                Text("独立沙盒探针 · 不修改正式 App").font(.title2)
                HStack {
                    Button("基础检查") { probe.basic() }
                    Button("选择模型副本并测试") { probe.modelTests() }
                    Button("麦克风测试（1 秒后删除）") { probe.microphone() }
                }.disabled(probe.busy)
                Text(probe.busy ? "验证中…" : "测试日志只含固定样例与状态。")
                ScrollView { Text(probe.lines.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(20).frame(minWidth: 800, minHeight: 620)
        }
    }
}
