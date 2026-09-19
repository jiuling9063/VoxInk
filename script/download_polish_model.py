"""Download pinned model files; publish readiness only after hash verification."""
import argparse
import json
from pathlib import Path

from check_polish_model import digest


def checked_path(directory, name):
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Unsafe model path")
    path = directory / relative
    if not path.resolve().is_relative_to(directory.resolve()):
        raise ValueError("Model path escapes installation")
    return path


def install(repository, revision, directory):
    from huggingface_hub import HfApi, snapshot_download

    if len(revision) != 40 or any(c not in "0123456789abcdef" for c in revision):
        raise ValueError("Expected immutable revision")
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    ready = directory / "verified.json"
    info = HfApi().model_info(repository, revision=revision, files_metadata=True, timeout=30)
    if info.sha != revision:
        raise ValueError("Revision mismatch")
    # Keep partial downloads resumable, but never expose them to inference.
    ready.unlink(missing_ok=True)
    for entry in info.siblings:
        path = checked_path(directory, entry.rfilename)
        expected = entry.lfs.sha256 if entry.lfs else entry.blob_id
        if path.exists() and (path.stat().st_size != entry.size or
                              digest(path, "sha256" if entry.lfs else "sha1") != expected):
            # Hub metadata may still call a locally corrupted file current.
            path.unlink()
    snapshot_download(repository, revision=revision, local_dir=directory, max_workers=2)
    manifest = []
    for entry in info.siblings:
        path = checked_path(directory, entry.rfilename)
        if path.stat().st_size != entry.size:
            raise ValueError("Size mismatch")
        expected = entry.lfs.sha256 if entry.lfs else entry.blob_id
        actual = digest(path, "sha256" if entry.lfs else "sha1")
        if actual != expected:
            raise ValueError("Hash mismatch")
        manifest.append({"file": entry.rfilename, "sha256": digest(path, "sha256")})
    names = {entry["file"] for entry in manifest}
    if not {"config.json", "tokenizer.json"}.issubset(names) or not any(n.endswith(".safetensors") for n in names):
        raise ValueError("Incomplete model")
    temporary = directory / "verified.json.tmp"
    temporary.write_text(json.dumps(manifest, indent=2))
    temporary.replace(ready)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("repository")
    parser.add_argument("revision")
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    install(args.repository, args.revision, args.directory)
