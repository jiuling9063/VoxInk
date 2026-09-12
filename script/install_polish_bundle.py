import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from setup_polish_runtime import publish_configuration, verify_internal_links


def checksum(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def relative_path(value):
    path = Path(value)
    if not value or path.is_absolute() or ".." in path.parts or str(path) != value:
        raise ValueError("Invalid package path")
    return path


def verify_payload(payload, manifest):
    if manifest.get("format") != 1 or not manifest.get("files"):
        raise ValueError("Unsupported or empty package manifest")
    verify_internal_links(payload)
    entries = manifest["files"]
    actual = {str(path.relative_to(payload)) for path in payload.rglob("*")
              if path.is_file() or path.is_symlink()}
    if actual != set(entries):
        raise ValueError("Package file inventory mismatch")
    for name, entry in entries.items():
        path = payload / relative_path(name)
        if not path.resolve().is_relative_to(payload.resolve()):
            raise ValueError("Package path escapes payload")
        if entry.get("kind") == "link":
            if not path.is_symlink() or os.readlink(path) != entry["target"]:
                raise ValueError("Package link mismatch")
        elif entry.get("kind") == "file":
            if path.is_symlink() or checksum(path) != entry["sha256"]:
                raise ValueError("Package checksum mismatch: " + name)
        else:
            raise ValueError("Invalid package entry")
    for key in ("python", "worker", "model"):
        path = payload / relative_path(manifest[key])
        if not path.exists() or not path.resolve().is_relative_to(payload.resolve()):
            raise ValueError("Missing package component")


def smoke_test(configuration):
    source = "明天下午开会。"
    result = subprocess.run(
        ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)",
         configuration["python"], "-B", "-E", "-s", configuration["worker"], configuration["model"]],
        input=json.dumps(source), text=True, capture_output=True, check=True,
        cwd="/tmp", timeout=35,
    )
    if json.loads(result.stdout).get("text") != source:
        raise ValueError("Installed runtime did not preserve the test sentence")


def install(bundle, destination):
    manifest = json.loads((bundle / "manifest.json").read_text())
    if manifest.get("system") != sys.platform or manifest.get("machine") != platform.machine():
        raise ValueError("This package does not match this operating system or CPU architecture")
    payload = bundle / "payload"
    verify_payload(payload, manifest)
    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (destination / ".offline-install.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        versions = destination / "installations"
        versions.mkdir(exist_ok=True, mode=0o700)
        target = Path(tempfile.mkdtemp(prefix="offline-", dir=versions))
        try:
            shutil.copytree(payload, target, symlinks=True, dirs_exist_ok=True)
            verify_payload(target, manifest)
            configuration = {key: str(target / manifest[key]) for key in ("python", "worker", "model")}
            smoke_test(configuration)
            publish_configuration(destination, configuration)
            return configuration
        except BaseException:
            shutil.rmtree(target)
            raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Install the local VoxInk polish component without downloading files")
    parser.add_argument("--destination", type=Path,
                        default=Path.home() / "Library/Application Support/VoxInk/Polish")
    args = parser.parse_args()
    try:
        install(Path(__file__).resolve().parent, args.destination.resolve())
        print("润色组件已安装并通过本地推理验证。返回语落即可启用润色预览。")
    except Exception as error:
        print("安装未完成，原有配置保持不变：" + str(error), file=sys.stderr)
        raise SystemExit(1)
