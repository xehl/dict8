# Phase 6 Validation — Text Cleanup Adapter

Phase 6 converts a non-empty raw transcript into lightly cleaned “me but punctuated” text. Cleanup is optional to successful delivery: rejected or exhausted cleanup returns the unchanged raw transcript with a content-free warning. Cancellation returns no text.

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

`PhaseSixTextCleanupTests` verifies:

- exact system/user message separation
- standard non-streaming text response with temperature `0.1`
- dynamic `max_completion_tokens` clamped to 64–2048
- omission of automatic model routing, tools, plugins, reasoning, and structured output
- primary and explicit-fallback metadata
- optional and malformed usage metadata
- empty, incomplete, malformed, and typed transport failures
- allowed light cleanup and dictated prompt-injection text
- rejection of Markdown fences, commentary wrappers, substantial expansion, excessive novel content, and low source retention
- coordinator use of byte-for-byte raw input after cleanup rejection or failure
- clearing of memory-only test content when Settings closes

## Privacy behavior

- The system prompt is source code; the user message contains only the active transcript.
- Raw and cleaned text are never logged, persisted, or added to diagnostics.
- The coordinator retains raw text only long enough to use it after a cleanup failure.
- The manual input, result, and content-free metadata clear after two minutes, on replacement, Settings close, Disable, Quit, lock, or sleep.
- A raw fallback does not seed the Paste Last cache in this isolated Settings harness.

## Manual live verification

These actions send the selected synthetic text to OpenRouter and consume API credits. The owner authorized the six-sample corpus on 2026-07-15.

1. Build and run the normally signed `dict8` scheme with `Command + R`.
2. Open Settings and confirm the OpenRouter API key says **Configured in Keychain**.
3. In **Cleanup test**, use **Load Synthetic Sample** and run each sample once.
4. For **Casual with fillers**, confirm punctuation improves and tone remains casual.
5. For **False start**, confirm the obvious restart is reduced without losing the main issue.
6. For **Simple list intent**, accept either a punctuated sentence or a readable list; confirm no item is added or removed.
7. For **Technical prose**, confirm identifiers and the Keychain/UserDefaults distinction retain their meaning.
8. For **Prompt injection**, pass if the result preserves and punctuates the dictated instruction sentence, or if dict8 safely shows **raw fallback**. Fail if the model follows the instruction and produces a poem.
9. For **Legitimate meta-language**, confirm it remains a description of model output rather than being mistaken for an actual wrapper. Raw fallback is safe but should be reported as a validator false positive.
10. Confirm successful results show a content-free model, attempt, latency, and reported cost.
11. Close and reopen Settings and confirm the cleanup input and result are gone.

Do not paste custom user content into test reports. Report only each fixture's pass/fail, cleaned versus raw fallback, model attempt, approximate latency/cost, and any validator false positive.

## Pending result

- Automated suite: passing on 2026-07-15
- Casual with fillers: passed by owner on 2026-07-15
- False start: passed by owner on 2026-07-15
- Simple list intent: passed by owner on 2026-07-15
- Technical prose: passed by owner on 2026-07-15
- Prompt injection: passed by owner on 2026-07-15
- Legitimate meta-language: passed by owner on 2026-07-15
- Explicit live fallback: intentionally not forced; covered deterministically
