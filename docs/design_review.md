## Over-Engineering Risks

- **VAD duplicates the user's stop command.** RFC §4 "VAD" adds thresholds, silence timers, timestamps, and a future ONNX path even though RFC §2 defaults to toggle recording and PRD §Non-Goals explicitly accepts batch-per-utterance processing. The second hotkey press already defines the utterance boundary. VAD creates clipping and noisy-room failure modes without solving an MVP requirement.

- **Two recording modes multiply behavior and testing for little value.** RFC §2 "GlobalHotkeyManager" adds push-to-talk and toggle modes, while PRD §Goals specifies one global-hotkey flow. Ship toggle only; add push-to-talk only after users demonstrate a need for it.

- **LLM cleanup is a second product inside the dictation app.** RFC §7 adds endpoint compatibility, model selection, prompting, timeout, and hallucination concerns, while PRD §Goals is local speech recognition and PRD §Goals #4 requires output within two seconds. Remove LLM post-processing from the MVP rather than making core dictation depend on another user-managed service.

- **The settings surface contradicts the stated scope.** RFC §8 defines eight persisted settings, including two LLM fields, two recording/output modes, and a model ID. PRD §Success Criteria names only hotkey, model path, and an LLM toggle. After removing VAD modes and LLM cleanup, the MVP needs only a hotkey and local runtime/model location.

- **Per-character keystroke simulation is an unnecessary text engine.** RFC §6 "Mode B" proposes typing every character with `CGEvent`. That is substantially harder than pasting Unicode text and is especially fragile for mixed Chinese-English input required by PRD §Success Criteria. Use the pasteboard plus one simulated Command-V; leave the transcript in the clipboard when insertion is unavailable.

## Missing Pieces

- **The Python bridge is assumed rather than specified as a deliverable.** RFC §5 names `qwen3-asr-mlx-bridge` and a JSONL protocol, but RFC §Dependencies only requires the upstream runtime and PRD §Constraints says users pre-install it. The RFC must state whether this repository owns the bridge, its exact launch command, supported Python/runtime versions, working directory, environment, and how a script inside a virtual environment is located.

- **The audio format conversion path is absent.** RFC §3 requests PCM 16-bit, 24 kHz mono directly from an `AVAudioEngine` tap, but macOS input devices commonly supply 44.1/48 kHz interleaved or non-interleaved Float32. Specify `AVAudioConverter`, channel mixing, sample-rate conversion, buffer ownership, and handling for device changes and engine interruptions; otherwise PRD §Success Criteria cannot be met reliably across Macs and microphones.

- **Offline readiness is not enforceable.** RFC §8 stores a Hugging Face model ID and RFC §5 starts the model at launch, but PRD §Goals #2 requires 100% offline operation. Require a local model directory, perform a launch-time preflight with network-disabled/local-files-only behavior, and distinguish "runtime missing," "model missing," "loading," and "ready." Never trigger an implicit model download.

- **Permission and target-focus behavior is undefined.** PRD §Constraints mentions Accessibility, but RFC §2 incorrectly implies the hotkey package handles permission prompts and RFC §6 does not define what happens after denial or revocation. Specify microphone authorization, Accessibility preflight/prompting, a copy-only fallback, and whether insertion targets the application that was frontmost when recording started or when transcription completed.

- **The happy-path lifecycle has no concurrency rules.** RFC §5 only lists startup, utterance, response, and shutdown. Define the legal behavior for a hotkey press while the model is loading, recording, or processing; prevent overlapping transcriptions; and decide whether sleep/wake, audio-device removal, or runtime restart returns to idle or reports a recoverable error.

- **Long recordings have no bound or privacy contract.** RFC §2 calls toggle mode better for long dictation and RFC §4 accumulates PCM chunks, but no maximum duration, memory limit, cancellation rule, or temporary-file cleanup is defined. PRD §Non-Goals says this is not a transcription app, so cap an utterance to a documented short-dictation duration and keep audio/transcripts out of logs and persistent storage.

- **Distribution constraints are missing.** RFC §5 requires launching an external Python process and PRD §Success Criteria requires an installable menu bar app. The RFC must choose a non-App-Store, Developer-ID/notarized distribution model or explicitly limit the MVP to source builds; App Sandbox and external-process restrictions materially affect this architecture.

- **The output requirement is internally inconsistent.** PRD §Goals #1 permits cursor insertion or clipboard output, PRD §Success Criteria requires text at the cursor, and RFC §6 defaults to clipboard-only manual paste. Choose one acceptance contract. For a dictation app, automatic paste with clipboard fallback best matches the success criteria.

## Risk Areas

- **The JSONL audio contract is ambiguous and inefficient.** RFC §5 labels each `audio_chunk` as `<base64-wav>`, although a WAV is normally one header plus one complete payload, not one WAV per capture chunk. Base64 also adds memory and copying. A sequential MVP should finalize one WAV file and send one `transcribe` request containing its local path, then receive one terminal response.

- **Subprocess I/O can deadlock or corrupt framing.** RFC §5 uses stdout for protocol messages but says nothing about stderr, runtime logging, partial lines, maximum line size, or pipe draining. Python/model diagnostics printed to stdout would break JSON decoding, and unread stderr can fill its pipe. Reserve stdout for JSONL, continuously drain stderr to a bounded in-memory diagnostic buffer, and reject malformed lines without entering an infinite restart loop.

