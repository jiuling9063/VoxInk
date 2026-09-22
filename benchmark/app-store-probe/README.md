# App Store sandbox feasibility probe

An isolated macOS App Sandbox experiment. It does not change the installed VoxInk application, preferences or model cache. It is not a distributable store build and does not establish App Review acceptance.

## Run

Prerequisites: Xcode; an installed signed VoxInk 0.1.9 or newer App; both pinned recognition and light polishing models already installed; APFS storage. Set `VOXINK_SIGN_IDENTITY` to the same signing identity as the installed runtime. No credentials are embedded in the script.

```sh
VOXINK_SIGN_IDENTITY=<certificate-SHA1> bash script/run_app_store_probe.sh
```

The script prints the App and fixtures paths. Launch the App, run 基础检查, then select its fixtures directory with the system folder picker. The picker grants read-only access; helpers inherit the App's sandbox. The main App deliberately has no network entitlement; only the separate download XPC service has network.client. Model fixtures are APFS copy-on-write copies, not references into the production cache.

The experiment checks:

- Live sandbox entitlement, container home, Metal device, existing permission state.
- Carbon hotkey registration (Control+Option+Command+F18). Actual delivery must also be tested on a physical keyboard while another app is active; successful registration alone is not enough.
- The existing sandbox-exec wrapper versus directly spawned, signed helpers with sandbox inheritance.
- Bundled Python/MLX GPU arithmetic, recognition model loading and silent-audio inference, fixed-text polishing generation.
- Optional one-second microphone capture, deleted immediately. No recorded microphone content is used for inference or uploaded.

The probe never posts keyboard events, reads arbitrary applications' accessibility content, or requests Accessibility permission. Cross-app automatic insertion remains unverified; false AX/event preflight values without permission cannot by themselves prove a sandbox restriction.

Logs live inside the probe's container at `Library/Application Support/VoxInkSandboxProbe/results.txt`. Temporary process outputs are removed after each test; each helper has a 120-second timeout. Model fixtures and the probe App remain in the printed `/tmp/voxink-store-probe.*` directory for review.

## Interpretation

A silent input should return `empty_transcript`; this proves execution, not recognition accuracy. A polish result rejected by the guard still proves execution, not acceptable output quality. Review the output of each test, not only the process exit code.

Recorded evidence: `evidence/2026-09-22-macos27-m5.txt`. Test host: Apple M5, macOS 27.0 build 26A428. Repeat on supported stable macOS releases before claiming compatibility. The existing audio-input entitlement worked on this host; final store entitlements must also be reconciled with Apple's current sandbox microphone guidance.

## Download isolation and persistence

Click 模型下载隔离检查. The main App creates a private partial file in its own container and passes a **write-only file descriptor** to its embedded `DownloadProbe.xpc`. The service downloads only the pinned recognition model's 7,187-byte `config.json`, using the manifest's revision, size and SHA-256. Its interface accepts no URL, output path or upload payload. HTTPS requests and redirects are restricted to `huggingface.co`. Data is size-bounded and verified in both processes before the main App publishes it atomically.

Review all three checks: main-process loopback connect denied before and after download, XPC sandbox/network entitlements reported, inherited Python loopback connect denied with exit 0. A successful transfer alone is insufficient. Quit and reopen the App, then click 读取已下载样例 to verify the persisted file without another network request. Preserve `results.txt` before restarting: logs are per-run.

This is a small config transfer, **not** full model installation: multi-GB streaming/resume, full-model recovery, peer validation hardening, old-cache migration, and integrated production inference remain unimplemented. A connection-owned task now cancels when XPC is invalidated/interrupted. Cancellation and URLSession failure behavior have deterministic offline tests; real connection invalidation during a long network transfer still needs integration coverage. The loopback check demonstrates tested socket denial; it is not a complete audit of every possible IPC/network path.

After a successful download, click 只读目标失败检查. It passes the verified file to XPC as a read-only descriptor, requires an EBADF error and verifies that its bytes remain unchanged. Click 模型下载隔离检查 again to verify recovery using a new connection. Evidence: `evidence/2026-09-22-failure-recovery.txt`.

## System Services insertion sample

```sh
VOXINK_SIGN_IDENTITY=<certificate-SHA1> bash script/build_services_probe.sh
```

Launch the printed `VoxInkServicesProbe.app`. Create an empty, disposable TextEdit document and use **文本编辑 → 服务 → VoxInk 插入测试文字**. The sample returns a fixed sentence through the service-specific pasteboard. It does not use the general pasteboard, AX APIs, synthetic key events, microphone or network. The system inserts the result into the receiving text view. Its separate sandbox container stores the callback's entitlement report at `Library/Application Support/VoxInkServicesProbe/results.txt`.

The service is a menu action advertised through `NSServices`, not a global hold/release shortcut. Availability depends on the receiving app/control's Services support. Real recording, asynchronous recognition, cancellation, web/custom controls and remote sessions are not covered. Successful insertion into TextEdit neither proves arbitrary-app input nor App Review acceptance. LaunchServices may retain the temporary sample's service entry; unregister this test bundle after the experiment when cleaning up.

## Automated checks and evidence

```sh
bash script/test_app_store_probe.sh
```

Runs 17 offline contract checks (correct data, tampering, truncation, oversized data, unsafe destinations, invalid metadata), 13 URLProtocol/task lifecycle scenarios (HTTP errors, offline, timeout, corruption, truncation, overflow, cancellation, retry, read-only descriptor, duplicate request and invalidated connection), plus Swift 6 type checks for all three executables and shell syntax checks. No model download or UI automation runs in this command.

Third-round live evidence: `evidence/2026-09-22-download-services.txt`; fixed TextEdit output: `evidence/services-textedit.rtf`. These experiments use Developer ID signatures on a beta OS; they are not Mac App Store archives.

References: [XPC privilege separation](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html), [Services provider methods](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html), [Services property list](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/properties.html).
