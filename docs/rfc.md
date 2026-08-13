# RFC — Mac Native Local ASR App

## Architecture Overview

```
┌──────────────────────────────────────────────────┐
│              Menu Bar App (SwiftUI)                │
│                                                   │
│  ┌──────────┐    ┌──────────────┐    ┌──────────┐  │
│  │ Global   │    │ AVAudio-    │    │ WAV      │  │
│  │ Hotkey   │───▶│ Engine      │───▶│ file     │  │
│  │ (toggle) │    │ → 24kHz     │    │ (temp)   │  │
│  └──────────┘    └──────────────┘    └────┬─────┘  │
│                                            │       │
│                            ┌───────────────▼────┐  │
│                            │ ASR Bridge Client  │  │
│                            │ (JSONL subprocess) │  │
│                            │ ┌────────────────┐ │  │
│                            │ │ qwen3-asr-mlx-  │ │  │
│                            │ │ runtime process │ │  │
│                            │ │ (model resident)│ │  │
│                            │ └────────────────┘ │  │
│                            └───────┬────────────┘  │
│                                    │               │
│                    ┌───────────────▼─────────────┐ │
│                    │ Text Output                 │ │
│                    │ 1. Write to NSPasteboard    │ │
│                    │ 2. Simulate ⌘V keystroke     │ │
│                    │    (if Accessibility granted)│ │
│                    │ Fallback: "Copied" status   │ │
│                    └─────────────────────────────┘ │
└──────────────────────────────────────────────────┘
```

## State Machine

The app has exactly one state at a time:

```
loading → idle → recording → processing → idle
                ↑                          │
                └────── error (back to idle, show message) ──┘
```

- **loading**: model starting, ASR bridge initializing
- **idle**: ready to record, menu bar icon gray
- **recording**: hotkey pressed, audio capturing, menu bar icon red
- **processing**: hotkey pressed again, audio sent to ASR, menu bar icon yellow
- **error**: transient state, shows error message, returns to idle

Hotkey behavior is deterministic:
- In `idle` → starts recording
- In `recording` → stops recording, starts processing
- In `processing` or `loading` → ignored (no-op)

## Component Contracts

### 1. MenuBarExtra (UI)

SwiftUI `MenuBarExtra` with `.menu` style (not `.window` — simpler, native, no window management). Icon is an SF Symbol that changes per state:

- Idle: `waveform.circle` (gray, template image)
- Recording: `waveform.circle.fill` (red, via tinted template image)
- Processing: `waveform.circle.badge.ellipsis` (yellow)
- Error: `exclamationmark.circle` (red)

Dropdown menu contents:
- Status text (current state + last action result)
- Last transcription (truncated to 2 lines, click to copy)
- Separator
- Settings… (opens a small settings window)
- Quit

### 2. GlobalHotkeyManager

Uses the `KeyboardShortcuts` SPM package. Default: ⌘⇧Space. User-configurable in Settings.

**Toggle mode only.** Press to start recording, press again to stop and process. No push-to-talk, no VAD. The two hotkey presses define the exact recording boundary.

### 3. AudioCaptureManager

`AVAudioEngine` with `installTap(onBus:0, bufferSize:4096, format:)`.

- Input: default input device (user changes via System Settings)
- Input format: whatever the device provides (commonly 44.1/48kHz, Float32, stereo or mono)
- Conversion: `AVAudioConverter` to transform to 24kHz, Int16, mono PCM
- Output: accumulated PCM buffer in memory, written to temp WAV file on stop
- Max recording duration: 60 seconds (dictation tool, not transcription app)
- Device change handling: `AVAudioEngine` notification for device removal → cancel recording, show error

Temp WAV file location: `NSTemporaryDirectory()`. Deleted after transcription completes or on app quit.

### 4. ASR Bridge Client

Manages the `qwen3-asr-mlx-runtime` subprocess via JSONL protocol.

**Startup** (at app launch):
1. Launch `python3 scripts/qwen3-asr-mlx-bridge` with `--model Qwen/Qwen3-ASR-1.7B --local-files-only`
2. Send `{"type":"start"}` → wait for `{"type":"ready"}` (timeout: 30s for model load)
3. State → `idle`

**Transcription** (per utterance):
1. Send `{"type":"transcribe","audio_path":"/tmp/xxx.wav"}`
2. Receive `{"type":"transcript","text":"..."}`
3. State → `idle`

**Shutdown** (on app quit):
1. Send `{"type":"stop"}`
2. Terminate process after 2s if no response

