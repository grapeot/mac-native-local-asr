#!/usr/bin/env python3
"""Minimal JSONL bridge for Qwen3-ASR on Apple Silicon via mlx-qwen3-asr.

Protocol (newline-delimited JSON over stdin/stdout):

    App → Bridge:
        {"type": "start"}
        {"type": "transcribe", "audio_path": "/tmp/utterance.wav"}
        {"type": "stop"}

    Bridge → App:
        {"type": "ready"}
        {"type": "transcript", "text": "..."}
        {"type": "error", "message": "..."}
        {"type": "stopped"}

Stderr is for diagnostics only — never mixed into the JSONL stream.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--model",
        required=True,
        help="HuggingFace model ID or local path (e.g. Qwen/Qwen3-ASR-1.7B)",
    )
    parser.add_argument(
        "--local-files-only",
        action="store_true",
        help="Prevent network downloads — model must already be cached locally",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    try:
        from mlx_qwen3_asr import transcribe
    except ImportError:
        print(
            json.dumps(
                {
                    "type": "error",
                    "message": (
                        "mlx-qwen3-asr is not installed. "
                        "Install with: pip install mlx-qwen3-asr"
                    ),
                }
            ),
            flush=True,
        )
        return 2

    # Signal ready — model loads lazily on first transcribe call
    print(json.dumps({"type": "ready"}), flush=True)

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            request = json.loads(line)
        except json.JSONDecodeError:
            print(
                json.dumps({"type": "error", "message": "Invalid JSON"}),
                flush=True,
            )
            continue

        msg_type = request.get("type")

        if msg_type == "start":
            # Already signaled ready above; acknowledge
            print(json.dumps({"type": "ready"}), flush=True)

        elif msg_type == "transcribe":
            audio_path = request.get("audio_path", "")
            if not audio_path or not Path(audio_path).is_file():
                print(
                    json.dumps(
                        {
                            "type": "error",
                            "message": f"Audio file not found: {audio_path}",
                        }
                    ),
                    flush=True,
                )
                continue

            try:
                result = transcribe(
                    audio_path,
                    model=args.model,
                    verbose=False,
                    return_timestamps=False,
                    return_chunks=True,
                )
                chunks = result.chunks or []
                text = " ".join(
                    (c.get("text") or "").strip() for c in chunks
                ).strip()
                if not text:
                    text = (result.text or "").strip()
                print(
                    json.dumps({"type": "transcript", "text": text}),
                    flush=True,
                )
            except Exception as error:
                print(
                    json.dumps(
                        {"type": "error", "message": str(error)}
                    ),
                    flush=True,
                )

        elif msg_type == "stop":
            print(json.dumps({"type": "stopped"}), flush=True)
            break

        else:
            print(
                json.dumps(
                    {"type": "error", "message": f"Unknown type: {msg_type}"}
                ),
                flush=True,
            )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())