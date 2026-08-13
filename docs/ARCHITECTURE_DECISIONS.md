# Architecture Decisions

This file records implementation decisions that must be verified rather than assumed.

## ADR-001 — Global push-to-talk mechanism

**Status:** Validated for Phase 7

Use one active `CGEvent` tap for both push-to-talk and Paste Last so two listeners cannot disagree about suppression or lifecycle. Either left/right `Control` plus either left/right `Option` completes push-to-talk. Reject `Command` and `Shift`; allow Caps Lock and `fn`. Consume only the second required modifier transition and its corresponding release, preserving balanced input for the foreground app while passing unrelated keys. Emit one press and one release, suppress duplicates, and require both modifier families to be physically released before rearming after interruption, disable/re-enable, listener start while held, or the automatic cutoff.

On 2026-07-10, the Phase 0 tap passed press/release and target-capture checks in TextEdit and a browser. `Control + Option` is also the macOS VoiceOver modifier, so dict8's v0 shortcut conflicts with VoiceOver commands while dict8 is enabled. This is accepted for the owner's personal v0; configurable shortcuts and external-button input remain future scope. Keep the monitor behind `HotkeyMonitoring`.

## ADR-002 — macOS deployment and signing

**Status:** Accepted for personal v0 development

v0 is developed and tested on macOS 26.5 for Apple silicon with a macOS 26.0 deployment target. The bundle identifier is `com.xehl.dict8`. Use Xcode automatic signing with Personal Team `94685W8N78` and Hardened Runtime. App Sandbox must remain disabled: in the observed Phase 0 test, sandboxing prevented dict8 from appearing in Accessibility settings and the event tap could not run; removing it allowed authorization and the probe to work. Developer ID distribution, notarization, and Mac App Store distribution remain out of scope.

## ADR-003 — OpenRouter contracts and pinned models

**Status:** Contracts, candidates, shared transport, and STT adapter validated

The verified candidates are `openai/whisper-large-v3` with `google/chirp-3` fallback for STT, and `google/gemini-2.5-flash-lite` with `anthropic/claude-haiku-4.5` fallback for cleanup. They appeared again in the relevant public Models API queries with ZDR filtering on 2026-07-14. Account-level OpenAI and Google ZDR must cover STT; cleanup additionally enforces ZDR per request. Each stage permits at most two total model attempts. Re-verify before changing either pipeline and validate quality/latency through explicit manual tests.

## ADR-004 — Temporary-file lifecycle

**Status:** Accepted for Phase 3

Use app-owned temporary files with structured cleanup on success, service failure, cancellation, replacement, Disable, Quit, screen lock, and sleep. The Phase 3 manual test may retain one stopped recording only until Play and Delete, explicit Delete, ten-minute expiry, or lifecycle cleanup. Startup sweeping after abnormal termination remains Phase 9 scope.

## ADR-005 — Clipboard behavior

**Status:** Accepted for v0

Write plain text to the clipboard only after transcription succeeds, then synthesize paste. Clipboard restoration is out of scope. If paste fails after the write, preserve the text on the clipboard and show an actionable error.

## ADR-006 — Original target and secure fields

**Status:** Phase 0 prototype validated

Capture the originating foreground application when recording begins. Automatically paste only if that application remains foreground; otherwise copy and notify. Refuse operation for a focused element known to be a password or secure field. On 2026-07-10, the owner reported successful originating-target retention and secure-field identification in the Phase 0 probe with Accessibility granted and App Sandbox disabled.

## ADR-007 — Last-dictation cache

**Status:** Accepted

Support `Command + Control + V` as Paste Last Dictation. Retain only the last successful output in process memory for at most ten minutes. Clear it on expiry, replacement, Disable, Quit, or screen lock. Never persist, log, or synchronize it. This narrow recovery feature is not transcript history.

## ADR-008 — API-key storage and privacy routing

**Status:** Accepted

Store the normal-launch API key in macOS Keychain, with `OPENROUTER_API_KEY` as a development override. Require account-level OpenAI and Google ZDR for STT, enforce per-request ZDR for cleanup, and disclose that content leaves the Mac for processing.

## ADR-009 — Recording feedback HUD

**Status:** Accepted

Play distinct, quiet synthesized cues of approximately 80 milliseconds. Finish the start cue before recording begins and stop recording before playing the stop cue so cues are not recorded. Show a small non-activating, click-through microphone HUD at the bottom-center of the active display while recording, then replace the microphone with a spinner while the production payload is processing. Transient content-free feedback temporarily replaces the spinner and restores it if processing is still active. The HUD must never take target focus and must close on every terminal or cancellation path.

## ADR-010 — Long recording strategy

**Status:** Accepted for initial v0 implementation

Begin with one STT request per recording and no chunking. On 2026-07-11, exact 15-, 120-, and 180-second synthetic `.m4a` files all returned HTTP 200; measured request latency was 1.049–1.927 seconds, and the 180-second upload was 998,540 bytes. The request included `provider.zdr: true`, but OpenRouter later clarified that the transcription endpoint does not apply this per-request data-policy control; account-level ZDR now supplies that guarantee. The repeated synthetic phrase caused compressed long-form output, so that benchmark validated transport, payload size, and timing rather than representative fidelity. On 2026-07-14, the owner passed the Phase 5 manual test with more than two minutes of representative non-repetitive speech and reported no material compression or missing-section issue. Later real-world compression prompted deterministic temperature and coverage diagnostics. One request per recording remains accepted while this evidence is gathered; add transparent ordered chunking only if representative failures persist.

## ADR-011 — Cleanup output safety

**Status:** Accepted

Treat transcript text as untrusted content, not model instructions. Reject empty, substantially expanded, commentary-wrapped, fenced, or obviously instruction-following cleanup output and use the raw transcript fallback. Validate behavior with synthetic fixtures rather than retained user transcripts.

