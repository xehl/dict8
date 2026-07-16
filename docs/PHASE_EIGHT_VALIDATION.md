# Phase 8 Validation — Full Dictation Pipeline

Phase 8 connects the production `Control + Option` interaction to transcription, conservative cleanup, original-application verification, paste or copy, temporary-data deletion, and Paste Last. The Settings recording, transcription, cleanup, and paste controls remain development harnesses and are disabled while production processing is active.

## Automated verification

Run:

```zsh
xcodebuild -quiet \
  -project dict8/dict8.xcodeproj \
  -scheme dict8 \
  -configuration Debug \
  -derivedDataPath /tmp/dict8-phase8-derived \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The Phase 8 matrix covers cleaned success, raw cleanup fallback, transcription failure, focus-change copy, clipboard and paste-event cache boundaries, audio-deletion retry, content-free fallback notices, cancellation and busy rejection, automatic cutoff, cue failure, and operation-local timing. All provider responses are synthetic; automated tests never call OpenRouter.

## Paid live verification boundary

The following signed tests send speech and transcript text to OpenRouter and consume API credits. Use only harmless synthetic speech. No transcript or audio is intentionally persisted by dict8, but the final text remains on the system clipboard after a successful attempt and may remain in the approved ten-minute in-memory Paste Last cache.

## Preconditions

1. Build and run the signed app from Xcode with `Command + R`.
2. Open Settings and confirm dict8 is Enabled, Microphone and Accessibility are Granted, Global shortcuts is Running, and the API key is configured.
3. Open TextEdit with a blank document and place the insertion point in it.

## TextEdit happy path

1. Hold `Control + Option` and say: “um phase eight should paste this sentence with punctuation”.
2. Release either required modifier.
3. Confirm the capsule closes, the menu-bar status advances through Transcribing, Cleaning up, and Pasting when those stages are long enough to observe, and one cleaned sentence appears in TextEdit.
4. Confirm no transcript appears in Settings and no recording remains ready for playback.
5. Move to a new line and press/release `Command + Control + V`. Confirm the same final result pastes exactly once.

## Original-application protection

1. Focus a blank TextEdit document, hold the chord, and say: “synthetic focus change check”.
2. Release and immediately switch to another application before processing completes.
3. Confirm dict8 does not type into the new application, shows **Copied — focus changed**, and leaves the generated text on the clipboard.
4. Return to TextEdit and use ordinary `Command + V` to confirm the copied text is available.

## Cancellation and secure fields

1. Start a short dictation, release, and immediately Disable dict8 from the menu bar while it is processing. Confirm no text is pasted after Disable and Paste Last is empty after re-enabling.
2. Focus a known password field and hold the chord. Confirm recording is refused before any network request and the clipboard is unchanged.

## Compatibility targets

Repeat one harmless short dictation in each target and confirm exactly one cleaned insertion at the active cursor:

1. ChatGPT
2. Codex
3. Cursor

Claude and representative browser text areas remain part of the broader Phase 9 compatibility matrix, but may also be checked now if convenient.

## Failure semantics covered automatically

- Cleanup exhaustion or suspicious output pastes unchanged raw text and warns.
- STT failure does not call cleanup or paste and does not seed Paste Last.
- Paste-event failure preserves clipboard text and seeds Paste Last; clipboard-write failure does neither.
- Temporary-audio deletion retries once and warns without discarding successfully transcribed text.
- Fallback notifications contain model-stage status but no transcript content.
- Disable, Quit, lock, and sleep cancel without a later paste.

## Result

Passed by owner approval on 2026-07-16. The signed production pipeline was accepted after automated verification of all failure semantics and the manual compatibility procedure. No new permission, entitlement, model, or provider exception was required.
