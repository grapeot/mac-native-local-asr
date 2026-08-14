#!/bin/bash
# E2E test for Mac Local ASR via ControlServer
# Usage: bash tests/e2e.sh
# Prerequisites: swift build passes, no existing app on port 17844

set -e

PORT=17844
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_AUDIO="/tmp/maclocalasr_test.wav"

cleanup() {
    pkill -f MacLocalASR 2>/dev/null || true
}
trap cleanup EXIT

echo "=== 1. Build ==="
swift build --package-path "$REPO_ROOT/src"

echo "=== 2. Generate test audio ==="
say -o /tmp/maclocalasr_test.aiff "Hello, this is a test of the speech recognition system." 2>/dev/null
ffmpeg -y -i /tmp/maclocalasr_test.aiff -ar 24000 -ac 1 -acodec pcm_s16le "$TEST_AUDIO" 2>/dev/null
echo "Test audio: $TEST_AUDIO ($(du -h "$TEST_AUDIO" | cut -f1))"

echo "=== 3. Launch app ==="
# Kill any lingering process
pkill -9 -f MacLocalASR 2>/dev/null || true
sleep 1

swift run --package-path "$REPO_ROOT/src" MacLocalASR 2>/tmp/maclocalasr_e2e_stderr.log &
APP_PID=$!
echo "App PID: $APP_PID"
sleep 4

echo "=== 4. Check initial status ==="
STATUS=$(curl --max-time 5 -sf http://127.0.0.1:$PORT/status)
echo "$STATUS"

if echo "$STATUS" | grep -q '"configured":false'; then
    echo "=== 5. First run — triggering setup ==="
    curl --max-time 5 -sf http://127.0.0.1:$PORT/setup
    echo ""
    echo "Waiting for setup to complete..."
    for i in $(seq 1 60); do
        sleep 5
        STATUS=$(curl --max-time 5 -sf http://127.0.0.1:$PORT/status)
        echo "[$((i*5))s] $STATUS"
        echo "$STATUS" | grep -q '"configured":true' && break
        echo "$STATUS" | grep -q '"phase":"error:' && ! echo "$STATUS" | grep -q '未配置' && echo "SETUP FAILED" && exit 1
    done
fi

echo "=== 6. Verify bridge ready ==="
STATUS=$(curl --max-time 5 -sf http://127.0.0.1:$PORT/status)
echo "$STATUS"
echo "$STATUS" | grep -q '"ready":true' || { echo "Bridge not ready"; exit 1; }

echo "=== 7. Test transcription via direct bridge call ==="
# Direct test: send the test WAV to the bridge process
VENV_PYTHON="$HOME/.maclocalasr/.venv/bin/python"
BRIDGE="$HOME/.maclocalasr/start_asr_bridge.py"
echo "{\"type\": \"start\"}" | "$VENV_PYTHON" "$BRIDGE" --model "Qwen/Qwen3-ASR-1.7B" 2>/tmp/maclocalasr_bridge_stderr.log <<EOF
{"type": "start"}
{"type": "transcribe", "audio_path": "$TEST_AUDIO"}
{"type": "stop"}
EOF

echo "=== 8. Check bridge stderr for ffmpeg errors ==="
if grep -qi "ffmpeg" /tmp/maclocalasr_bridge_stderr.log; then
    echo "WARNING: ffmpeg-related messages in bridge stderr:"
    grep -i "ffmpeg" /tmp/maclocalasr_bridge_stderr.log
fi

echo ""
echo "=== E2E test passed ==="