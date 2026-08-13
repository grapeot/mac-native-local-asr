# Mac Native Local ASR App

A macOS menu bar app for offline voice-to-text using local MLX-accelerated speech recognition. Press a global hotkey, speak, and your words appear at the cursor — no internet required.

## What it does

- Lives in the menu bar — no window, no dock icon
- Global hotkey (default: ⌘⇧Space) to toggle recording
- Audio captured via AVAudioEngine, segmented by VAD
- Transcribed locally by Qwen3-ASR-1.7B through MLX
- Text inserted at cursor position or copied to clipboard
- Optional LLM post-processing (punctuation, formatting) via Ollama or LM Studio
- 100% offline — no network calls, no cloud APIs

## Requirements

- macOS 14.0+ (Sonoma)
- Apple Silicon Mac (M1 or later)
- [qwen3-asr-mlx-runtime](https://github.com/drguptavivek/qwen3-asr-mlx-runtime) installed and model downloaded
- (Optional) [Ollama](https://ollama.ai) or LM Studio for text post-processing

## Installation

### 1. Install qwen3-asr-mlx-runtime

```bash
git clone https://github.com/drguptavivek/qwen3-asr-mlx-runtime.git ~/qwen3-asr-mlx-runtime
cd ~/qwen3-asr-mlx-runtime
python3.12 -m venv .venv
source .venv/bin/activate
pip install "mlx==0.31.2" "mlx-lm==0.29.1" "transformers==4.57.6" "qwen-asr==0.0.6"
```

### 2. Download model (automatic on first run)

The app will trigger model download on first use, or you can pre-download:

```bash
# Inside the runtime venv
python -c "from huggingface_hub import snapshot_download; snapshot_download('Qwen/Qwen3-ASR-1.7B')"
```

### 3. Build and run the app

Open `src/MacLocalASR.xcodeproj` in Xcode, build and run.

Or from command line:

```bash
xcodebuild -project src/MacLocalASR.xcodeproj -scheme MacLocalASR -configuration Release build
open build/Release/MacLocalASR.app
```

### 4. Grant permissions

On first launch, the app will request:
- **Microphone access** (required for recording)
- **Accessibility access** (required for global hotkey and text insertion at cursor)

Grant both in System Settings → Privacy & Security.

## Configuration

Copy `.env.example` to `~/.config/mac-local-asr/.env` and adjust paths:

```bash
mkdir -p ~/.config/mac-local-asr
cp .env.example ~/.config/mac-local-asr/.env
```

Edit the file to point to your qwen3-asr-mlx-runtime installation.

## License

MIT

## For AI Agents

If you are an AI coding agent (Claude Code, Codex, OpenCode, etc.) installing this skill for a user, read `AGENTS.md` first, then `docs/prd.md` and `docs/rfc.md` for architecture context.