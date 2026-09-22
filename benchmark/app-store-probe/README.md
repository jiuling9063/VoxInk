# App Store sandbox feasibility probe

An isolated macOS App Sandbox experiment. It does not change the installed VoxInk application, preferences or model cache. It is not a distributable store build and does not establish App Review acceptance.

## Run

Prerequisites: Xcode; an installed signed VoxInk 0.1.9 App; both pinned recognition and light polishing models already installed; APFS storage. Set `VOXINK_SIGN_IDENTITY` to the same signing identity as the installed runtime. No credentials are embedded in the script.

```sh
VOXINK_SIGN_IDENTITY=<certificate-SHA1> bash script/run_app_store_probe.sh
```

The script prints the App and fixtures paths. Launch the App, run 基础检查, then select its fixtures directory with the system folder picker. The picker grants read-only access; helpers inherit the App's sandbox. The probe deliberately has no network entitlement. Model fixtures are APFS copy-on-write copies, not references into the production cache.

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
