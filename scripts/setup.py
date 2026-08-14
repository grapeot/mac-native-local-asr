#!/usr/bin/env python3
"""First-run setup for Mac Local ASR.

Creates a venv, installs mlx-qwen3-asr, and verifies the model is available.
Called by the Swift app on first launch (or when the user clicks "Setup").

Outputs JSONL status lines to stdout for the app to display progress:
    {"type":"progress","step":"creating_venv","message":"Creating Python environment…"}
    {"type":"progress","step":"installing","message":"Installing mlx-qwen3-asr…"}
    {"type":"progress","step":"checking_model","message":"Checking model…"}
    {"type":"done","venv_python":"/path/to/.venv/bin/python","model_id":"Qwen/Qwen3-ASR-1.7B"}
    {"type":"error","message":"..."}
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


MODEL_ID = "Qwen/Qwen3-ASR-1.7B"


def emit(obj: dict) -> None:
    print(json.dumps(obj, ensure_ascii=False), flush=True)


def find_system_python3() -> str | None:
    for candidate in ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]:
        if Path(candidate).is_file():
            result = subprocess.run(
                [candidate, "--version"], capture_output=True, text=True
            )
            if result.returncode == 0 and "Python 3." in result.stdout:
                return candidate
    return None


def check_mlx_available(python: str) -> bool:
    result = subprocess.run(
        [python, "-c", "import mlx_qwen3_asr"],
        capture_output=True, text=True
    )
    return result.returncode == 0


def main() -> int:
    install_dir = Path.home() / ".maclocalasr"
    venv_dir = install_dir / ".venv"
    venv_python = venv_dir / "bin" / "python"

    # If venv already exists and has mlx-qwen3-asr, just report ready
    if venv_python.is_file() and check_mlx_available(str(venv_python)):
        emit({"type": "done", "venv_python": str(venv_python), "model_id": MODEL_ID})
        return 0

    install_dir.mkdir(parents=True, exist_ok=True)

    # Step 1: Find system python3
    sys_python = find_system_python3()
    if not sys_python:
        emit({"type": "error", "message": "Python 3 not found. Install with: brew install python3"})
        return 1

    # Step 2: Create venv
    emit({"type": "progress", "step": "creating_venv", "message": "Creating Python environment…"})
    result = subprocess.run(
        [sys_python, "-m", "venv", str(venv_dir)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        emit({"type": "error", "message": f"Failed to create venv: {result.stderr}"})
        return 1

    # Step 3: Install mlx-qwen3-asr
    emit({"type": "progress", "step": "installing", "message": "Installing mlx-qwen3-asr (this may take a minute)…"})
    result = subprocess.run(
        [str(venv_python), "-m", "pip", "install", "--upgrade", "pip"],
        capture_output=True, text=True
    )
    result = subprocess.run(
        [str(venv_python), "-m", "pip", "install", "mlx-qwen3-asr"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        emit({"type": "error", "message": f"Failed to install mlx-qwen3-asr: {result.stderr[-500:]}"})
        return 1

    # Step 4: Verify
    if not check_mlx_available(str(venv_python)):
        emit({"type": "error", "message": "mlx-qwen3-asr installed but import failed"})
        return 1

    # Step 5: Check model (will download on first transcription if not cached)
    emit({"type": "progress", "step": "checking_model", "message": "Model will download on first use."})

    emit({"type": "done", "venv_python": str(venv_python), "model_id": MODEL_ID})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())