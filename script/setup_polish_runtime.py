import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DESTINATION = Path.home() / "Library/Application Support/VoxInk/Polish"

if __name__ == "__main__":
    from check_polish_model import DIRECTORY

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
    configuration = {"python": str(runtime / "bin/python"), "worker": str(DESTINATION / "polish_worker.py"),
                     "model": str(DIRECTORY)}
    temporary = DESTINATION / "runtime.json.tmp"
    temporary.write_text(json.dumps(configuration))
    temporary.replace(DESTINATION / "runtime.json")
    print("Local development polish runtime installed; model remains in benchmark cache.")
