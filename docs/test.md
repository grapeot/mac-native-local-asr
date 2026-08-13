# Test Strategy

## Unit Tests

Swift tests in the Xcode project test target (`MacLocalASRTests`).

- **VAD logic**: energy threshold, silence detection, minimum utterance length
- **ASR bridge client**: JSONL protocol encoding/decoding, error handling, timeout
- **Text output**: clipboard writing, keystroke event construction
- **Settings**: UserDefaults persistence, default values

## Integration Tests

- **Audio pipeline**: AVAudioEngine tap produces PCM chunks at expected format (24kHz mono 16-bit)
- **ASR bridge**: start → transcribe sample audio → verify transcript returned (requires model installed — opt-in test)
- **LLM post-processing**: send sample ASR text to Ollama endpoint, verify cleaned output (requires Ollama running — opt-in test)

## Manual Verification

The core user flow is verified manually:
1. Launch app → menu bar icon appears
2. Press hotkey → icon turns red (recording)
3. Speak a sentence → press hotkey → icon turns yellow (processing) → text appears at cursor or clipboard
4. Check: text is accurate, no network was used (turn off Wi-Fi and repeat)
5. Open Settings → change hotkey → verify new hotkey works
6. Quit app → verify model process is cleaned up

## Build Verification

```bash
xcodebuild -project src/MacLocalASR.xcodeproj -scheme MacLocalASR -configuration Debug build
xcodebuild -project src/MacLocalASR.xcodeproj -scheme MacLocalASR test
```

Both must pass with zero errors before any commit is considered complete.