- **Automatic restart can become a crash loop or duplicate output.** RFC §5 says to restart after a crash without a retry limit or pending-request rule. Restart with bounded backoff, discard the in-flight utterance, and require a fresh user action after the runtime becomes ready; never automatically replay audio that might already have produced text.

- **Energy thresholds will fail across devices and environments.** RFC §4 hard-codes -45/-50 dB values without calibration. Built-in microphones, headsets, gain settings, aircraft noise, and silence differ enough that this can cut sentence endings or never stop, directly threatening PRD §Problem's flight use case. Removing VAD from the toggle MVP eliminates this failure class.

- **Unicode insertion via `CGEvent` is not equivalent to typing in every app.** RFC §6 claims per-character simulation works in any accepting text field. Chinese text, secure fields, Terminal, Electron apps, permission boundaries, keyboard layouts, and focus changes violate that assumption. Treat insertion as best effort and make the clipboard the guaranteed recovery path.

- **The menu bar UI contract relies on unsupported or unreliable presentation details.** RFC §1 specifies a `systemTray` style, but SwiftUI `MenuBarExtra` exposes `.menu` and `.window` styles. Menu bar template images also do not reliably preserve red/yellow tint or pulsing animation. Use the native `.menu` style and distinct SF Symbols or status text for idle, recording, processing, and error states.

- **The latency goal is not measurable as written.** PRD §Goals #4 says under two seconds "from stop-speaking," while RFC §4 may wait 1.5 seconds to decide silence and RFC §7 may add another 0.5-1 second. Define the measurement from the user's stop-hotkey event to clipboard/insertion, after the model reports ready, with fixed short Chinese, English, and mixed-language fixtures on stated Apple Silicon hardware.

- **External runtime drift can break a public release.** RFC §Dependencies leaves `qwen3-asr-mlx-runtime` unversioned even though RFC §5 depends on a specific bridge behavior. Record a tested runtime version/commit and Python version, validate them during preflight, and fail with an actionable compatibility message rather than attempting to support arbitrary installations.

## Simplification Opportunities

- **Use one linear state flow:** `loading -> idle -> recording -> processing -> idle`, plus a single displayed error. This replaces the implicit interactions among RFC §§1-5 and makes hotkey behavior deterministic.

- **Use toggle recording as the utterance boundary.** Remove RFC §4 VAD, RFC §2 push-to-talk, timestamps, silence thresholds, and the future Silero plan. This directly implements PRD §Goals #1 and preserves the batch-per-utterance choice in PRD §Non-Goals.

- **Send one completed local WAV per request.** Replace RFC §5's `audio_chunk`/`end_utterance` sequence with `ready`, `transcribe(audio_path)`, `transcript`, `error`, and `stop`. Sequential processing means request IDs, streaming, and a generalized transport abstraction are unnecessary for the MVP.

- **Make automatic paste the only primary output path.** Replace RFC §6's two modes with pasteboard write plus one Command-V event; if Accessibility is unavailable or insertion fails, keep the text in the clipboard and show "Copied." This satisfies PRD §Success Criteria without a Unicode typing subsystem.

- **Remove LLM post-processing from the initial RFC.** Delete RFC §7 and its settings from RFC §8. It is optional product expansion, not part of proving accurate offline dictation under PRD §Goals.

- **Use one configuration source.** RFC §8 describes `UserDefaults`, while the runtime is otherwise described as an external installation. Keep the user-facing hotkey and local runtime/model path in `UserDefaults`; do not add a parallel `.env` contract or expose model IDs that could cause downloads.

- **Treat the Python process as one concrete adapter, not a framework.** RFC §5 needs a small `Process` wrapper with fixed messages, readiness, timeout, and bounded restart behavior. Avoid protocol layering, backend interfaces, dependency injection containers, or support for multiple ASR engines until a second backend actually exists.

## Top 5 Most Important Corrections

1. **Make the bridge real and minimal.** Amend RFC §5 and §Dependencies to define an owned, versioned Python bridge, its launch environment, stderr/stdout rules, and a single-file `transcribe` request. The current RFC depends on an executable and protocol that are not established by PRD §Constraints.

2. **Delete VAD and push-to-talk from the MVP.** Use the two toggle hotkey presses from RFC §2 as exact recording boundaries; remove RFC §4. This is simpler and avoids the most likely failure in PRD §Problem's noisy-flight scenario.

3. **Specify native audio conversion and bounded recording.** Amend RFC §3 with `AVAudioConverter`, mono/24 kHz/Int16 conversion, device/interruption handling, and a maximum utterance duration. Without this, the ASR input contract and memory behavior are not implementable reliably.

4. **Correct text insertion and permission semantics.** Replace RFC §6 per-character typing with pasteboard plus Command-V, define microphone and Accessibility denial paths, preserve clipboard fallback, and align PRD §Goals with PRD §Success Criteria on whether automatic cursor insertion is required.

5. **Enforce offline, reproducible startup and cut optional systems.** Require a local model directory and tested runtime version in RFC §§5 and 8, prohibit implicit downloads required by PRD §Goals #2, and remove RFC §7 LLM post-processing plus its settings from the MVP.
