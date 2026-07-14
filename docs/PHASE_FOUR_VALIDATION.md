# Phase 4 Validation

Phase 4 proves the shared OpenRouter networking foundation without sending audio or text to a live API. Speech-to-text payload construction and transcript decoding begin in Phase 5.

## Automated verification

Run the complete hosted macOS test suite:

```bash
xcodebuild -quiet \
  -project dict8/dict8.xcodeproj \
  -scheme dict8 \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/dict8-phase4-tests \
  CODE_SIGNING_ALLOWED=NO \
  test
```

`PhaseFourOpenRouterTransportTests` uses only generated secrets, synthetic content, and an in-memory transport. It verifies authentication, mandatory ZDR, same-model provider fallback policy, explicit second-model fallback, permanent and transient HTTP failures, `Retry-After`, cancellation, total stage deadlines, and content-free errors.

No live API test runs automatically or consumes OpenRouter credits.

## Manual verification

1. Open `dict8/dict8.xcodeproj` in Xcode.
2. Select the `dict8` scheme and **My Mac** destination.
3. Press **Command + U**.
4. Confirm `PhaseZeroFoundationTests`, `PhaseOneAppShellTests`, `PhaseTwoPasteTests`, `PhaseThreeAudioTests`, and `PhaseFourOpenRouterTransportTests` are green.
5. Press **Command + R** and open dict8 Settings.
6. Confirm the OpenRouter API-key status still reports **Configured in Keychain** or **Development override active**, without displaying the key.
7. Confirm launching the app performs no OpenRouter request and consumes no API credits; Phase 4 has no live pipeline action.

## Verified result

- Full unsigned unit suite: passed on 2026-07-14.
- Public ZDR catalog: all four configured model identifiers present on 2026-07-14.
- Live paid request: intentionally not run; deferred until the Phase 5 transcription adapter exists.
