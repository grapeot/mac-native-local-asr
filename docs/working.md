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
- User clarified: output should be clipboard-only (auto-copy), not auto-paste
- Removed all CGEvent paste simulation, Accessibility permission, and frontmost-app tracking
- Updated all docs to reflect clipboard-only output
- No Accessibility permission needed anymore — only microphone
- GPT self-review found 5 issues; fixed 3: model preload in bridge, audio capture thread safety, frontmost-app check (later removed when switching to clipboard-only)
- User reported "setup.py not found" — rewrote setup as native Swift SetupRunner with bridge script embedded as string literal, no external file dependency
- User reported settings window not appearing — fixed with NSWindow + temporary activation policy switch to .regular
- User reported settings window not resizable — added .resizable style mask
- Added ControlServer (HTTP on localhost:17843) for automated end-to-end testing via curl
- Fixed mlx-qwen3-asr load_model API: package exposes `load_model(path_or_hf_repo, dtype)`, not `_model.load_model` with `local_files_only`
- Verified full automated flow: curl /setup → venv created → pip install → bridge started → status shows configured:true, ready:true in ~10s
- Documented ControlServer as business requirement in PRD, RFC, test.md, AGENTS.md

## Lessons Learned

- GPT tends to over-engineer but its design review was valuable: the VAD, push-to-talk, and per-character CGEvent suggestions were correctly flagged as unnecessary complexity. The key insight was that toggle mode (explicit start/stop) makes VAD redundant for an MVP dictation tool.
- GPT's implementation assumed a specific internal API (`RuntimeJSONBridge`, `ProbeContext`) of an external package that doesn't exist as importable Python objects. Always verify external package APIs against actual installed code, not against what seems reasonable from the package name.
- `@Environment(\.openSettings)` and `WindowGroup(id:)` in SwiftUI `MenuBarExtra(.menu)` are unreliable on macOS 14 — use `NSWindow` + `NSHostingController` directly.
- SwiftPM executable doesn't load `.xcstrings` String Catalogs reliably — use inline bilingual strings instead.
- Swift 6 strict concurrency disallows `NSLock.lock()/unlock()` in async contexts — use `DispatchQueue.sync` instead.
- Socket I/O (accept/read) blocks the thread — must run on a background `Thread`, not on MainActor. Otherwise `Task` dispatches from within the accept loop never execute.
- **Automated testing is a business requirement.** A GUI-only app that requires manual clicking to verify creates a slow feedback loop. The ControlServer pattern (embedded HTTP server with /status, /setup, /toggle endpoints) lets AI agents and CI scripts test the full flow without human interaction. Every macOS app in this workspace should adopt this pattern.