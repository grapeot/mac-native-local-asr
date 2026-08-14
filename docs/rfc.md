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
│                    │ Write to NSPasteboard       │ │
│                    │ User pastes manually (⌘V)  │ │
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

- Input: default input device or user-selected device via Core Audio device switching
- Input format: whatever the device provides (commonly 44.1/48kHz, Float32, stereo or mono)
- Conversion: `AVAudioConverter` to transform to 24kHz, Int16, mono PCM
- Output: accumulated PCM buffer in memory, written to temp WAV file on stop
- Max recording duration: 60 seconds (dictation tool, not transcription app)
- Device change handling: `AVAudioEngine` notification for device removal → cancel recording, show error
- Device selection: if user picks a specific device in Settings, the app temporarily switches the system default input device before recording and restores it after. This is necessary because `AVAudioEngine.inputNode` always uses the system default input device, which may be an aggregate device (e.g. 17-channel BlackHole mix) that doesn't capture the actual microphone.

Temp WAV file location: `NSTemporaryDirectory()`. Deleted after transcription completes or on app quit.

### 4. ASR Bridge Client

Manages the `qwen3-asr-mlx-runtime` subprocess via JSONL protocol.

**Startup** (at app launch):
1. Launch the configured `start_asr_bridge.py` with `--model <local-model-path> --local-files-only`
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

**Versioning**: the adapter targets `qwen3-asr-mlx-runtime` protocol `qwen3-asr-mlx-jsonl-v1`. Runtime installation and pinning remain user-managed and do not add a fourth setting.

### 5. TextOutputManager

Single output path: write transcript to `NSPasteboard.general.clearContents()` + `setString(transcript)`. The user pastes manually with ⌘V.

No simulated keystrokes, no Accessibility permission required. One `NSPasteboard` write. Simple and universal.

**Permission handling**: 
- Microphone: required. App requests on first recording. If denied, show error.
- No Accessibility permission needed.

### 6. SettingsStore

Persisted via `@AppStorage` (UserDefaults):

- `hotkey` — global hotkey combo (default: ⌘⇧Space)
- `asrModelId` — HuggingFace model ID (default: `Qwen/Qwen3-ASR-1.7B`)
- `audioInputDeviceID` — selected input device uniqueID (default: empty = system default)

Three user-visible settings. The venv path, bridge script path, and model ID are managed automatically by `SetupRunner` — the user never types paths. The input device picker lets users select a specific microphone (e.g. Shure MVX2U) instead of the system default (which may be an aggregate device with wrong channels).

### 7. SetupRunner

Runs on first launch (or when the user clicks "Setup…" in Settings or the menu bar). Creates a self-contained Python environment without requiring user input:

1. Find system Python 3 (`/opt/homebrew/bin/python3`, `/usr/local/bin/python3`, `/usr/bin/python3`)
2. Create venv at `~/.maclocalasr/.venv`
3. `pip install mlx-qwen3-asr` into the venv
4. Verify `import mlx_qwen3_asr` succeeds
5. Write the embedded bridge script to `~/.maclocalasr/start_asr_bridge.py`
6. On completion, the app auto-starts the ASR bridge

The bridge script content is embedded as a Swift string literal — no external file dependency. This eliminates "file not found" errors regardless of how the app is launched (swift run, Xcode, .app bundle).

Progress is reported via a callback to `AppState.setupProgress` for display in the Settings window.

### 8. ControlServer (automated testing)

A minimal HTTP server on `localhost:17844` that allows external tools (curl, CI scripts, AI agents) to query state and trigger actions without GUI interaction. This is a **business requirement**: the app must be testable end-to-end from the command line.

| Endpoint | Method | Purpose |
|---|---|---|
| `/status` | GET | Returns JSON: `phase`, `configured`, `ready`, `lastTranscript`, `setupProgress` |
| `/setup` | GET | Triggers `SetupRunner.runSetup()` asynchronously |
| `/toggle` | GET | Triggers `AppState.toggleRecording()` |
| `/settings` | GET | Opens the Settings window |

Socket I/O runs on a background `Thread`; MainActor calls are dispatched via `DispatchQueue.main`. The server binds to `127.0.0.1` only — no external access.

## Key Design Decisions

### Why subprocess, not in-process MLX?

The `qwen3-asr-mlx-runtime` is a Python project. Bridging Python+MLX into Swift directly requires PyObjC or a C bridge, both fragile. A subprocess with JSONL protocol is clean, debuggable, and lets the Python runtime own its memory lifecycle. The model loads once and stays resident — subprocess startup cost is paid once at app launch.

### Why no VAD?

VAD adds complexity (thresholds, silence detection, calibration across devices) and failure modes (aircraft noise, room acoustics) that don't exist when the user explicitly presses a hotkey to start and stop. Toggle mode makes the recording boundary deterministic. VAD can be added later if users want auto-segmented continuous dictation.

### Why clipboard-only, no auto-paste?

Auto-paste via `CGEvent` requires Accessibility permission, which adds friction at setup and prompts users unexpectedly. Clipboard-only output is universal — every macOS text field accepts ⌘V — and requires zero extra permissions. The user presses ⌘V when and where they want the text.

### Why not VoiceFlowKit?

VoiceFlowKit is designed for cloud WebSocket ASR. Its `VoiceFlowMicrophone` is `#if os(iOS) || os(visionOS)` — unavailable on macOS. Its session/ticket/recovery model is cloud-transport-specific. This app shares zero code with VoiceFlowKit by design.

### Why KeyboardShortcuts SPM package?

Raw `CGEvent` tap for global hotkeys requires complex Carbon-era `RegisterEventHotKey` calls and is error-prone. `KeyboardShortcuts` by Sindre Sorhus is well-maintained, handles permission prompts, and provides a clean SwiftUI integration. MIT licensed.

### Why no LLM post-processing in MVP?

LLM post-processing adds a dependency on another user-managed service (Ollama/LM Studio), more failure modes, and 0.5-1s latency. The ASR output from Qwen3-ASR-1.7B already includes punctuation. If post-processing is needed, it can be added as a Phase 2 feature without changing the core architecture.

## Dependencies

- **KeyboardShortcuts** (SPM, MIT) — global hotkey registration
- **mlx-qwen3-asr** (pip, auto-installed by SetupRunner) — ASR backend

No other dependencies. No Ollama, no LM Studio, no ONNX Runtime in the MVP.

## Future (Phase 2, not in MVP)

- LLM post-processing via local Ollama endpoint
- Silero VAD for auto-segmented continuous dictation
- Recording history (last N transcripts viewable in menu dropdown)
- Model selection (0.6B vs 1.7B)
- Notarized Developer ID distribution as a proper .app bundle
