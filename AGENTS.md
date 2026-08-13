# AGENTS.md — Mac Native Local ASR App

## Project Role

A macOS menu bar app for offline voice-to-text using local MLX speech recognition (Qwen3-ASR-1.7B). Public GitHub repo. Not a web service, not an iOS app — a native macOS app built with SwiftUI and AVAudioEngine.

## Language

- **Working language**: English for all docs, code, and commit messages.
- **UI strings**: bilingual (English + Simplified Chinese), following system locale.
- This file and all docs under `docs/` are in English.

## Structure

- `src/` — Xcode project and Swift sources
  - `src/MacLocalASR.xcodeproj` — Xcode project
  - `src/MacLocalASR/` — App sources (Swift)
- `docs/` — Product and engineering docs
  - `prd.md` — product scope, user goals, success criteria
  - `rfc.md` — architecture, key design decisions, component contracts
  - `design.md` — visual and interaction design spec
  - `working.md` — changelog and lessons learned
  - `test.md` — test strategy and acceptance criteria
- `scripts/` — Build, test, and utility scripts
- `tests/` — Test targets (Swift tests live in Xcode project)
- `Assets/` — App icon and image assets

## Git Rules

- Branch: `master` (not `main`)
- Commit frequently in small, reversible units
- Update `docs/working.md` after each meaningful change
- Do not commit `.env`, secrets, model weights, or build artifacts
- This is a public repo — no private emails, real API keys, internal paths, or 1Password references in any committed file

## Build & Test

```bash
# Build
xcodebuild -project src/MacLocalASR.xcodeproj -scheme MacLocalASR -configuration Debug build

# Unit tests
xcodebuild -project src/MacLocalASR.xcodeproj -scheme MacLocalASR test

# Run app
open build/Debug/MacLocalASR.app
```

## Key Architecture Decisions

1. **Menu bar app, not window app** — `MenuBarExtra` in SwiftUI. No dock icon, no main window.
2. **Global hotkey** — `CGEvent` tap or `KeyboardShortcuts` SPM package for system-wide key capture.
3. **AVAudioEngine** — macOS-native audio capture, not AVAudioSession (iOS pattern).
4. **qwen3-asr-mlx-runtime as subprocess** — JSONL bridge protocol over stdin/stdout. Model stays resident.
5. **Text output** — `NSPasteboard` for clipboard, `CGEvent` key events for cursor insertion.
6. **Optional LLM post-processing** — Ollama or LM Studio local API, not bundled.

## What NOT to do

- Do not add cloud dependencies. The entire point is offline operation.
- Do not add WebSocket, ticket flow, or cloud session management — this is not VoiceFlowKit.
- Do not over-engineer settings. Three settings max: hotkey, model path, LLM toggle.
- Do not add speaker diarization. Single-user dictation tool.
- Do not create a complex window-based UI. Menu bar + simple dropdown only.

## Maintenance

- After each implementation milestone: commit, update `docs/working.md`, verify build still passes.
- Privacy scan before any public push: `rg -n "real.email|real.phone|op://|internal.path" .` must return zero matches.