# Phase 9 Validation — Hardening, Metrics, and Local v0 Readiness

Phase 9 adds aggregate content-free metrics, abnormal-exit temporary-audio cleanup, lifecycle regression coverage, and the signed local-release checklist. Automated tests use synthetic values and never call OpenRouter. The paid steps below send harmless speech to OpenRouter and consume API credits.

## Automated verification

Run:

```zsh
xcodebuild -quiet \
  -project dict8/dict8.xcodeproj \
  -scheme dict8 \
  -configuration Debug \
  -derivedDataPath /tmp/dict8-phase9-derived \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The hardening suite verifies versioned metrics persistence, malformed-snapshot recovery without resetting other settings, content-free stored data, success/failure/cancellation accounting, provider-reported cost and latency aggregation, raw-cleanup-fallback counting, stale-file selection, and lifecycle cancellation with cache clearing. Automated tests do not write real transcripts, audio, API keys, or clipboard contents into metrics.

## Current model and ZDR verification

Re-verified against official OpenRouter data on 2026-07-16:

- `openai/whisper-large-v3` and `google/chirp-3` are present in the filtered transcription catalog as `audio -> transcription` models.
- `google/gemini-2.5-flash-lite` and `anthropic/claude-haiku-4.5` are present in the general model catalog with text output and temperature support.
- The live ZDR endpoint catalog contains at least one endpoint for every configured identifier.
- Runtime requests continue to set `provider.zdr: true`; catalog presence never relaxes the fail-closed request rule.

Official sources:

- [Models API](https://openrouter.ai/api/v1/models)
- [ZDR endpoint catalog](https://openrouter.ai/api/v1/endpoints/zdr)
- [Zero Data Retention](https://openrouter.ai/docs/guides/features/zdr)

## Signed build preconditions

1. Quit every running copy of dict8, including any build launched by Xcode.
2. In Xcode, select the dict8 project, then the dict8 application target.
3. Under Signing & Capabilities, confirm the Personal Team is selected, **Automatically manage signing** is enabled, Hardened Runtime is present, and App Sandbox is absent.
4. Confirm the target shows marketing version `0.1.0` and build `1`.
5. Select **Product → Scheme → Edit Scheme**, select **Run**, and choose the **Release** build configuration for this validation run.
6. Press `Command + R`, then confirm Settings shows Enabled, Microphone **Granted**, Accessibility **Granted**, Global shortcuts **Running**, and the API key configured.

Do not run the Xcode copy and an installed `/Applications/dict8.app` copy at the same time. v0 intentionally has no single-instance lock.

## Metrics smoke test

1. Note all values in Settings → Usage metrics.
2. Open TextEdit with a blank document.
3. Hold `Control + Option`, dictate one harmless sentence, and release.
4. Confirm exactly one result reaches TextEdit and **Dictation requests** and **Successful** each increase by one.
5. Confirm **Audio minutes**, average transcription latency, average cleanup latency, and average end-to-end latency update.
6. Confirm reported costs remain numeric and nondecreasing. They may remain unchanged when OpenRouter omits cost metadata.
7. Quit and relaunch dict8. Confirm the aggregate values persist and no transcript is shown anywhere in Settings.

## Long-form and cutoff checks — paid

Use harmless, non-repetitive prose. Do not save the transcript in this repository.

1. In TextEdit, record approximately 120 seconds covering several distinct topics or numbered sections.
2. Release, and confirm the UI remains responsive, exactly one complete result arrives, and the opening, middle, and final ideas are represented in order.
3. Confirm the request and audio totals increase once, not once per model attempt.
4. Start another recording and keep holding the chord past three minutes.
5. Confirm recording stops automatically at about 180 seconds, the normal stop cue and **3-minute limit reached** capsule appear, processing begins once, and releasing the still-held chord does not start or stop another recording.

## Lifecycle and cleanup checks

1. Start a dictation, release, and immediately Disable dict8 while it is processing. Confirm no later paste occurs, Paste Last is cleared, and the request appears as Cancelled rather than Failed.
2. Repeat, then lock the screen during processing. Unlock and confirm no later paste occurs and Paste Last is empty.
3. Repeat with system sleep if convenient; confirm the same result after wake.
4. Quit dict8 during recording or processing, relaunch it, and confirm Settings → **Startup audio cleanup** reads **No stale recordings** or reports a content-free removed-file count.
5. Confirm no completed recording remains under the current user's temporary `dict8-recordings` directory after successful and failed operations.

## Compatibility matrix — paid

For each installed target, focus a blank normal text field, dictate one harmless short sentence, release, and confirm exactly one cleaned plain-text insertion. Record Pass, Not installed, or a concise content-free limitation.

| Target | Result | Content-free note |
|---|---|---|
| TextEdit | Pending | |
| ChatGPT | Pending | |
| Codex | Pending | |
| Cursor | Pending | |
| Claude | Pending | |
| Safari text area | Pending | |
| Chrome text area | Pending | |

For at least one target, switch to another app immediately after release. Confirm dict8 copies and notifies instead of pasting into the new app. Also verify a known password field refuses recording and leaves the clipboard unchanged.

## Routine-use and local installation

1. Confirm start and stop sounds are subtle and the microphone capsule appears without stealing focus.
2. Confirm a successful dictation can be pasted once with `Command + Control + V`, then Disable and re-enable dict8 and confirm Paste Last is empty.
3. Confirm primary-model fallback notifications are content-free if a fallback is encountered naturally; automated coverage is sufficient if no provider failure occurs during this run.
4. Restore the scheme's Run configuration to **Debug** if desired, choose **Product → Archive** for the signed local candidate, and reveal the archived app in Finder.
5. Quit all dict8 copies, replace `/Applications/dict8.app` with the archived candidate, and launch only that installed copy.
6. Confirm Keychain API-key status, permissions, dictation, and Launch at Login still work from the installed app.
7. Log out and back in, or restart once, and confirm dict8 launches without Xcode or a shell and accepts the shortcut.

Personal v0 ends at a signed local app. Do not notarize, tag, publish a release, add update infrastructure, or enroll in the paid Apple Developer Program for this checklist.

## Privacy and logging audit

Run the repository scans below and inspect every match:

```zsh
rg -n 'print\(|debugPrint\(|NSLog\(|os_log|Logger\(' dict8 Supporting Tests Scripts
rg -n 'OPENROUTER_API_KEY|Authorization|Bearer ' . --glob '!docs/**' --glob '!PRD.md' --glob '!AGENTS.md'
rg -n 'transcript|clipboard|input_audio|base64' dict8/dict8/Services/MetricsService.swift Tests/Unit/PhaseNineHardeningTests.swift
```

Pass when production code contains no content-bearing logging, no secret is committed, the metrics implementation contains no transcript/audio/clipboard fields, and the synthetic privacy test passes. Documentation may name forbidden data categories without storing actual user content.

## Acceptance record

Pending owner completion of the signed manual matrix. Record only pass/fail, installed/not-installed status, approximate durations, aggregate metric behavior, and content-free limitations. Never paste transcript text, API keys, audio, screenshots containing dictated content, or clipboard contents into this file.
