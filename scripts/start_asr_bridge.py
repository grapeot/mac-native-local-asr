#!/usr/bin/env python3
"""App-facing JSONL adapter for qwen3-asr-mlx-runtime."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, help="Local Qwen3-ASR model directory")
    parser.add_argument("--local-files-only", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    model_path = Path(args.model).expanduser().resolve()
    if not model_path.is_dir():
        print(json.dumps({"type": "error", "message": "Model directory was not found"}))
        return 2

    try:
        from qwen3_asr_mlx_runtime import runtime
    except ImportError as error:
        project_python = Path(__file__).resolve().parent.parent / ".venv" / "bin" / "python"
        if project_python.is_file() and Path(sys.executable).resolve() != project_python.resolve():
            os.execv(str(project_python), [str(project_python), __file__, *sys.argv[1:]])
        print(
            json.dumps(
                {
                    "type": "error",
                    "message": (
                        "qwen3-asr-mlx-runtime is not installed in this Python "
                        f"environment: {error}"
                    ),
                }
            ),
            flush=True,
        )
        return 2

    runtime.LOG_STREAM = sys.stderr
    context = runtime.ProbeContext(
        model=str(model_path),
        cache_dir=model_path.parent,
        audio_path=None,
        language=None,
        trust_remote_code=True,
        local_files_only=args.local_files_only,
        max_new_tokens=None,
    )
    bridge = runtime.RuntimeJSONBridge(context, use_cache=True)

    for line in sys.stdin:
        try:
            request = json.loads(line)
            if request.get("type") == "transcribe" and "audio_path" in request:
                request["audio"] = request.pop("audio_path")
            response = bridge.handle(request)
        except Exception as error:
            response = {"type": "error", "message": str(error)}

        print(json.dumps(response, ensure_ascii=False), flush=True)
        if response.get("type") == "stopped":
            break

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
