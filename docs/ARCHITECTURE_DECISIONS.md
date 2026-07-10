# Architecture Decisions

This file records implementation decisions that must be verified rather than assumed.

## ADR-001 — Global push-to-talk mechanism

**Status:** Open  
**Decision needed by:** Phase 0

Evaluate native approaches for consumed global `Control + Option` press-and-release semantics. Record reliability, modifier-event ordering, key-repeat behavior, Accessibility requirements, lifecycle cleanup, and behavior while dict8 or another app is focused. Keep the service abstract so a future configurable shortcut or chord-emitting external button does not affect orchestration.

## ADR-002 — macOS deployment and signing

**Status:** Partially accepted  
**Decision needed by:** Phase 0

v0 targets the user's current macOS 26.5 Apple-silicon system only and is for personal use. Use a stable signed bundle identity, normal Finder launch, and Launch at Login. The exact bundle identifier, development team/signing workflow, and sandbox configuration remain to be selected in Phase 0.

## ADR-003 — OpenRouter contracts and pinned models

**Status:** Open  
**Decision needed by:** Phase 0

Verify the current official transcription and text endpoint schemas. Record links, request/response shapes, supported audio constraints, retry-relevant status behavior, and exact pinned and fallback model identifiers. Both attempts must enforce ZDR. Each stage permits at most two total model attempts. Do not invent model slugs.

## ADR-004 — Temporary-file lifecycle

**Status:** Accepted  
**Decision needed by:** Phase 3

Use app-owned temporary files with structured cleanup on success, service failure, cancellation, disable, and quit. Remove stale app-owned temporary files at startup after an abnormal prior termination.

## ADR-005 — Clipboard behavior

**Status:** Accepted for v0

Write plain text to the clipboard only after transcription succeeds, then synthesize paste. Clipboard restoration is out of scope. If paste fails after the write, preserve the text on the clipboard and show an actionable error.

## ADR-006 — Original target and secure fields

**Status:** Accepted, pending Phase 0 validation

Capture the originating foreground application when recording begins. Automatically paste only if that application remains foreground; otherwise copy and notify. Refuse operation for a focused element known to be a password or secure field. Validate the reliability and permission requirements of target and secure-field detection on macOS 26.5 before production implementation.

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

**Status:** Open, decision by Phase 0 benchmark

Benchmark the selected STT route with 15-, 120-, and 180-second `.m4a` recordings. If long requests are unreliable, transparently split audio and merge ordered transcripts while preserving the single hold-and-release interaction.

## ADR-011 — Cleanup output safety

**Status:** Accepted

Treat transcript text as untrusted content, not model instructions. Reject empty, substantially expanded, commentary-wrapped, fenced, or obviously instruction-following cleanup output and use the raw transcript fallback. Validate behavior with synthetic fixtures rather than retained user transcripts.