## ADR-012 — Automatic recording cutoff

**Status:** Accepted for v0

The recorder enforces the 180-second limit and returns a completed artifact without waiting for UI timing. Use the normal stop cue and a non-content capsule reading “3-minute limit reached — recording stopped.” When global push-to-talk arrives in Phase 7, the hotkey state machine must ignore the still-held chord until both modifiers are released.

## ADR-013 — OpenRouter routing and retry ownership

**Status:** Accepted for v0

Cleanup requests set `provider.zdr` to `true`; STT relies on required account-level OpenAI and Google ZDR because its endpoint does not apply per-request data-policy controls. OpenRouter may route one explicitly requested model across multiple provider endpoints, preserving model behavior while improving availability under the applicable privacy policy. dict8 never supplies OpenRouter's automatic multi-model routing fields; it sends the centrally configured fallback model itself only after an eligible network failure or HTTP 408, 429, 500, 502, 503, or 504 response. HTTP 404 is a terminal configuration error. The caller supplies one deadline for the entire stage, including any valid `Retry-After` wait and the fallback attempt.

## ADR-014 — Portable STT response and validation transcript

**Status:** Accepted for Phase 5

Use the common transcription JSON response rather than provider-specific `verbose_json`, because the explicit fallback is not guaranteed to support OpenAI-compatible duration and timestamp extensions. Require trimmed non-empty text; treat all usage fields independently as optional. Send the English language hint, pin temperature to `0`, and give the primary plus explicit fallback one shared 45-second deadline. Compare provider-reported audio seconds with local duration and flag unusually sparse long transcripts as content-free diagnostics without discarding text or automatically spending a second model attempt.

The Settings “Transcribe and Delete” action is a development-validation surface, not transcript history or preview-before-paste. Its read-only transcript exists only in memory and clears explicitly, after two minutes, when Settings closes, on replacement, Disable, Quit, lock, or sleep. The coordinator owns and deletes temporary audio; the provider adapter never owns file deletion.

## ADR-015 — Cleanup request, validation, and raw fallback

**Status:** Validated for Phase 6

Send the fixed PRD system prompt and the raw transcript as a separate user message through a standard non-streaming chat completion with `"reasoning": {"effort": "none"}`. Use temperature `0.1`, no tools, plugins (except Auto Router settings where configured), or structured response format, and a 10-second deadline. Bound output with `max_completion_tokens = min(1024, max(48, ceil(UTF8 bytes / 3) + 32))`.

Trim and reject empty or incomplete output. Treat Markdown fences, unrequested commentary wrappers, substantial expansion, excessive novel vocabulary, and low source-word retention as suspicious. Suspicious successful output is not eligible for another model attempt; the coordinator uses the unchanged raw transcript and shows a content-free warning. Cancellation produces no fallback output. Raw text exists only for the active operation except when the final successful pipeline result later enters the approved Paste Last cache.

The Settings cleanup harness uses source-controlled synthetic fixtures plus optional memory-only input. Input and output clear after two minutes, on replacement, Settings close, Disable, Quit, lock, or sleep. It is a validation surface, not transcript history.

On 2026-07-15, all six paid live fixtures passed, including prompt-injection and legitimate meta-language cases. No validator relaxation or model change was required.

## ADR-016 — Production pipeline ownership and terminal cleanup

**Status:** Validated for Phase 8

Each production recording is owned by one coordinator task after `AudioRecording.stop()` returns it. The task waits for the stop cue, transcribes, deletes audio immediately after STT no longer needs it, cleans with unchanged-raw fallback, verifies the originating application through the paste service, and then pastes or copies. Disable, Quit, screen lock, and sleep cancel the task; cancellation does not invoke cleanup fallback or paste. Settings validation tasks remain separate and cannot start while production processing is active.

Temporary audio deletion receives one immediate retry. After successful STT, a persistent content-free deletion warning does not block delivery of the resulting text. If STT and deletion both fail, show a combined sanitized error. Cache the final text only after it reaches the clipboard: successful paste, focus-change copy, or paste-event failure after clipboard write. Never cache after STT failure, secure refusal, clipboard-write failure, or cancellation.

Provider fallback, raw cleanup fallback, focus-copy, cue failure, and temporary-file failure use content-free feedback. Operation-local transcription, cleanup, paste, and total durations are emitted only to an in-memory callback in Phase 8; Phase 9 owns aggregate persistence and Settings metrics.

## ADR-017 — Aggregate metrics and abnormal-exit cleanup

**Status:** Implemented for Phase 9; signed manual validation pending

Persist one versioned, typed `UserDefaults` snapshot containing only counts, durations, provider-reported costs, stage totals, and one stable content-free issue category. Count a request when a stopped production recording enters the pipeline. Count success once final text reaches the clipboard, including focus-change copy and a synthetic-paste event failure after a successful clipboard write; count failure when no final text reaches the clipboard. Derive cancellation as requests minus successes and failures so an interrupted or abnormally terminated request needs no separate write. Cost totals are explicitly partial when OpenRouter omits metadata. Invalid persisted data resets only the metrics key and surfaces a non-blocking storage status.

At launch, inspect only the shallow app-owned `dict8-recordings` temporary directory. Delete regular `.m4a` files whose modification time is more than 15 minutes old, retrying a failed deletion once. Do not traverse subdirectories or delete other extensions. This sweep limits abnormal-exit residue without treating the temporary directory as general application storage.

The local v0 candidate is marketing version `0.1.0`, build `1`. Personal Team signing, App Sandbox disabled, and Hardened Runtime remain unchanged. Notarization, releases, tags, and a single-instance lock are out of scope; do not run an Xcode build and an installed `/Applications` copy simultaneously.
