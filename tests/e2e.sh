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
    if [ -n "${GATE_PID:-}" ]; then
        kill "$GATE_PID" 2>/dev/null || true
    fi
    if [ -n "${APP_PID:-}" ]; then
        kill "$APP_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

echo "=== 1. Build ==="
swift build --package-path "$REPO_ROOT/src"

echo "=== 2. Generate test audio ==="
say -o /tmp/maclocalasr_test.aiff "Hello, this is a test of the speech recognition system." 2>/dev/null
ffmpeg -y -i /tmp/maclocalasr_test.aiff -ar 24000 -ac 1 -acodec pcm_s16le "$TEST_AUDIO" 2>/dev/null
echo "Test audio: $TEST_AUDIO ($(du -h "$TEST_AUDIO" | cut -f1))"

echo "=== 3. Launch app ==="
if lsof -nP -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Port $PORT is already in use. Quit the running app or use tests/live_audio.sh."
    exit 1
fi

"$REPO_ROOT/src/.build/debug/MacLocalASR" 2>/tmp/maclocalasr_gate_stderr.log &
GATE_PID=$!
sleep 2
if curl --max-time 1 -sf http://127.0.0.1:$PORT/status >/dev/null 2>&1; then
    echo "ControlServer started without --enable-control-server"
    kill "$GATE_PID" 2>/dev/null || true
    exit 1
fi
kill "$GATE_PID" 2>/dev/null || true
wait "$GATE_PID" 2>/dev/null || true
GATE_PID=""
sleep 2

"$REPO_ROOT/src/.build/debug/MacLocalASR" --enable-control-server 2>/tmp/maclocalasr_e2e_stderr.log &
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
for i in $(seq 1 120); do
    STATUS=$(curl --max-time 5 -sf http://127.0.0.1:$PORT/status)
    echo "[$i s] $STATUS"
    echo "$STATUS" | grep -q '"ready":true' && break
    echo "$STATUS" | grep -q '"phase":"error:' && { echo "Bridge startup failed"; exit 1; }
    sleep 1
done
echo "$STATUS" | grep -q '"ready":true' || { echo "Bridge not ready"; exit 1; }

echo "=== 7. Test transcription via direct bridge call ==="
# Direct test: send the test WAV to the bridge process
VENV_PYTHON="$HOME/.maclocalasr/.venv/bin/python"
BRIDGE="$HOME/.maclocalasr/start_asr_bridge.py"
BRIDGE_OUTPUT=$("$VENV_PYTHON" "$BRIDGE" --model "Qwen/Qwen3-ASR-1.7B" --local-files-only 2>/tmp/maclocalasr_bridge_stderr.log <<EOF
{"type": "start"}
{"type": "transcribe", "audio_path": "$TEST_AUDIO"}
{"type": "stop"}
EOF
)
echo "$BRIDGE_OUTPUT"
echo "$BRIDGE_OUTPUT" | grep -q '"type": "transcript"' || { echo "Bridge returned no transcript"; exit 1; }
echo "$BRIDGE_OUTPUT" | grep -qi 'test\|speech\|recognition' || { echo "Transcript did not match the fixture"; exit 1; }

echo "=== 8. Check bridge stderr for ffmpeg errors ==="
if grep -qi "ffmpeg" /tmp/maclocalasr_bridge_stderr.log; then
    echo "WARNING: ffmpeg-related messages in bridge stderr:"
    grep -i "ffmpeg" /tmp/maclocalasr_bridge_stderr.log
fi

echo ""
echo "=== E2E test passed ==="
