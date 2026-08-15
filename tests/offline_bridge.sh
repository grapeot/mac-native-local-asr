#!/bin/bash
# Verify that the installed bridge can load the cached model without network access.

set -euo pipefail

VENV_PYTHON="$HOME/.maclocalasr/.venv/bin/python"
BRIDGE="$HOME/.maclocalasr/start_asr_bridge.py"
MODEL="${MACLOCALASR_MODEL:-Qwen/Qwen3-ASR-1.7B}"

[ -x "$VENV_PYTHON" ] || { echo "Missing setup venv: $VENV_PYTHON" >&2; exit 1; }
[ -f "$BRIDGE" ] || { echo "Missing installed bridge: $BRIDGE" >&2; exit 1; }

OUTPUT=$(HF_HUB_OFFLINE=1 "$VENV_PYTHON" "$BRIDGE" \
    --model "$MODEL" --local-files-only <<EOF
{"type": "start"}
{"type": "stop"}
EOF
)

echo "$OUTPUT"
printf '%s' "$OUTPUT" | grep -q '"type": "ready"' || {
    echo "Bridge could not load the cached model offline" >&2
    exit 1
}

echo "PASS: cached model loaded with HF_HUB_OFFLINE=1"
