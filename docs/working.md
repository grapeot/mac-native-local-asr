# Working Log

## 2026-08-13

- Scaffolded project structure: AGENTS.md, README.md, .gitignore, .env.example, docs/prd.md, docs/rfc.md
- Created directory layout: src/, docs/, scripts/, tests/, Assets/
- Initialized git repo with master branch
- Drafted PRD with success criteria focused on offline dictation
- GPT design review identified 5 key corrections: remove VAD, remove push-to-talk, remove LLM post-processing, fix text insertion, enforce offline startup
- Revised RFC: simplified to 6 components (from 8), removed VAD, removed push-to-talk, removed LLM post-processing, changed text output to clipboard+⌘V, added explicit audio format conversion, added state machine, reduced settings to 3 items
- Identified qwen3-asr-mlx-runtime as the ASR backend (subprocess, not in-process MLX)
- Decided against reusing VoiceFlowKit (cloud-transport design incompatible with local-only app)
- GPT implemented core app: 13 Swift files, Python bridge script, String Catalog, Package.swift
- GPT self-review found 5 issues; main thread fixed 3 most important:
  1. Python bridge: model now loads on "start" before returning "ready" (was returning ready before loading)
  2. AudioCaptureManager: added NSLock to protect converter/outputFormat/isRecording from cross-thread races
  3. TextOutputManager: record frontmost app at recording start, only auto-paste if same app is frontmost when transcription completes
- Issue 4 (app bundle identity for stable TCC) marked as known limitation — SwiftPM executable works but TCC grants may reset on rebuild; Phase 2 will create proper .app bundle
- Issue 3 (bridge crash vs AppState readiness sync) partially addressed; full fix needs callback from ASRBridgeClient to AppState — deferred to next iteration

## Lessons Learned

- GPT tends to over-engineer but its design review was valuable: the VAD, push-to-talk, and per-character CGEvent suggestions were correctly flagged as unnecessary complexity. The key insight was that toggle mode (explicit start/stop) makes VAD redundant for an MVP dictation tool.
- GPT's implementation assumed a specific internal API (`RuntimeJSONBridge`, `ProbeContext`) of an external package that doesn't exist as importable Python objects. Always verify external package APIs against actual installed code, not against what seems reasonable from the package name.
- `@Environment(\.openSettings)` in SwiftUI `MenuBarExtra(.menu)` style is unreliable on macOS 14 — use `NSApp.sendAction(Selector(("showSettingsWindow:")))` instead.
