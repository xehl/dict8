# Phase 7 Validation — Global Push-to-Talk

Phase 7 installs the production global shortcut router. Holding `Control + Option` captures the originating target, plays the start cue, starts one recording, and shows the microphone capsule. Releasing either required modifier stops once, plays the stop cue, and leaves temporary audio ready in Settings. Phase 8 will connect release to automatic transcription, cleanup, and paste.

The same event tap owns `Command + Control + V`, preventing competing listeners. It ignores dict8's synthetic paste events, rejects push-to-talk when `Command` or `Shift` is present, allows Caps Lock and `fn`, and waits for a full `Control`/`Option` release after interruptions or automatic stop.

## Automated verification

Run:

```zsh
xcodebuild -quiet \
  -project dict8/dict8.xcodeproj \
  -scheme dict8 \
  -configuration Debug \
  -derivedDataPath /tmp/dict8-phase7-derived \
  CODE_SIGNING_ALLOWED=NO \
  test
```

The Phase 7 suite covers both modifier orders and sides, balanced suppression, duplicate transitions, exact-chord filtering, interruption recovery, start-while-held behavior, Paste Last coexistence, synthetic-event rejection, unrelated-key pass-through, known-secure-field refusal, rapid-release cancellation, and normal one-start/one-stop coordination.

## Manual verification

Build and run the signed app with `Command + R`, then open Settings. Confirm:

- dict8 is Enabled.
- Microphone and Accessibility are Granted.
- Global shortcuts is Running.
- No new entitlement or permission prompt appears beyond the existing Microphone and Accessibility permissions.

Use a blank TextEdit document for the following checks:

1. Focus TextEdit. Hold left `Control`, then left `Option`; speak briefly; release either key. Confirm one start cue, one microphone capsule, one stop, and no character or foreground shortcut produced by the chord. In Settings, confirm the recording is ready. Delete it before the next check.
2. Repeat with `Option` pressed before `Control`, then with right-side modifiers or mixed left/right modifiers. Each valid chord starts and stops exactly once.
3. Tap the chord very quickly. Confirm no recording or capsule remains stuck and no temporary recording is left ready.
4. Hold `Command + Control + Option`, then `Shift + Control + Option`. Confirm neither starts recording. Repeat with Caps Lock enabled and plain `Control + Option`; confirm it does start. If your keyboard exposes `fn` in event flags, confirm `fn` also does not block the chord.
5. While recording, type an unrelated letter. Confirm dict8 does not swallow that key. Cancel or delete the test recording afterward.
6. In Settings, click **Paste Test Text in 3 Seconds**, focus TextEdit, and let it seed the cache. Move to a blank line and press/release `Command + Control + V`. Confirm Paste Last still inserts exactly once and does not type a literal `v`.
7. Begin holding push-to-talk, then disable dict8 using the menu-bar UI. Re-enable it while the physical keys are still down. Confirm recording stops or cancels, and no new recording starts until both `Control` and `Option` have been released and a fresh chord is pressed.
8. Start dict8 while either required modifier is already held, or revoke/restore Accessibility while holding the chord. Confirm it waits for a full release before accepting a new press.
9. Hold a recording through the three-minute cutoff. Confirm the normal stop cue and the content-free limit capsule appear once. Keep holding for several more seconds and confirm recording does not restart. Fully release, press a fresh chord, and confirm it works again.
10. Focus a known password field and press the chord. Confirm recording does not start, the clipboard is untouched, and dict8 shows the secure-field refusal capsule/error without reading or displaying field contents.

VoiceOver uses `Control + Option` as its modifier. If VoiceOver is enabled, treat the collision as a documented v0 limitation rather than attempting both tools' commands simultaneously.

## Content and cost boundary

The shortcut checks are local and do not call OpenRouter. Do not click **Transcribe and Delete** unless a paid transcription check is intentionally desired. Test speech and temporary audio remain subject to the Phase 3 deletion controls.

## Result

Passed on 2026-07-15. The owner confirmed the signed shortcut flow, recording capsule, stop behavior, cutoff/rearm behavior, Paste Last coexistence, and secure-field handling. A completed Settings transcript initially prevented a new shortcut recording; the coordinator guard was corrected, covered by a regression test, and the owner confirmed the signed fix. The capsule has a small perceptible startup delay because the start cue intentionally finishes before recording and HUD presentation; this was accepted for Phase 7.
