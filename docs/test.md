# Test Strategy

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

The core user flow is verified manually:
1. Launch app → menu bar icon appears
2. Press hotkey → icon turns red (recording)
3. Speak a sentence → press hotkey → icon turns yellow (processing) → text is copied to clipboard (verify with ⌘V)
4. Check: text is accurate, no network was used (turn off Wi-Fi and repeat)
5. Open Settings → change hotkey → verify new hotkey works
6. Quit app → verify model process is cleaned up

## Build Verification

```bash
swift build --package-path src
.venv/bin/python -m py_compile scripts/start_asr_bridge.py
```

Both must pass with zero errors before any commit is considered complete. Full audio and ASR integration remain manual until a local model fixture is configured.
