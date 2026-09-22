"""Read-only VoxInk bundle preflight; passing is not App Review approval."""
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess

from bundle_polish_runtime import audit_dependencies, native_files


def record(name, status, detail):
    return {"check": name, "status": status, "detail": detail}


def metadata_checks(info, entitlements, signing):
    checks = []
    def nonempty_string(key):
        value = info.get(key)
        return isinstance(value, str) and bool(value.strip())
    def check(name, passed, detail):
        checks.append(record(name, "PASS" if passed else "FAIL", detail))
    check("app-sandbox", entitlements.get("com.apple.security.app-sandbox") is True,
          "Main app must enable App Sandbox for Mac App Store distribution.")
    check("distribution-signature", any(line.startswith(("Authority=Apple Distribution:",
          "Authority=3rd Party Mac Developer Application:")) for line in signing.splitlines()),
          "Developer ID/ad-hoc signatures are not Mac App Store distribution signatures.")
    check("debug-entitlement", not any(entitlements.get(key) for key in
          ("com.apple.security.get-task-allow", "get-task-allow")), "Distribution must not allow debugger attachment.")
    check("microphone-description", nonempty_string("NSMicrophoneUsageDescription"),
          "Microphone usage description must be present.")
    check("version", all(nonempty_string(key) for key in
          ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "LSMinimumSystemVersion")),
          "Bundle identity, version, build and deployment target must be present.")
    check("interface-languages", {"zh-Hans", "zh-Hant", "en", "ja", "ko"}.issubset(info.get("CFBundleLocalizations", [])),
          "Project's five declared interface languages must be present.")
    return checks


def version_tuple(value):
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * max(0, 3 - len(parts))


def inspect(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    signing = subprocess.run(["/usr/bin/codesign", "-dv", "--verbose=4", str(app)],
                             capture_output=True, text=True, timeout=30)
    entitlement_result = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(app)],
                                        capture_output=True, timeout=30)
    entitlements = plistlib.loads(entitlement_result.stdout) if entitlement_result.stdout else {}
    checks = metadata_checks(info, entitlements, signing.stderr)
    verification = subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)],
                                  capture_output=True, text=True, timeout=120)
    checks.append(record("signature-integrity", "PASS" if verification.returncode == 0 else "FAIL",
                         verification.stderr.strip() or "Deep/strict verification passed."))
    executable = app / "Contents/MacOS" / info.get("CFBundleExecutable", "")
    checks.append(record("main-executable", "PASS" if executable.is_file() else "FAIL", str(executable)))
    binaries = list(native_files(app))
    try:
        audit_dependencies(binaries)
        checks.append(record("native-dependencies", "PASS", f"{len(binaries)} native files: no non-system absolute dependency."))
    except (ValueError, subprocess.CalledProcessError) as error:
        checks.append(record("native-dependencies", "FAIL", str(error)))
    minimum = version_tuple(info.get("LSMinimumSystemVersion", "0"))
    incompatible, unknown = [], []
    for binary in binaries:
        result = subprocess.run(["/usr/bin/xcrun", "vtool", "-show-build", str(binary)],
                                capture_output=True, text=True, timeout=30)
        versions = re.findall(r"\bminos\s+([\d.]+)", result.stdout)
        if result.returncode != 0 or not versions:
            unknown.append(str(binary.relative_to(app)))
        elif any(version_tuple(version) > minimum for version in versions):
            incompatible.append({"file": str(binary.relative_to(app)), "minimums": versions})
    checks.append(record("native-minimum-os", "FAIL" if incompatible else "MANUAL" if unknown else "PASS",
                         {"declared": info.get("LSMinimumSystemVersion"), "incompatible": incompatible, "unknown": unknown}))
    for relative in ("Worker/voxink-qwen-smoke", "PolishRuntime/bin/python3.12"):
        child = app / "Contents/Resources" / relative
        result = subprocess.run(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(child)],
                                capture_output=True, timeout=30)
        child_entitlements = plistlib.loads(result.stdout) if result.stdout else {}
        inherited = all(child_entitlements.get(key) is True for key in
                        ("com.apple.security.app-sandbox", "com.apple.security.inherit"))
        offline = entitlements.get("com.apple.security.network.client") is not True
        checks.append(record("offline-inherited-helper:" + relative, "PASS" if inherited and offline else "FAIL",
                             "Project's proposed store architecture needs signed sandbox-inheriting helpers and an offline parent."))
    checks.append(record("provisioning-and-upload", "MANUAL",
                         {"embedded_profile_present": (app / "Contents/embedded.provisionprofile").exists(),
                          "remaining": "Validate registered App ID, capabilities, distribution profile if required, archive/upload and TestFlight."}))
    return {"app": str(app), "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion"),
            "checks": checks, "scope": "Static project preflight only; excludes runtime sandbox behavior, App Review approval and TestFlight."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    report = inspect(args.app.resolve())
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if any(item["status"] == "FAIL" for item in report["checks"]) else 0


if __name__ == "__main__":
    raise SystemExit(main())
