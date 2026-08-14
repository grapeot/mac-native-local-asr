# Test Strategy

## Core Principle: Automated Testing via ControlServer

The app must be testable end-to-end from the command line without GUI interaction. A built-in HTTP control server (`localhost:17843`) exposes state queries and action triggers. This is a business requirement, not a convenience — every change to the app must be verifiable by `curl` before handing off to a human.

## ControlServer Endpoints

| Endpoint | Purpose |
|---|---|
| `GET /status` | Returns JSON: `phase`, `configured`, `ready`, `lastTranscript`, `setupProgress` |
| `GET /setup` | Triggers first-run setup (venv creation, pip install, bridge script) |
| `GET /toggle` | Toggles recording (start/stop) |
| `GET /settings` | Opens the Settings window |

## Automated Test Flow

The following sequence can be run by an AI agent or CI script without human interaction:

```bash
# 1. Build
swift build --package-path src

# 2. Launch app in background
swift run --package-path src MacLocalASR &
APP_PID=$!
sleep 3

# 3. Verify initial state (unconfigured on first run)
curl -sf http://127.0.0.1:17843/status | grep '"configured":false'

# 4. Trigger setup
curl -sf http://127.0.0.1:17843/setup

# 5. Poll until setup completes (venv + pip install + bridge start)
for i in $(seq 1 60); do
    sleep 5
    curl -sf http://127.0.0.1:17843/status | grep '"configured":true' && break
done

# 6. Verify bridge is ready
curl -sf http://127.0.0.1:17843/status | grep '"ready":true'

# 7. (Optional) Toggle recording — requires microphone permission
# curl -sf http://127.0.0.1:17843/toggle

# 8. Cleanup
kill $APP_PID
```

## Unit Tests

Unit tests should cover the deterministic component contracts without requiring model weights.

- **ASR bridge client**: JSONL protocol encoding/decoding, error handling, timeout
- **Text output**: clipboard writing (NSPasteboard clear + setString)
- **Settings**: UserDefaults persistence, default values
- **Audio output**: WAV header and 24 kHz mono Int16 format

## Integration Tests

- **Audio pipeline**: AVAudioEngine tap produces PCM chunks at expected format (24kHz mono 16-bit)
- **ASR bridge**: start → transcribe sample audio → verify transcript returned (requires model installed — opt-in test)

## Manual Verification

The core user flow is verified manually after automated tests pass:
1. Launch app → menu bar icon appears
2. Press hotkey → icon turns red (recording)
3. Speak a sentence → press hotkey → icon turns yellow (processing) → text is copied to clipboard (verify with ⌘V)
4. Check: text is accurate, no network was used (turn off Wi-Fi and repeat)
5. Open Settings → change hotkey → verify new hotkey works
6. Quit app → verify model process is cleaned up

## Build Verification

```bash
swift build --package-path src
```

Must pass with zero errors before any commit.