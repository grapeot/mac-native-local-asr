#!/bin/bash
# Opt-in hardware integration test for the signed app bundle.

set -euo pipefail

PORT=17844
APP_PATH="${MACLOCALASR_APP_PATH:-$HOME/Applications/MacLocalASR.app}"
STARTED_APP=0

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

cleanup() {
    STATUS=$(curl --max-time 2 -sf "http://127.0.0.1:$PORT/status" 2>/dev/null || true)
    if printf '%s' "$STATUS" | grep -q '"phase":"recording"'; then
        curl --max-time 2 -sf "http://127.0.0.1:$PORT/toggle" >/dev/null 2>&1 || true
    fi
    if [ "$STARTED_APP" = "1" ] && [ -n "${APP_PID:-}" ]; then
        kill "$APP_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

if ! curl --max-time 2 -sf "http://127.0.0.1:$PORT/status" >/dev/null 2>&1; then
    [ -d "$APP_PATH" ] || fail "App bundle not found at $APP_PATH; run scripts/build_app.sh first"
    open "$APP_PATH"
    STARTED_APP=1
    for _ in $(seq 1 30); do
        APP_PID=$(pgrep -n -f "$APP_PATH/Contents/MacOS/MacLocalASR" || true)
        curl --max-time 2 -sf "http://127.0.0.1:$PORT/status" >/dev/null 2>&1 && break
        sleep 1
    done
fi

STATUS=$(curl --max-time 3 -sf "http://127.0.0.1:$PORT/status")
echo "Initial: $STATUS"
printf '%s' "$STATUS" | grep -q '"ready":true' || fail "ASR bridge is not ready"
printf '%s' "$STATUS" | grep -q '"phase":"idle"' || fail "App is not idle"

curl --max-time 3 -sf "http://127.0.0.1:$PORT/toggle" >/dev/null

MAX_LEVEL=0
for _ in $(seq 1 30); do
    sleep 0.2
    STATUS=$(curl --max-time 2 -sf "http://127.0.0.1:$PORT/status")
    LEVEL=$(printf '%s' "$STATUS" | sed -E 's/.*"audioLevel":([0-9.]+).*/\1/')
    MAX_LEVEL=$(awk -v current="$LEVEL" -v maximum="$MAX_LEVEL" 'BEGIN { print (current > maximum ? current : maximum) }')
    printf '%s' "$STATUS" | grep -q '"phase":"recording"' && [ "$MAX_LEVEL" != "0" ] && break
done

echo "Recording: $STATUS"
awk -v level="$MAX_LEVEL" 'BEGIN { exit !(level > 0) }' || fail "No non-zero microphone samples observed"
printf '%s' "$STATUS" | grep -q '"phase":"recording"' || fail "App did not enter recording state"

curl --max-time 3 -sf "http://127.0.0.1:$PORT/toggle" >/dev/null
sleep 1
STATUS=$(curl --max-time 3 -sf "http://127.0.0.1:$PORT/status")
echo "Stopped: $STATUS"
printf '%s' "$STATUS" | grep -qi 'no audio.*captured' && fail "Capture produced no PCM data"

echo "PASS: signed app captured live microphone audio (max level $MAX_LEVEL)"