**Error handling**:
- Subprocess crash: bounded restart (max 3 attempts, exponential backoff). Discard in-flight utterance. User must press hotkey again after recovery.
- Model load failure: show error in menu bar, do not retry automatically.
- Transcript timeout (>15s): show timeout error, kill and restart bridge.
- stdout is for JSONL only. stderr is drained to a bounded in-memory diagnostic buffer (last 50 lines). Any non-JSON line on stdout is skipped, not fatal.

**Bridge script**: this repo owns a thin launch script at `scripts/start_asr_bridge.py` that imports `qwen3-asr-mlx-runtime` and exposes the JSONL protocol. The external runtime must be installed by the user; this script is the adapter layer.

**Versioning**: the app records the tested runtime commit hash and Python version in Settings. At startup, it logs a warning if the installed runtime doesn't match, but does not hard-block.

### 5. TextOutputManager

Single output path, no mode switching:

1. Write transcript to `NSPasteboard.general.clearContents()` + `setString(transcript)`
2. If Accessibility permission granted: simulate ⌘V via `CGEvent(keyCode:kVK_ANSI_V, flags:.commandDown)`
3. If Accessibility not granted or paste fails: show "Copied to clipboard" in menu bar

This is one `NSPasteboard` write + one key event. No per-character typing. No Unicode fragility.

**Permission handling**: 
- Microphone: required. App requests on first recording. If denied, show error.
- Accessibility: optional. If granted, auto-paste works. If not, clipboard-only with manual paste.

### 6. SettingsStore

Persisted via `@AppStorage` (UserDefaults):

- `hotkey` — global hotkey combo (default: ⌘⇧Space)
- `asrRuntimePath` — path to `start_asr_bridge.py` script
- `asrModelPath` — local path to model directory (must exist, no implicit download)

Three settings. That's it. No LLM settings, no output mode, no recording mode.

## Key Design Decisions

### Why subprocess, not in-process MLX?

The `qwen3-asr-mlx-runtime` is a Python project. Bridging Python+MLX into Swift directly requires PyObjC or a C bridge, both fragile. A subprocess with JSONL protocol is clean, debuggable, and lets the Python runtime own its memory lifecycle. The model loads once and stays resident — subprocess startup cost is paid once at app launch.

### Why no VAD?

VAD adds complexity (thresholds, silence detection, calibration across devices) and failure modes (aircraft noise, room acoustics) that don't exist when the user explicitly presses a hotkey to start and stop. Toggle mode makes the recording boundary deterministic. VAD can be added later if users want auto-segmented continuous dictation.

### Why clipboard + ⌘V, not per-character CGEvent?

Per-character `CGEvent` typing is fragile for Unicode text (Chinese characters, emoji, mixed scripts). Some apps (Terminal, Electron, secure fields) don't reliably accept simulated Unicode keystrokes. Writing to `NSPasteboard` and simulating one ⌘V is universal — every macOS text field that accepts paste will work. If Accessibility is unavailable, the user still has the text in clipboard for manual paste.

### Why not VoiceFlowKit?

VoiceFlowKit is designed for cloud WebSocket ASR. Its `VoiceFlowMicrophone` is `#if os(iOS) || os(visionOS)` — unavailable on macOS. Its session/ticket/recovery model is cloud-transport-specific. This app shares zero code with VoiceFlowKit by design.

### Why KeyboardShortcuts SPM package?

Raw `CGEvent` tap for global hotkeys requires complex Carbon-era `RegisterEventHotKey` calls and is error-prone. `KeyboardShortcuts` by Sindre Sorhus is well-maintained, handles permission prompts, and provides a clean SwiftUI integration. MIT licensed.

### Why no LLM post-processing in MVP?

LLM post-processing adds a dependency on another user-managed service (Ollama/LM Studio), more failure modes, and 0.5-1s latency. The ASR output from Qwen3-ASR-1.7B already includes punctuation. If post-processing is needed, it can be added as a Phase 2 feature without changing the core architecture.

## Dependencies

- **KeyboardShortcuts** (SPM, MIT) — global hotkey registration
- **qwen3-asr-mlx-runtime** (external, user-installed, Apache-2.0) — ASR backend

No other dependencies. No Ollama, no LM Studio, no ONNX Runtime in the MVP.

## Future (Phase 2, not in MVP)

- LLM post-processing via local Ollama endpoint
- Silero VAD for auto-segmented continuous dictation
- Recording history (last N transcripts viewable in menu dropdown)
- Model selection (0.6B vs 1.7B)
- Notarized Developer ID distribution