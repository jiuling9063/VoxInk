import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = Path.home() / "Library/Application Support/VoxInk/Polish"


def verify_model(directory):
    manifest = json.loads((directory / "verified.json").read_text())
    if not isinstance(manifest, list) or not manifest:
        raise ValueError("Empty model manifest")
    names = set()
    for entry in manifest:
        name = entry["file"]
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts or name in names:
            raise ValueError("Unsafe model manifest")
        names.add(name)
        path = directory / relative
        if not path.resolve().is_relative_to(directory.resolve()):
            raise ValueError("Model file escapes directory")
        with path.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != entry["sha256"]:
            raise ValueError("Model checksum mismatch")
    if not {"config.json", "tokenizer.json"}.issubset(names) or not any(
        name.endswith(".safetensors") for name in names
    ):
        raise ValueError("Incomplete model manifest")
    return manifest


def migrate_model(source, destination):
    manifest = verify_model(source)
    models = destination / "models"
    models.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = models / source.name
    if target.exists():
        if verify_model(target) != manifest:
            raise ValueError("Installed model differs from source")
        return target
    with tempfile.TemporaryDirectory(prefix=".install-", dir=models) as staging:
        staged = Path(staging) / source.name
        staged.mkdir(mode=0o700)
        for entry in manifest:
            relative = Path(entry["file"])
            copied = staged / relative
            copied.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / relative, copied)
        shutil.copyfile(source / "verified.json", staged / "verified.json")
        verify_model(staged)
        staged.rename(target)
    return target


def publish_configuration(destination, configuration):
    with tempfile.NamedTemporaryFile(mode="w", dir=destination, delete=False) as stream:
        temporary = Path(stream.name)
        try:
            json.dump(configuration, stream)
            stream.flush()
            temporary.replace(destination / "runtime.json")
        finally:
            temporary.unlink(missing_ok=True)


def verify_internal_links(directory):
    root = directory.resolve()
    for path in directory.rglob("*"):
        if path.is_symlink() and not path.resolve().is_relative_to(root):
            raise ValueError("Runtime symlink escapes installation: " + str(path.relative_to(directory)))


def migrate_python(configuration, destination):
    probe = subprocess.run(
        [configuration["python"], "-I", "-c",
         "import json,sys,sysconfig; print(json.dumps(dict(base=sys.base_prefix, "
         "site=sysconfig.get_path('purelib'), version=f'{sys.version_info.major}.{sys.version_info.minor}')))"],
        check=True, capture_output=True, text=True, timeout=30,
    )
    info = json.loads(probe.stdout)
    base = Path(info["base"]).resolve()
    site = Path(info["site"]).resolve()
    runtimes = destination / "runtimes"
    runtimes.mkdir(parents=True, exist_ok=True, mode=0o700)
    target = runtimes / ("python-" + info["version"] + "-" + uuid.uuid4().hex)
    try:
        shutil.copytree(base, target, symlinks=True)
        copied_site = target / "lib" / ("python" + info["version"]) / "site-packages"
        shutil.copytree(site, copied_site, symlinks=True, dirs_exist_ok=True)
        verify_internal_links(target)
        python = target / "bin" / ("python" + info["version"])
        checked = subprocess.run(
            [str(python), "-I", "-c",
             "import sys,json,ssl,sqlite3,mlx.core,mlx_lm,transformers,tokenizers; "
             "print(json.dumps(dict(base=sys.base_prefix, paths=sys.path)))"],
            check=True, capture_output=True, text=True, timeout=60, cwd="/tmp",
        )
        loaded = json.loads(checked.stdout)
        if Path(loaded["base"]).resolve() != target.resolve() or any(
            not Path(path).resolve().is_relative_to(target.resolve()) for path in loaded["paths"]
        ):
            raise ValueError("Copied interpreter still references external Python paths")
        result = subprocess.run(
            ["/usr/bin/sandbox-exec", "-p", "(version 1)(allow default)(deny network*)",
             str(python), configuration["worker"], configuration["model"]],
            input=json.dumps("明天下午开会。"), capture_output=True, text=True,
            check=True, timeout=35, cwd="/tmp",
        )
        response = json.loads(result.stdout)
        if response.get("text") != "明天下午开会。":
            raise ValueError("Runtime smoke test did not preserve the test sentence")
        return python
    except BaseException:
        if target.exists():
            shutil.rmtree(target)
        raise


if __name__ == "__main__":
    from check_polish_model import DIRECTORY

    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--migrate-python-only", action="store_true",
                       help="Copy the current interpreter and dependencies into product storage, offline")
    modes.add_argument("--migrate-model-only", action="store_true",
                        help="Reuse the installed runtime and migrate verified weights without network access")
    args = parser.parse_args()
    if args.migrate_python_only:
        configuration = json.loads((DESTINATION / "runtime.json").read_text())
        python = migrate_python(configuration, DESTINATION)
        configuration["python"] = str(python)
        publish_configuration(DESTINATION, configuration)
        print("Independent Python runtime verified and activated in Application Support.")
        raise SystemExit(0)
    if args.migrate_model_only:
        configuration = json.loads((DESTINATION / "runtime.json").read_text())
        target = migrate_model(Path(configuration["model"]), DESTINATION)
        configuration["model"] = str(target)
        publish_configuration(DESTINATION, configuration)
        print("Verified model installed in Application Support; runtime configuration updated.")
        raise SystemExit(0)

    if not (DIRECTORY / "verified.json").is_file():
        raise SystemExit("Download and verify the model with check_polish_model.py --download first")
    DESTINATION.mkdir(parents=True, exist_ok=True, mode=0o700)
    runtime = DESTINATION / "venv"
    if not (runtime / "bin/python").exists():
        subprocess.run(["uv", "venv", str(runtime), "--python", "3.12"], check=True)
    subprocess.run(["uv", "pip", "install", "--python", str(runtime / "bin/python"),
                    "-r", str(ROOT / "benchmark/polish-requirements.txt")], check=True)
    for name in ["polish_worker.py", "polish_guard.py", "check_polish_model.py"]:
        shutil.copy2(ROOT / "script" / name, DESTINATION / name)
    model = migrate_model(DIRECTORY, DESTINATION)
    configuration = {"python": str(runtime / "bin/python"), "worker": str(DESTINATION / "polish_worker.py"),
                     "model": str(model)}
    configuration["python"] = str(migrate_python(configuration, DESTINATION))
    publish_configuration(DESTINATION, configuration)
    print("Independent polish runtime and verified weights configured in Application Support.")
