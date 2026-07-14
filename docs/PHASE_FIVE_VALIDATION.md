# Phase 5 Validation — Speech-to-Text Adapter

Phase 5 converts one completed `.m4a` recording into a validated transcript through OpenRouter's dedicated transcription endpoint. The Settings flow is intentionally temporary and is not the production push-to-talk pipeline or transcript history.

## Automated coverage

Run:

```sh
xcodebuild -quiet \
  -project dict8/dict8.xcodeproj \
  -scheme dict8 \
  -configuration Debug \
  -destination 'platform=macOS' \
  test CODE_SIGNING_ALLOWED=NO
```

`PhaseFiveSpeechToTextTests` verifies:

- dedicated endpoint request construction with raw base64 M4A audio and English hint
- omission of temperature, `verbose_json`, and automatic multi-model routing fields
- the shared 45-second deadline and centrally pinned model pair
- trimmed non-empty transcript decoding
- optional and partially malformed usage metadata
- content-free explicit-fallback metadata
- empty output, malformed response, typed transport failure, and invalid local audio

The Phase 3 coordinator suite additionally verifies that success and failure both delete the temporary audio, that only success exposes transient in-memory text, and that closing Settings clears that text.

## Privacy behavior

- The adapter reads audio and constructs base64 only inside the transcription call.
- The adapter does not persist or log audio, base64, transcript text, or response bodies.
- The coordinator owns deletion of the recorded file on success, failure, cancellation, Disable, Quit, lock, and sleep.
- A successful validation transcript is read-only, memory-only, and cleared after two minutes, on explicit Clear, replacement, Settings close, or lifecycle cleanup.
- Usage and fallback displays remain content-free.

## Manual live verification

These actions send audio to OpenRouter and consume API credits. The owner authorized the short and longer-than-two-minute checks on 2026-07-14.

1. Build and run the normally signed `dict8` scheme from Xcode with `Command + R`.
2. Open Settings and confirm the OpenRouter API key says **Configured in Keychain**.
3. In **Audio recording test**, record 10–20 seconds of natural English containing a distinctive opening and closing phrase.
4. Stop, choose **Transcribe and Delete**, and confirm:
   - status reaches **Transcribed and deleted audio**;
   - a non-empty, accurate transcript appears;
   - the opening and closing phrases are present;
   - model, attempt, latency, recorded duration, and reported cost remain content-free;
   - no Last error appears.
5. Clear the transcript.
6. Record at least 2:05 of non-repetitive natural prose. Include unique markers near the beginning, around one minute, and near the end—for example “amber beginning,” “cedar midpoint,” and “violet ending.”
7. Stop and choose **Transcribe and Delete**. Confirm all three markers and the major intervening ideas appear in order. Minor punctuation or word-level errors are acceptable; missing sections, severe compression, reordering, timeout, or an empty result fails the long-form gate.
8. Confirm **Clear Transcript** removes the text immediately.
9. Make one short recording, transcribe it, close Settings, reopen Settings, and confirm the transcript is gone.
10. Do not copy transcript content into test logs or documentation. Report only content-free outcome, duration, model/fallback status, latency, and cost when visible.

If the long-form check fails, stop Phase 5. Do not add chunking implicitly; review ADR-010 and design ordered chunking as a deliberate scope change.

## Pending result

- Automated suite: passing on 2026-07-14
- Short live recording: passed by owner on 2026-07-14
- Representative recording longer than two minutes: passed by owner on 2026-07-14; no material compression or missing-section issue reported
- Explicit live fallback: intentionally not forced; covered deterministically
