# PRD — Mac Native Local ASR App

## Problem

On a 6-hour flight without Wi-Fi, or in any offline environment, there is no way to do voice-to-text dictation on a Mac. Cloud-based ASR (OpenAI Realtime, Whisper API, DashScope) requires internet. The user needs a local solution that works completely offline.

## Users

Power users who want voice dictation on macOS without depending on cloud services. Primary user is a developer/technical writer who works in mixed Chinese-English and needs technical terms recognized accurately.

## Goals

1. Press a global hotkey anywhere on macOS → speak → text is copied to clipboard, ready to paste with ⌘V
2. Works 100% offline with no network calls
3. Uses Qwen3-ASR-1.7B via MLX for high-quality Chinese/English/mixed recognition
4. Low latency: under 2 seconds from stop-speaking to text-copied
5. Battery-aware: model stays resident but inference is fast enough to not drain battery

## Non-Goals

- Speaker diarization (single-user dictation)
- Cloud fallback (if local fails, show error — do not silently call a cloud API)
- Full transcription editor (this is a dictation tool, not a transcription app)
- iOS/visionOS support (separate codebase: VoiceFlow app)
- Real-time streaming display (batch-per-utterance is sufficient and simpler)

## Success Criteria

- [ ] App installs and runs as a menu bar item with no dock icon
- [ ] Global hotkey toggles recording; menu bar icon changes state (idle/recording/processing)
- [ ] Spoken Chinese text copied to clipboard within 2 seconds of speaking
- [ ] Spoken English text copied to clipboard within 2 seconds of speaking
- [ ] Chinese-English mixed speech (e.g., "用 PyTorch 写一个 Transformer") transcribed correctly
- [ ] Works with Wi-Fi turned off (verified by disabling network)
- [ ] Model loads once at app startup and stays resident for the session
- [ ] Quitting the app releases the model and frees memory
- [ ] First-run setup is self-contained: user clicks "Setup", app auto-creates venv, installs mlx-qwen3-asr, starts bridge — no path entry
- [ ] Settings window is resizable and shows hotkey recorder + setup status
- [ ] Bilingual UI (English/Chinese) following system locale
- [ ] App is testable end-to-end from command line via HTTP control server (localhost:17843) without GUI interaction

## Constraints

- macOS 14+ (SwiftUI MenuBarExtra requires Sonoma)
- Apple Silicon only (MLX is Apple-specific)
- qwen3-asr-mlx-runtime must be pre-installed by user
- Microphone permission required for recording
- No Accessibility permission needed (clipboard-only output, no simulated keystrokes)
