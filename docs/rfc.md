# RFC — Mac Native Local ASR App

## Architecture Overview

```
┌──────────────────────────────────────────────────┐
│              Menu Bar App (SwiftUI)                │
│                                                   │
│  ┌──────────┐    ┌──────────────┐    ┌──────────┐  │
│  │ Global   │    │ AVAudio-    │    │ VAD      │  │
│  │ Hotkey   │───▶│ Engine      │───▶│ (energy  │  │
│  │          │    │ (24kHz mono)│    │  based)  │  │
│  └──────────┘    └──────────────┘    └────┬─────┘  │
│                                            │       │
│                            ┌───────────────▼────┐ │
│                            │ ASR Bridge Client  │ │
│                            │ (JSONL subprocess) │ │
│                            │ ┌────────────────┐ │ │
│                            │ │ qwen3-asr-mlx-  │ │ │
│                            │ │ runtime process │ │ │
│                            │ │ (model resident) │ │ │
│                            │ └────────────────┘ │ │
│                            └───────┬────────────┘ │
│                                    │              │
│                    ┌───────────────▼────────────┐ │
│                    │ Text Output                │ │
│                    │ ├─ Paste to clipboard      │ │
│                    │ └─ Simulate keystroke       │ │
│                    │    (CGEvent key events)     │ │
│                    └────────────────────────────┘ │
│                                                   │
│  Optional: ┌────────────────────────────────────┐ │
│            │ LLM Post-Processing                 │ │
│            │ (Ollama/LM Studio localhost API)    │ │
│            │ → punctuation, formatting, cleanup  │ │
│            └────────────────────────────────────┘ │
└──────────────────────────────────────────────────┘
```

## Component Contracts

### 1. MenuBarExtra (UI)

SwiftUI `MenuBarExtra` with `systemTray` style. Icon is a simple SF Symbol that changes:
- Idle: `mic.fill` (gray)
- Recording: `mic.fill` (red, pulsing animation)
- Processing: `mic.fill` (yellow)

Click opens a small dropdown with:
- Status text (current state)
- Last transcription (truncated, tap to copy)
- Settings link (opens settings window)
- Quit button

### 2. GlobalHotkeyManager

Uses the `KeyboardShortcuts` SPM package (simpler and more reliable than raw CGEvent tap). Default: ⌘⇧Space. User-configurable in Settings.

Two modes:
- **Push-to-talk**: hold hotkey to record, release to stop
- **Toggle**: press to start, press again to stop (better for long dictation)

Default mode: toggle. Configurable in Settings.

### 3. AudioCaptureManager

`AVAudioEngine` with `installTap(onBus:0, bufferSize:4096, format:)`.

- Input: default input device (user can change in System Settings)
- Format: PCM 16-bit, 24kHz, mono (matches Qwen3-ASR input)
- Output: `Data` chunks fed to VAD

No `AVAudioSession` (that's iOS). macOS uses device selection via `AVAudioEngine.inputNode`.

### 4. VAD (Voice Activity Detection)

**Phase 1 (MVP)**: Energy-based VAD. Simple RMS threshold + silence duration detection.
- Speech threshold: RMS > -45dB
- Silence threshold: RMS < -50dB for > 1.5 seconds → end of utterance
- Minimum utterance length: 0.3 seconds (filter clicks/noise)

**Phase 2 (future)**: Silero VAD via ONNX Runtime if energy-based is insufficient.

VAD output: utterance audio segments (PCM Data chunks with timestamps).

### 5. ASR Bridge Client

Manages the `qwen3-asr-mlx-runtime` subprocess via JSONL protocol.

**Lifecycle**:
1. App startup → `start` command (model loads, stays resident)
2. VAD detects utterance → `audio_chunk` + `end_utterance`
3. Receive `transcript` JSON response
4. Repeat for each utterance
5. App quit → `stop` command (clean shutdown)

**Protocol** (newline-delimited JSON over stdin/stdout):

```jsonl
// App → Runtime
{"type":"start"}
{"type":"audio_chunk","audio":"<base64-wav>","sample_rate":24000}
{"type":"end_utterance"}
{"type":"stop"}

// Runtime → App
{"type":"ready"}
{"type":"transcript","text":"你好世界","segments":[...]}
{"type":"error","message":"..."}
```

**Error handling**: if subprocess crashes, restart it. If model fails to load, show error in menu bar. If transcript times out (>10s), show timeout error.

### 6. TextOutputManager

Two output modes (configurable in Settings):

**Mode A: Clipboard** (default, safest)
- Write transcript to `NSPasteboard.general`
- User pastes manually with ⌘V

**Mode B: Keystroke simulation** (default for push-to-talk)
- Use `CGEvent` to simulate typing each character
- Works in any text field that accepts keyboard input
- Requires Accessibility permission

### 7. LLMPostProcessor (optional)

If enabled in Settings, sends raw ASR text to a local LLM endpoint:

```
POST http://localhost:11434/v1/chat/completions
{
  "model": "qwen2.5:3b",
  "messages": [
    {"role": "system", "content": "Clean up ASR output: fix punctuation, remove filler words, format as readable text. Preserve the original language (Chinese/English/mixed). Output only the cleaned text."},
    {"role": "user", "content": "<raw ASR text>"}
  ]
}
```

Adds ~0.5-1s latency. User can disable for speed.

### 8. SettingsStore

Persisted via `UserDefaults` (or `@AppStorage`):
- `hotkey` — global hotkey key combo
- `asrRuntimePath` — path to qwen3-asr-mlx-bridge script
- `asrModel` — HuggingFace model ID (default: `Qwen/Qwen3-ASR-1.7B`)
- `outputMode` — "clipboard" or "keystroke"
- `recordingMode` — "toggle" or "push-to-talk"
- `llmEnabled` — bool
- `llmEndpoint` — URL string (default: `http://localhost:11434/v1`)
- `llmModel` — model name (default: `qwen2.5:3b`)

## Key Design Decisions

### Why subprocess, not in-process MLX?

The `qwen3-asr-mlx-runtime` is a Python project. Bridging Python+MLX into Swift directly requires PyObjC or a C bridge, both fragile. A subprocess with JSONL protocol is clean, debuggable, and lets the Python runtime own its memory lifecycle. The model loads once and stays resident — subprocess startup cost is paid once at app launch.

### Why energy-based VAD for MVP?

Silero VAD adds an ONNX Runtime dependency and model download. Energy-based VAD is ~30 lines of Swift and works well for close-mic dictation (the user is speaking directly into their Mac). We can upgrade to Silero if field testing shows insufficient accuracy.

### Why not VoiceFlowKit?

VoiceFlowKit is designed for cloud WebSocket ASR. Its `VoiceFlowMicrophone` is `#if os(iOS) || os(visionOS)` — unavailable on macOS. Its session/ticket/recovery model is cloud-transport-specific. Adding a "local strategy" would pollute the clean cloud design. This app shares zero code with VoiceFlowKit by design.

### Why KeyboardShortcuts SPM package?

Raw `CGEvent` tap for global hotkeys requires complex Carbon-era `RegisterEventHotKey` calls and is error-prone. `KeyboardShortcuts` by Sindre Sorhus is well-maintained, handles permission prompts, and provides a clean SwiftUI integration. It's MIT licensed.

## Dependencies

- **KeyboardShortcuts** (SPM) — global hotkey registration. MIT.
- **qwen3-asr-mlx-runtime** (external) — user-installed, not bundled. Apache-2.0.
- **Ollama or LM Studio** (optional, external) — LLM post-processing. User-installed.

No other SPM dependencies. Keep the dependency surface minimal for a public repo.