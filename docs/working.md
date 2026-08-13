# Working Log

## 2026-08-13

- Scaffolded project structure: AGENTS.md, README.md, .gitignore, .env.example, docs/prd.md, docs/rfc.md
- Created directory layout: src/, docs/, scripts/, tests/, Assets/
- Initialized git repo with master branch
- Drafted PRD with success criteria focused on offline dictation
- Drafted RFC with 8-component architecture, subprocess JSONL bridge, energy-based VAD MVP
- Identified qwen3-asr-mlx-runtime as the ASR backend (subprocess, not in-process MLX)
- Decided against reusing VoiceFlowKit (cloud-transport design incompatible with local-only app)

## Lessons Learned

(none yet — to be filled during implementation)