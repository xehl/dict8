# Phase 2 Validation

Phase 2 proves safe focused-application paste behavior. It does not record audio or call OpenRouter.

## Automated checks

1. Open `dict8/dict8.xcodeproj` in Xcode.
2. Select the `dict8` scheme and **My Mac** destination.
3. Press `Command + U`.
4. Confirm `PhaseZeroFoundationTests`, `PhaseOneAppShellTests`, and `PhaseTwoPasteTests` are green.

The Phase 2 build-for-testing command also completes with strict Swift 6 concurrency checking. Command-line test execution is unavailable inside the Codex sandbox because macOS blocks access to `testmanagerd`, so the Xcode test run is the authoritative execution check.

## Signing and Accessibility identity

1. Select the blue `dict8` project in Xcode's Project navigator.
2. Select the `dict8` target, then **Signing & Capabilities**.
3. Confirm **Automatically manage signing** is enabled and the Team is Eric Lee's **Personal Team**. Do not use **Sign to Run Locally**.
4. Build and run with `Command + R`.
5. Open dict8 Settings and confirm Accessibility shows **Granted**. If it does not, click **Request Accessibility**, approve the current signed build in **System Settings → Privacy & Security → Accessibility**, relaunch dict8, and click **Refresh**.
6. Rebuild and relaunch once more. Confirm Accessibility remains granted and no repeated codesign password prompt appears.

Changing the signing identity changes the identity macOS uses for Accessibility approval. If the Team or certificate changes later, remove the stale dict8 entry from Accessibility and approve the newly signed build.

## Focused TextEdit paste and Paste Last

1. Open a blank TextEdit document and leave its insertion point visible.
2. In dict8 Settings, click **Paste Test Text in 3 Seconds**.
3. Focus the TextEdit document before the countdown ends.
4. Confirm `dict8 paste test` appears once and Settings later reports **Test text pasted** (or the verified-target message if the field's secure status was unavailable).
5. Move the insertion point to a new line and press, then release, `Command + Control + V`.
6. Confirm the same text appears once and a non-activating **Pasted last dictation** capsule briefly appears.
7. Confirm the shortcut's `V` keystroke is consumed and does not type a literal `v`.

## Safe refusal and fallback behavior

1. In a known password field, invoke Paste Last with `Command + Control + V`.
2. Confirm dict8 does not paste and does not replace the clipboard.
3. Remove dict8 from Accessibility, relaunch it, and try the Settings test again.
4. Confirm no paste occurs, the clipboard is unchanged, and Settings shows an actionable Accessibility error with buttons to request permission or open System Settings.
5. Restore Accessibility approval, relaunch, and click **Refresh** before continuing.

Original-application identity, focus-change copy-without-paste behavior, unknown secure-state handling, and synthetic-event failure fallback are covered by `PhaseTwoPasteTests`. The Settings test has no artificial post-capture delay, so reliably forcing that race by hand is not part of the manual UI harness.

## Cache clearing

1. Seed Paste Last using the Settings test.
2. Disable dict8, re-enable it, and invoke `Command + Control + V`; confirm **No recent dictation** appears and nothing is pasted.
3. Seed it again, quit and relaunch dict8, then invoke Paste Last; confirm the cache is empty.
4. Seed it again, lock and unlock the Mac, then invoke Paste Last; confirm the cache is empty.
5. Automated tests cover ten-minute expiry, replacement, session resignation, screen sleep, system sleep, Disable, and Quit.

## Expected limitations

- Phase 2 uses only fixed synthetic test text; recording begins in Phase 3.
- Secure-field refusal applies to the paste path now. Recording-time refusal becomes testable when recording exists in Phase 3.
- The cache is intentionally memory-only, holds one value, and lasts no longer than ten minutes.
- `Command + Control + V` is fixed for v0 and works only while dict8 is enabled with Accessibility permission.
- The clipboard is intentionally left containing the output if synthetic event creation fails.

## Verified result

Phase 2 passed on July 14, 2026:

- `PhaseZeroFoundationTests`, `PhaseOneAppShellTests`, and `PhaseTwoPasteTests` passed.
- The Personal Team build launched with Accessibility granted.
- The delayed Settings action pasted the fixed test text into TextEdit exactly once.
- `Command + Control + V` pasted the cached result exactly once, consumed the literal `v`, and displayed non-activating feedback.
- Disable cleared the cache, and Paste Last reported that no recent result was available after re-enabling.
- A known password field refused Paste Last without inserting text.
