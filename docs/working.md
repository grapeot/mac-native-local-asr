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

## Lessons Learned

- GPT tends to over-engineer but its design review was valuable: the VAD, push-to-talk, and per-character CGEvent suggestions were correctly flagged as unnecessary complexity. The key insight was that toggle mode (explicit start/stop) makes VAD redundant for an MVP dictation tool.