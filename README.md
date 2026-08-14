# Mac Native Local ASR App

A macOS menu bar app for offline voice-to-text using local MLX-accelerated speech recognition. Press a global hotkey, speak, and your words are copied to the clipboard — no internet required.

## What it does

- Lives in the menu bar — no window, no dock icon
- Global hotkey (default: ⌘⇧Space) to toggle recording
- Audio captured via AVAudioEngine and converted to 24 kHz mono PCM
- Transcribed locally by Qwen3-ASR-1.7B through MLX
- Transcript copied to clipboard — paste with ⌘V wherever you want
- 100% offline — no network calls, no cloud APIs

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon Mac (M1 or later)
- [qwen3-asr-mlx-runtime](https://github.com/drguptavivek/qwen3-asr-mlx-runtime) installed and model downloaded

## Installation

### 1. Install qwen3-asr-mlx-runtime

```bash
git clone https://github.com/drguptavivek/qwen3-asr-mlx-runtime.git ~/qwen3-asr-mlx-runtime
uv venv .venv --python 3.12
uv pip install --python .venv/bin/python -e ~/qwen3-asr-mlx-runtime
```

The app never downloads a model. Download Qwen3-ASR-1.7B while online and keep
the resulting snapshot in a local directory.

### 2. Build and run the app

Open `src/Package.swift` in Xcode and run the `MacLocalASR` executable scheme.

Or from command line:

```bash
cd src
swift run MacLocalASR
```

### 3. Configure

Open Settings from the menu bar and set:

- ASR Bridge Path: this repository's `scripts/start_asr_bridge.py`
- Model Path: the downloaded local model directory
- Hotkey: defaults to ⌘⇧Space and can be changed in the recorder

### 4. Grant permissions

On first launch, the app will request **microphone access** (required for recording). No Accessibility permission is needed — the app copies to the clipboard and you paste manually with ⌘V.

## License

MIT

## For AI Agents

If you are an AI coding agent (Claude Code, Codex, OpenCode, etc.) installing this skill for a user, read `AGENTS.md` first, then `docs/prd.md` and `docs/rfc.md` for architecture context.
