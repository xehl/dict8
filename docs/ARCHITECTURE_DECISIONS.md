# Architecture Decisions

This file records implementation decisions that must be verified rather than assumed.

## ADR-001 — Global push-to-talk mechanism

**Status:** Phase 0 prototype validated

Phase 0 uses an active `CGEvent` tap over modifier events because it exposes separate transitions and can suppress delivery. On 2026-07-10, the owner reported successful press/release and target capture checks in TextEdit and a browser. Consuming a modifier-only chord can disable ordinary Control/Option shortcuts while active; that tradeoff is accepted for personal v0 but remains a reason to keep the eventual service abstract for a future configurable shortcut or chord-emitting external button.

## ADR-002 — macOS deployment and signing

**Status:** Accepted for personal v0 development

v0 is developed and tested on macOS 26.5 for Apple silicon with a macOS 26.0 deployment target. The bundle identifier is `com.xehl.dict8`. Use Xcode automatic signing with Personal Team `94685W8N78` and Hardened Runtime. App Sandbox must remain disabled: in the observed Phase 0 test, sandboxing prevented dict8 from appearing in Accessibility settings and the event tap could not run; removing it allowed authorization and the probe to work. Developer ID distribution, notarization, and Mac App Store distribution remain out of scope.

## ADR-003 — OpenRouter contracts and pinned models

**Status:** Contracts and candidates verified; STT live route verified, cleanup live behavior pending

The verified candidates are `openai/whisper-large-v3` with `google/chirp-3` fallback for STT, and `google/gemini-2.5-flash-lite` with `anthropic/claude-haiku-4.5` fallback for cleanup. They appeared in the relevant public Models API queries with ZDR filtering on 2026-07-10. Both attempts must enforce per-request ZDR, and each stage permits at most two total model attempts. Re-verify before Phase 4–6 and validate quality/latency through explicit manual tests.

## ADR-004 — Temporary-file lifecycle

**Status:** Accepted  
**Decision needed by:** Phase 3

Use app-owned temporary files with structured cleanup on success, service failure, cancellation, disable, and quit. Remove stale app-owned temporary files at startup after an abnormal prior termination.

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

Store the normal-launch API key in macOS Keychain, with `OPENROUTER_API_KEY` as a development override. Enforce OpenRouter ZDR on every STT and cleanup attempt and disclose that content leaves the Mac for processing.

## ADR-009 — Recording feedback HUD

**Status:** Accepted

Play an unobtrusive cue before recording starts and after recording stops so cues are not recorded. Show a small non-activating, click-through microphone HUD at the bottom-center of the active display while recording. The HUD must never take target focus.

## ADR-010 — Long recording strategy

**Status:** Accepted for initial v0 implementation

Begin with one STT request per recording and no chunking. On 2026-07-11, exact 15-, 120-, and 180-second synthetic `.m4a` files all succeeded through the primary ZDR route with HTTP 200; measured request latency was 1.049–1.927 seconds, and the 180-second upload was 998,540 bytes. The repeated synthetic phrase caused compressed long-form output, so this validates transport, payload size, and timing rather than representative fidelity. Re-test non-repetitive long prose before v0 readiness and add transparent ordered chunking if real-prose fidelity or reliability fails.

## ADR-011 — Cleanup output safety

**Status:** Accepted

Treat transcript text as untrusted content, not model instructions. Reject empty, substantially expanded, commentary-wrapped, fenced, or obviously instruction-following cleanup output and use the raw transcript fallback. Validate behavior with synthetic fixtures rather than retained user transcripts.
