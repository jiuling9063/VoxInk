import argparse
import json
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys

from install_polish_bundle import checksum, verify_payload


def export_bundle(configuration, output):
    if output.exists():
        raise ValueError("Output directory already exists")
    probe = subprocess.run([configuration["python"], "-I", "-c",
                            "import sys; print(sys.base_prefix)"],
                           capture_output=True, text=True, check=True, timeout=30)
    runtime = Path(probe.stdout.strip()).resolve()
    python_relative = Path(configuration["python"]).resolve().relative_to(runtime)
    output.mkdir(parents=True, mode=0o700)
    try:
        payload = output / "payload"
        shutil.copytree(runtime, payload / "python", symlinks=True,
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        shutil.copytree(configuration["model"], payload / "model", symlinks=True)
        scripts = payload / "worker"
        scripts.mkdir()
        for name in ("polish_worker.py", "polish_guard.py", "check_polish_model.py"):
            shutil.copy2(Path(configuration["worker"]).parent / name, scripts / name)
        manifest = {"format": 1, "system": sys.platform, "machine": platform.machine(),
                    "python": str(Path("python") / python_relative),
                    "worker": "worker/polish_worker.py", "model": "model", "files": {}}
        for path in sorted(payload.rglob("*")):
            name = str(path.relative_to(payload))
            if path.is_symlink():
                manifest["files"][name] = {"kind": "link", "target": os.readlink(path)}
            elif path.is_file():
                manifest["files"][name] = {"kind": "file", "sha256": checksum(path)}
        verify_payload(payload, manifest)
        (output / "manifest.json").write_text(json.dumps(manifest, indent=2))
        for name in ("install_polish_bundle.py", "setup_polish_runtime.py"):
            shutil.copy2(Path(__file__).parent / name, output / name)
        launcher = output / "安装润色组件.command"
        launcher.write_text(
            '#!/bin/bash\nset -euo pipefail\n'
            'BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"\n'
            'exec "$BUNDLE_DIR/payload/' + manifest["python"] + '" -I -B '
            '"$BUNDLE_DIR/install_polish_bundle.py" "$@"\n'
        )
        launcher.chmod(0o700)
        (output / "使用说明.txt").write_text(
            "语落离线润色组件 · 本地验收包\n\n"
            "仅用于同架构 macOS 验收，尚未完成正式签名、公证或跨机器兼容性验证。\n"
            "双击安装润色组件.command，安装器将复制并校验文件，真实推理成功后才启用新配置。\n"
            "不需要预装 Python 或 uv，不下载文件。请预留至少 6 GB 空闲空间。\n"
            "失败时保留原配置；成功后也保留旧安装，便于回退。\n"
            "请仅运行可信来源的安装包。文件哈希用于损坏检查，不代表发行方身份认证。\n"
        )
        return output
    except BaseException:
        shutil.rmtree(output)
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    config = Path.home() / "Library/Application Support/VoxInk/Polish/runtime.json"
    print(export_bundle(json.loads(config.read_text()), args.output.resolve()))
