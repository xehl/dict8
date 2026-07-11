# Phase 0 Validation

## Foundation decisions

- Product target: native macOS application only
- Development/test OS: macOS 26.5 on Apple silicon
- Deployment target: macOS 26.0
- Bundle identifier: `com.xehl.dict8`
- Signing: Xcode automatic signing with Personal Team `94685W8N78`
- Development certificate: Apple Development identity managed by Xcode
- Distribution: personal local use; Developer ID and notarization remain out of scope
- Security configuration: Hardened Runtime enabled; App Sandbox disabled because observed testing showed it blocked Accessibility authorization and the required event tap
- Test target: macOS unit-test bundle hosted by the app target
- Dependencies: Apple frameworks and Swift standard library only

## Hotkey probe

The probe uses an active `CGEvent` tap over `flagsChanged` events so it can observe press/release transitions and suppress the modifier events. It requires Accessibility trust. The probe deliberately consumes Control and Option key codes while running; it is not production code.

This exposes a central tradeoff: consuming a modifier-only chord also prevents ordinary Control and Option shortcuts while the event tap is active. The owner accepted that behavior for personal v0 after manual TextEdit/browser testing; revisit it before any configurable-shortcut or broader-distribution work.

Observed on 2026-07-10: with App Sandbox enabled, dict8 did not appear in Accessibility settings and the probe could not start. After removing App Sandbox, resetting Accessibility consent for `com.xehl.dict8`, and granting access, the event-tap counts advanced. The owner then reported the TextEdit, browser, focus-switch, and secure-field checks as passing. The modifier-only suppression tradeoff is accepted for personal v0.

Official references:

- [CGEvent](https://developer.apple.com/documentation/coregraphics/cgevent)
- [Creating an event tap](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate%28tap%3Aplace%3Aoptions%3Aeventsofinterest%3Acallback%3Auserinfo%3A%29)

## Target and secure-field probe

The probe captures only:

- Frontmost application bundle identifier
- Accessibility role
- Accessibility subrole
- Whether the subrole equals `AXSecureTextField`

It never reads the focused element's value. Accessibility permission is required for AX inspection.

- [AX secure text field subrole](https://developer.apple.com/documentation/applicationservices/kaxsecuretextfieldsubrole)

## Manual validation procedure

1. Build and run dict8 from Xcode using the `dict8` scheme and My Mac destination.
2. Click **Request Accessibility**, grant dict8 access in System Settings, then relaunch the app if macOS requires it.
3. Click **Start Probe**.
4. Focus a blank TextEdit document.
5. Hold and release `Control + Option` once.
6. Confirm the probe records exactly one press and release and captures TextEdit's bundle ID and text role.
7. Confirm the chord does not insert text or invoke an application action.
8. Repeat in a browser text area.
9. Focus a password field containing no real credential, then hold and release the chord.
10. Confirm the subrole is reported as secure and no field value appears anywhere in the UI or logs.
11. While the probe is active, try a normal Control- or Option-based shortcut and record whether suppression is disruptive.

Do not enter a real password or dictate user content during Phase 0 validation.

## Long-recording benchmark

The owner explicitly opted into the authenticated synthetic benchmark on 2026-07-11. The secret-safe harness:

- Generated exact 15-, 120-, and 180-second synthetic English `.m4a` samples.
- Sent each through the pinned primary STT model with per-request ZDR.
- Recorded only content-free duration, byte counts, latency, status, text length, and usage/cost.
- Deleted the API key from shell memory and removed temporary text/audio after completion.
- Did not invoke the fallback because all primary requests succeeded.

All three requests returned HTTP 200 in 1.049–1.927 seconds. The 180-second upload was 998,540 bytes and cost approximately $0.00450. Start v0 without chunking. Because the input intentionally repeated one synthetic phrase and the long outputs were compressed, this result validates transport and timing, not representative long-prose fidelity. Test non-repetitive prose before v0 readiness.

## Validation status

- Xcode project creation: complete
- Automatic Personal Team certificate synchronization: complete
- Signed foundation build: complete (`com.xehl.dict8`, Personal Team signing)
- Unit-test target: complete; `PhaseZeroFoundationTests` passed in Xcode on 2026-07-10 (the Codex sandbox's command-line runner could compile and sign but could not materialize test workers)
- TextEdit/browser hotkey and focus-switch observation: complete, owner-reported on 2026-07-10
- Secure-field observation: complete, owner-reported on 2026-07-10
- App Sandbox/Accessibility compatibility: complete; App Sandbox must remain disabled
- Authenticated OpenRouter benchmarks: complete, explicitly authorized and run on 2026-07-11
- Initial long-recording decision: one request without chunking; revalidate with representative non-repetitive prose before v0 readiness
