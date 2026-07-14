# Phase 3 Validation

Phase 3 proves microphone permission, local audio recording, feedback, playback, and temporary-file cleanup. It does not install the global push-to-talk shortcut or send audio to OpenRouter.

## Automated checks

1. Open `dict8/dict8.xcodeproj` in Xcode.
2. Select the `dict8` scheme and **My Mac** destination.
3. Press `Command + U`.
4. Confirm `PhaseZeroFoundationTests`, `PhaseOneAppShellTests`, `PhaseTwoPasteTests`, and `PhaseThreeAudioTests` are green.

Phase 3 tests cover missing permission, double start and stop, the exact 180-second recorder limit, completed-artifact validation, cancellation deletion, cue-before-record ordering, preview deletion, and Disable cleanup.

## Signing and microphone permission

1. Select the blue `dict8` project, the `dict8` target, and **Signing & Capabilities**.
2. Confirm automatic Personal Team signing and Hardened Runtime remain enabled.
3. Under Hardened Runtime **Resource Access**, confirm **Audio Input** is enabled.
4. Press `Command + R`.
5. Open Settings and confirm Microphone shows **Not requested**, **Denied**, or **Granted**, never a silent unknown state.
6. If it is not granted, click **Request Microphone** and approve the system prompt. If previously denied, click **Open Microphone Settings**, enable dict8, relaunch, and click **Refresh Microphone**.
7. Rebuild and relaunch once; confirm the grant remains attached to the signed dict8 identity.

## Short recording, cues, HUD, and playback

1. Open dict8 Settings and click **Start Test Recording**.
2. Confirm a short high cue finishes before the bottom-center microphone HUD appears.
3. Speak ordinary synthetic test prose for 10–15 seconds and confirm elapsed time advances without blocking Settings.
4. Click **Stop Test Recording**.
5. Confirm the HUD disappears, a lower stop cue plays, and the status reports a temporary recorded duration.
6. Click **Play and Delete** and listen to the whole recording.
7. Confirm speech is clear, neither cue is audible inside the recording, playback occurs once, and the status returns to **Ready** after deletion.

## Cancellation and lifecycle cleanup

1. Start another recording, speak briefly, then click **Cancel and Delete**.
2. Confirm the HUD disappears and no Play button becomes available.
3. Repeat, but use **Disable** while recording; re-enable dict8 and confirm no recording is available.
4. Repeat with screen lock and unlock; confirm the recording was cancelled and removed.
5. Stop a short recording so it is ready to play, then quit and relaunch dict8; confirm no recording is available.
6. Stop another short recording and click **Delete Without Playing**; confirm the state returns to **Ready**.

## Long recording and automatic cutoff

1. Start a test recording and speak or read varied prose for at least two minutes.
2. Confirm Settings remains responsive and elapsed time continues updating.
3. Stop, play, and delete the file; confirm the full recording is present and intelligible.
4. For the cutoff test, start another recording and leave it running to 3:00.
5. Confirm recording stops automatically, the normal stop cue plays, and the capsule says **3-minute limit reached — recording stopped**.
6. Play and delete the result. Confirm it contains audio through the limit and neither cue is embedded.

## Expected limitations

- Phase 3 uses Settings buttons rather than the global `Control + Option` shortcut; global push-to-talk is Phase 7.
- Settings becomes the foreground app during the manual flow, so originating-app and recording-time secure-field integration are not validated until the global shortcut exists.
- A stopped manual-test file may exist temporarily for playback, but only one is retained and it expires within ten minutes.
- Cleanup after a process crash or forced termination is deferred to the Phase 9 stale-file sweep.

## Verified result

Phase 3 passed on July 14, 2026:

- `PhaseZeroFoundationTests`, `PhaseOneAppShellTests`, `PhaseTwoPasteTests`, and `PhaseThreeAudioTests` passed.
- The Personal Team build launched with Microphone permission granted and the Audio Input entitlement active.
- Short recordings captured and played intelligible speech while elapsed time and the non-activating HUD remained responsive.
- The distinct start and stop cues played outside the recorded audio.
- Cancel, Disable, playback completion, and explicit deletion removed the temporary test artifact as designed.
- A recording continued beyond two minutes, preserved audio near its end, and played successfully.
- The 180-second limit stopped automatically, retained audio through the cutoff, played the stop cue, and displayed the limit capsule.
