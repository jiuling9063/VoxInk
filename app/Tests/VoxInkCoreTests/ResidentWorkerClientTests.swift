import Foundation
import Testing
@testable import VoxInkCore

private let fixture = #"""
import json,os,sys,time,signal
mode=sys.argv[1]
if mode=='timeout': time.sleep(30)
if mode=='exit': sys.exit(7)
if mode=='invalidready':
 print(json.dumps(dict(type='ready',protocol_version=1,pid=-1,load_ms=-10)),flush=True)
 time.sleep(30)
print(json.dumps(dict(type='ready',protocol_version=1,pid=os.getpid(),load_ms=12)),flush=True)
for line in sys.stdin:
 r=json.loads(line)
 if mode=='eof': sys.exit(0)
 if mode=='malformed':
  print(json.dumps(dict(request_id=r['request_id'])),flush=True)
  continue
 if r['sample_id']=='missing':
  print(json.dumps(dict(request_id=r['request_id'],result=None,error_code='audio_not_found')),flush=True)
  continue
 if mode=='slow':
  signal.signal(signal.SIGTERM,signal.SIG_IGN)
  time.sleep(30)
 if mode=='stale':
  print(json.dumps(dict(request_id='00000000-0000-0000-0000-000000000000',result=dict(raw_text='STALE',success=True))),flush=True)
 print(json.dumps(dict(request_id=r['request_id'],result=dict(raw_text=r['sample_id'],success=True,load_ms=12,transcribe_ms=3,peak_rss_bytes=100,extra='ignored'),error_code=None)),flush=True)
"""#

private func start(_ client: ResidentWorkerClient, mode: String = "normal", timeout: Duration = .seconds(3)) async throws -> WorkerReady {
    try await client.start(executable: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-u", "-c", fixture, mode], readyTimeout: timeout)
}

@Test func residentReusesProcessAndIgnoresStaleIDs() async throws {
    let client = ResidentWorkerClient()
    let ready = try await start(client, mode: "stale")
    for sample in ["SMOKE-001", "SMOKE-002"] {
        let result = try await client.transcribe(sampleID: sample, audioPath: "/tmp/test.wav")
        #expect(result.rawText == sample)
        #expect(result.transcribeMS == 3)
        #expect(await client.readyInfo?.pid == ready.pid)
    }
    await client.shutdown()
    #expect(await client.readyInfo == nil)
}

@Test func residentCancellationReapsAndAllowsRestart() async throws {
    let client = ResidentWorkerClient()
    let old = try await start(client, mode: "slow")
    let pending = Task { try await client.transcribe(sampleID: "old", audioPath: "/tmp/test.wav") }
    try await Task.sleep(for: .milliseconds(150))
    await #expect(throws: ResidentWorkerError.busy) {
        try await client.transcribe(sampleID: "duplicate", audioPath: "/tmp/test.wav")
    }
    await client.cancel()
    await #expect(throws: ResidentWorkerError.cancelled) { try await pending.value }
    #expect(kill(Int32(old.pid), 0) == -1)
    let new = try await start(client)
    #expect(new.pid != old.pid)
    let result = try await client.transcribe(sampleID: "new", audioPath: "/tmp/test.wav")
    #expect(result.rawText == "new")
    await client.shutdown()
}

@Test func residentTimeoutAndEarlyExit() async throws {
    let client = ResidentWorkerClient()
    await #expect(throws: ResidentWorkerError.timeout) {
        try await start(client, mode: "timeout", timeout: .milliseconds(100))
    }
    await client.shutdown()
    await #expect(throws: ResidentWorkerError.self) { try await start(client, mode: "exit") }
    await client.shutdown()
}

@Test func residentErrorEnvelopePreservesProcess() async throws {
    let client = ResidentWorkerClient()
    let ready = try await start(client)
    await #expect(throws: ResidentWorkerError.worker("audio_not_found")) {
        try await client.transcribe(sampleID: "missing", audioPath: "/missing.wav")
    }
    let result = try await client.transcribe(sampleID: "recovered", audioPath: "/tmp/test.wav")
    #expect(result.rawText == "recovered")
    #expect(await client.readyInfo?.pid == ready.pid)
    await client.shutdown()
    #expect(kill(Int32(ready.pid), 0) == -1)
}

@Test func residentRequestTimeoutAndEOF() async throws {
    let client = ResidentWorkerClient()
    _ = try await start(client, mode: "slow")
    await #expect(throws: ResidentWorkerError.timeout) {
        try await client.transcribe(sampleID: "slow", audioPath: "/tmp/test.wav", timeout: .milliseconds(100))
    }
    _ = try await start(client, mode: "eof")
    await #expect(throws: ResidentWorkerError.exited) {
        try await client.transcribe(sampleID: "eof", audioPath: "/tmp/test.wav")
    }
    await client.shutdown()
}

@Test func residentTaskCancellationAndLaunchFailure() async throws {
    let client = ResidentWorkerClient()
    await #expect(throws: (any Error).self) {
        try await client.start(executable: URL(fileURLWithPath: "/nonexistent-worker"), arguments: [])
    }
    let ready = try await start(client, mode: "slow")
    let pending = Task { try await client.transcribe(sampleID: "cancel", audioPath: "/tmp/test.wav") }
    try await Task.sleep(for: .milliseconds(100))
    pending.cancel()
    await #expect(throws: ResidentWorkerError.cancelled) { try await pending.value }
    #expect(kill(Int32(ready.pid), 0) == -1)
    await client.shutdown()
}

@Test func residentRejectsInvalidReadyMetadata() async throws {
    let client = ResidentWorkerClient()
    await #expect(throws: ResidentWorkerError.invalidProtocol) {
        try await start(client, mode: "invalidready")
    }
    await client.shutdown()
}

@Test func residentRoutesDiagnosticsSeparately() async throws {
    let client = ResidentWorkerClient()
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    FileManager.default.createFile(atPath: destination.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: destination) }
    let handle = try FileHandle(forWritingTo: destination)
    defer { try? handle.close() }
    _ = try await client.start(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                               arguments: ["-u", "-c", "import sys; print('worker diagnostic',file=sys.stderr,flush=True);\n" + fixture, "normal"],
                               standardError: handle)
    await client.shutdown()
    #expect(try String(contentsOf: destination, encoding: .utf8).contains("worker diagnostic"))
}

@Test func residentMalformedEnvelopeInvalidatesProcess() async throws {
    let client = ResidentWorkerClient()
    let ready = try await start(client, mode: "malformed")
    await #expect(throws: ResidentWorkerError.invalidProtocol) {
        try await client.transcribe(sampleID: "malformed", audioPath: "/tmp/test.wav")
    }
    #expect(await client.readyInfo == nil)
    #expect(kill(Int32(ready.pid), 0) == -1)
    await client.shutdown()
}

@Test func residentInheritsParentEnvironmentByDefault() async throws {
    let client = ResidentWorkerClient()
    let home = try #require(ProcessInfo.processInfo.environment["HOME"])
    _ = try await client.start(executable: URL(fileURLWithPath: "/usr/bin/python3"),
                               arguments: ["-u", "-c", "import os,sys; assert os.environ.get('HOME') == sys.argv[2]\n" + fixture, "normal", home])
    await client.shutdown()
}
