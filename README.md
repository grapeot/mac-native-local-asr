# Mac Native Local ASR App

A macOS menu bar app for offline voice-to-text using local MLX-accelerated speech recognition. Press a global hotkey, speak, and your words are copied to the clipboard — no internet required.

## What it does

- Lives in the menu bar — no window, no dock icon
- Global hotkey (default: ⌘⇧Space) to toggle recording
- Physical input device selected through AVFoundation and converted to 24 kHz mono PCM
- Transcribed locally by Qwen3-ASR-1.7B through MLX
- Transcript copied to clipboard — paste with ⌘V wherever you want
- Offline after first-time setup — no cloud APIs during transcription

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon Mac (M1 or later)
- Python 3 available in a standard Homebrew or system location

## Installation

### 1. Build the signed app bundle

```bash
bash scripts/build_app.sh
open ~/Applications/MacLocalASR.app
```

An Apple Development certificate is used when available; otherwise the script
falls back to ad-hoc signing. A stable signature is required for macOS to retain
microphone permission between builds.

### 2. Run first-time setup

Click **Setup** once. The app creates `~/.maclocalasr/.venv`, installs
`mlx-qwen3-asr`, writes its bridge script, and loads Qwen3-ASR-1.7B. This step
requires internet access; recording and transcription are offline afterward.

Open Settings to change the global hotkey or select a physical input device.

### 3. Grant permission

On first launch, the app will request **microphone access** (required for recording). No Accessibility permission is needed — the app copies to the clipboard and you paste manually with ⌘V.

## Testing

```bash
swift test --package-path src
bash tests/e2e.sh
bash tests/live_audio.sh  # signed app + granted microphone permission required
```

## License

MIT

## For AI Agents

If you are an AI coding agent (Claude Code, Codex, OpenCode, etc.) installing this skill for a user, read `AGENTS.md` first, then `docs/prd.md` and `docs/rfc.md` for architecture context.
