# Test Strategy

## Core Principle: Automated Testing via ControlServer

The app must be testable end-to-end from the command line without GUI interaction. A built-in HTTP control server (`localhost:17844`) exposes state queries and action triggers. This is a business requirement, not a convenience — every change to the app must be verifiable by `curl` before handing off to a human.

## ControlServer Endpoints

| Endpoint | Purpose |
|---|---|
| `GET /status` | Returns JSON: `phase`, `configured`, `ready`, `lastTranscript`, `setupProgress` |
| `GET /setup` | Triggers first-run setup (venv creation, pip install, bridge script) |
| `GET /toggle` | Toggles recording (start/stop) |
| `GET /settings` | Opens the Settings window |

## Test Layers

### 1. Deterministic unit test

```bash
swift test --package-path src
```

`PCM16WAVEncoderTests` mechanically verifies RIFF sizes, PCM encoding, channel
count, 24kHz sample rate, byte rate, block alignment, bit depth, and payload.

### 2. Model integration test

```bash
bash tests/e2e.sh
```

This builds the debug executable, verifies ControlServer and bridge readiness,
generates a deterministic spoken fixture with `say`, transcribes it through the
installed bridge, and asserts that a transcript event with expected words is
returned. It refuses to kill an unrelated process already using port 17844.

### 3. Signed-app hardware test

```bash
bash scripts/build_app.sh
open ~/Applications/MacLocalASR.app
# Grant microphone access once, then:
bash tests/live_audio.sh
```

This test exercises the actual TCC identity and physical microphone. It requires
the signed app, completed setup, and previously granted microphone permission.
It asserts that the app enters `recording`, reports a non-zero live audio level,
and stops without a `no audio captured` error. The script can attach to an
already running app and does not terminate processes it did not start.

The build script signs by certificate hash because multiple keychain entries can
share the same Apple Development display name. It does not reset TCC by default;
use `RESET_MICROPHONE_PERMISSION=1 bash scripts/build_app.sh` only when explicitly
testing the first-run permission prompt.

## Unit Tests

Unit tests should cover the deterministic component contracts without requiring model weights.

- **ASR bridge client**: JSONL protocol encoding/decoding, error handling, timeout
- **Text output**: clipboard writing (NSPasteboard clear + setString)
- **Settings**: UserDefaults persistence, default values
- **Audio output**: WAV header and 24 kHz mono Int16 format (implemented)

## Integration Tests

- **Audio pipeline**: signed `AVCaptureSession` app produces non-zero microphone levels and PCM data
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
