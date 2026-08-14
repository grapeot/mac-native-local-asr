# AGENTS.md — Mac Native Local ASR App

## Project Role

A macOS menu bar app for offline voice-to-text using local MLX speech recognition (Qwen3-ASR-1.7B). Public GitHub repo. Not a web service, not an iOS app — a native macOS app built with SwiftUI and AVAudioEngine.

## Language

- **Working language**: English for all docs, code, and commit messages.
- **UI strings**: bilingual (English + Simplified Chinese), following system locale.
- This file and all docs under `docs/` are in English.

## Structure

- `src/` — Swift package and app sources
  - `src/Package.swift` — package manifest, openable directly in Xcode
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
# Build from the repository root
swift build --package-path src

# Run from the repository root
swift run --package-path src MacLocalASR

# Or open src/Package.swift in Xcode and run the MacLocalASR scheme
```

## Key Architecture Decisions

1. **Menu bar app, not window app** — `MenuBarExtra` with `.menu` style in SwiftUI. No dock icon.
2. **Toggle hotkey only** — press to start recording, press again to stop. No VAD, no push-to-talk.
3. **AVAudioEngine + AVAudioConverter** — macOS-native audio capture with explicit conversion to 24kHz Int16 mono.
4. **qwen3-asr-mlx-runtime as subprocess** — JSONL protocol, model stays resident, single WAV file per utterance.
5. **Clipboard-only text output** — write to NSPasteboard, user pastes manually with ⌘V. No simulated keystrokes, no Accessibility permission.
6. **No LLM post-processing in MVP** — Qwen3-ASR-1.7B includes punctuation. LLM cleanup is Phase 2.

## What NOT to do

- Do not add cloud dependencies. The entire point is offline operation.
- Do not add VAD, push-to-talk, or auto-segmentation in the MVP.
- Do not add LLM post-processing in the MVP.
- Do not add per-character CGEvent typing or simulated paste keystrokes for text output.
- Do not over-engineer settings. Three settings: hotkey, runtime path, model path.
- Do not add speaker diarization. Single-user dictation tool.
- Do not create a complex window-based UI. Menu bar + simple dropdown only.

## Maintenance

- After each implementation milestone: commit, update `docs/working.md`, verify build still passes.
- Privacy scan before any public push: `rg -n "real.email|real.phone|op://|internal.path" .` must return zero matches.
