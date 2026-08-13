# dict8 — AGENTS.md

These instructions apply to all Codex work in this repository.

`PRD.md` is the source of truth for product behavior, scope, approved exceptions, and phase numbering. If this file conflicts with `PRD.md`, stop and reconcile this file to `PRD.md` before implementation; do not override the PRD.

## 1. Operating mode

Work incrementally.

Implement only the explicitly requested phase or task. Do not skip ahead, pre-build future features, or add speculative abstractions.

Before making changes:

1. Read `PRD.md`, the authoritative product and phase specification.
2. Read this file.
3. Inspect the repository structure.
4. Inspect relevant existing files.
5. Run `git status`.
6. Summarize the minimal implementation approach.
7. List the exact files expected to be created or modified.

Do not edit code before understanding the current implementation.

## 2. Repository visibility

Before implementation, show a concise directory tree of the relevant project structure.

Mark planned changes with:

```text
(+) new file
(~) modified file
(-) deleted file
```

Example:

```text
dict8/
├── App/
│   ├── Dict8App.swift (~)
│   └── AppState.swift (+)
└── Views/
    └── SettingsView.swift (+)
```

After implementation, show the updated relevant tree.

Whenever creating a file, explain in one or two sentences:

* Why the file exists
* Why its responsibility does not belong in an existing file

Prefer fewer files. Do not create a type merely to make the architecture look sophisticated.

## 3. Scope discipline

Only implement the requested task.

Do not add:

* Future phases
* Unrequested settings
* Extra AI providers
* Generic plugin systems
* Premature configuration layers
* Complex dependency injection frameworks
* Extra UI polish
* Logging frameworks
* Analytics beyond the requested phase
* Persistence beyond current requirements
* Compatibility code for hypothetical platforms
* Refactors unrelated to the phase

If a future requirement affects current design, create only the smallest seam necessary.

Do not implement the future feature.

## 4. Product boundaries

dict8 is a personal native macOS push-to-talk dictation app.

Core v0 behavior:

```text
hold Control + Option
→ record
→ release
→ transcribe
→ clean
→ verify the original target
→ paste or copy and notify
→ delete temporary data
```

Primary targets:

* ChatGPT
* Codex
* Cursor
* Claude
* Browser text areas
* TextEdit as the baseline test target

Default cleanup style:

```text
Me but punctuated.
```

v0 excludes:

* Streaming transcription
* Live partial transcripts
* Transcript history beyond the approved ten-minute, memory-only Paste Last Dictation cache
* Audio history
* Preview-before-paste
* Retry/rewrite UX
* Cleanup modes
* Configurable hotkeys
* fn/Globe support
* Local Whisper
* Multiple AI-provider implementations
* Automatic model routing
* More than one explicit fallback model per pipeline stage
* Interactive or persistent floating overlay beyond the approved recording HUD
* App Store distribution
* Notarization
* Intel Mac and older macOS compatibility

Approved v0 additions:

* `Control + Option` is the fixed push-to-talk chord and is consumed while enabled.
* `Command + Control + V` re-pastes one memory-only result cached for at most ten minutes.
* The cache clears on expiry, replacement, Disable, Quit, or screen lock.
* Automatic paste occurs only if the originating application remains foreground; otherwise copy and notify.
* Known password and secure fields are refused.
* Keychain stores the normal-launch API key; `OPENROUTER_API_KEY` is a development override.
* Account-level OpenAI and Google ZDR settings are required for STT because OpenRouter does not apply per-request data-policy controls to the transcription endpoint; cleanup additionally enforces ZDR per request.
* Each AI stage has one pinned model and at most one explicit fallback, **except** the cleanup stage, which uses OpenRouter's `openrouter/auto` Auto Router (stable slug) per the explicit exception below.
* A subtle start/stop cue and non-activating bottom-center microphone HUD provide recording feedback.
* Normal launch and Launch at Login are included.
* **Approved exception — cleanup stage uses OpenRouter Auto Router (approved 2026-08-12, switched to Beta track 2026-08-13, reverted to stable slug 2026-08-13):** The cleanup stage sends `model: "openrouter/auto"` instead of a pinned primary model plus one explicit fallback, and its per-request Auto Router settings use the `auto-router` plugin id. STT is unaffected and keeps its pinned primary/fallback pair. Rationale: cleanup is a low-stakes, low-cost, high-volume stage where OpenRouter's live spend-share routing can pick a suitable model without dict8 hand-maintaining a fallback list. The Beta track (`openrouter/auto-beta`, `auto-beta-router` plugin id) was tried for roughly a day but reverted after on-device usage metrics showed a high cleanup raw-fallback rate (~27% of requests, dominated by `missingChoice` zero-completion responses) while running on Beta; the zero-completion single-retry accommodation below was added first, but the decision was made to revert to the stable slug rather than continue evaluating Beta. Consequences of this exception:
  * Cleanup makes exactly one explicit model attempt (`openrouter/auto`); there is no local dict8-side model-fallback switch for cleanup. A transient failure on that single attempt is treated as an ordinary cleanup failure (raw transcript pastes, per existing failure behavior) rather than triggering a second model attempt.
  * `provider.zdr: true` is still sent on every cleanup request, unchanged; per OpenRouter's Auto Router docs, account-level model/provider restrictions, guardrails, and ZDR policy are honored by the router before it selects a candidate.
  * The "notify user when a fallback model was required" cleanup behavior no longer applies, because dict8 does not select or know about the router's internal fallback; only the responding model's identity (already returned in `response.model`) is available and may still be used for content-free metrics.
  * This exception is scoped to the cleanup stage only. It does not apply to STT, and it does not authorize automatic/multi-model routing for any other stage without a separate explicit approval.
* **Approved exception — cleanup stage deadline and output cap lowered (approved 2026-08-13):** Cleanup's request deadline is 10 seconds (lowered from the original 30 seconds) and its `max_completion_tokens` cap is 1,024 (lowered from 2,048), with the per-input floor lowered from 64 to 48. Rationale: cleanup is a "lightly punctuate this" task whose output should never be much longer than the input, so both the worst-case generation time and the failure-detection latency have slack to tighten; failing faster into the existing raw-transcript-fallback path is preferred over waiting out a slow Auto Router pick. This does not change STT's deadline or token limits, and it does not authorize combining a same-model retry with fallback beyond the existing per-stage attempt cap.

## 5. Architecture rules

Use native macOS technologies:

* Swift
* SwiftUI
* AppKit where required
* AVFoundation for audio recording
* NSPasteboard for clipboard behavior
* CGEvent or another justified native API for synthetic paste
* URLSession for networking
* Swift concurrency with `async` and `await`

Do not use Electron.

Keep these concerns separate:

1. Application state
2. UI
3. Hotkey monitoring
4. Audio recording
5. Speech-to-text
6. Text cleanup
7. OpenRouter networking
8. Pipeline orchestration
9. Paste behavior
10. Permissions
11. Metrics

UI code must not:

* Construct API requests
* Directly manage microphone recording
* Own retry logic
* Contain provider-specific request schemas
* Orchestrate the full pipeline

The coordinator owns the end-to-end dictation flow.

OpenRouter-specific details belong behind provider adapters or the shared OpenRouter client.

## 6. Simplicity rules

Prefer boring code.

Use the smallest implementation that clearly satisfies the requirement.

Avoid:

* Managers managing managers
* Empty protocols with no testing or boundary value
* Deep inheritance
* Clever generics
* Service locators
* Global mutable state
* Custom event buses
* Unnecessary Combine pipelines
* Detached tasks without clear lifecycle ownership
* Nested callback pyramids
* Duplicate model types
* Wrapper types that only rename standard-library behavior
* Premature protocol proliferation
* One-file-per-trivial-type architecture

A type should have one clear reason to exist.

A file should have one dominant responsibility.

Do not split a small cohesive implementation across many files.

## 7. Swift conventions

Use current Swift conventions.

Requirements:

* Use descriptive names.
* Prefer structs unless reference identity is required.
* Use `final` for classes not intended for inheritance.
* Use `private` and `fileprivate` appropriately.
* Isolate UI-observable state to the main actor.
* Perform UI state changes on the main actor.
* Use typed errors.
* Avoid force unwraps.
* Avoid `try!`.
* Avoid silent `catch`.
* Avoid implicitly unwrapped optionals unless required by Apple framework lifecycle.
* Use `defer` for guaranteed cleanup when appropriate.
* Keep functions reasonably short.
* Add comments only where intent is not obvious.
* Do not comment trivial syntax.
* Do not suppress compiler warnings without explaining why.
* Do not use deprecated APIs unless no practical alternative exists and the reason is documented.

## 8. State management

Represent important application state explicitly.

Prefer one enum over unrelated booleans such as:

```swift
isRecording
isLoading
isCleaning
isBusy
```

Prevent invalid transitions.

Examples:

* Do not start recording twice.
* Do not stop when no recording is active.
* Do not begin a new request while processing.
* Do not paste after failed transcription.
* Do not run cleanup if transcription failed.
* Do not leave the app stuck in a processing state after failure.
* Do not retain stale errors after a successful request unless intentionally displayed.

All user-visible state transitions must occur on the main actor.

## 9. Concurrency

Use structured concurrency.

Requirements:

* Prefer `async` and `await`.
* Keep task ownership explicit.
* Avoid `Task.detached` unless there is a documented reason.
* Support cancellation where practical.
* Do not block the main thread with file reads, encoding, networking, audio processing, or sleeps.
* Do not update observable state from background threads.
* Do not create overlapping pipelines for one hotkey interaction.
* Do not launch unowned long-running tasks.

If a task is launched, document:

* Which object owns it
* When it is cancelled
* What happens if the app quits
* What happens if dict8 is disabled

## 10. Privacy and sensitive data

Never log or persist:

* API keys
* Authorization headers
* Raw audio
* Base64 audio
* Raw transcripts
* Cleaned transcripts
* Prompt contents containing user text
* API request bodies containing user content
* API response bodies containing user content

Temporary audio must be deleted on:

* Success
* Transcription failure
* Cleanup failure
* Paste failure
* Cancellation where practical
* App shutdown where practical

Transcript strings should remain in the narrowest practical scope and become unreferenced after use, except for the approved Paste Last Dictation cache. That cache may hold only the last successful output in process memory for at most ten minutes and must never be logged, persisted, or synchronized.

Errors shown to the user must not include transcript or audio contents.

## 11. API keys

For normal launches, store the API key in macOS Keychain. For local development, allow this process-environment override:

```text
OPENROUTER_API_KEY
```

Rules:

* Prefer the process environment only as an explicit development override; otherwise read from Keychain.
* Never print it.
* Never display it.
* Never commit it.
* Never hardcode it.
* Never include it in test fixtures.
* Only display configured or missing status.
* Add relevant local secret files to `.gitignore`.
* Do not introduce custom Keychain access groups or synchronization without explicit approval.

## 12. OpenRouter integration

Use official OpenRouter documentation as the source of truth.

Before implementing any OpenRouter request:

1. Verify the current endpoint.
2. Verify the request schema.
3. Verify the response schema.
4. Verify authentication headers.
5. Verify the model slug.
6. Verify usage and cost fields.
7. Verify audio encoding requirements.
8. Verify current error behavior.

Do not invent:

* Model identifiers
* Request fields
* Response fields
* Headers
* Error formats
* Usage fields
* Pricing fields
* Provider behavior

Keep model identifiers in one configuration location.

Pin explicit primary and fallback models for v0.

Do not use:

* Automatic model routing
* More than one explicit cleanup fallback
* More than one explicit STT fallback

OpenRouter may route one explicitly requested model across multiple provider endpoints. Account-level OpenAI and Google ZDR settings must restrict STT routing because the transcription endpoint does not apply per-request data-policy controls. Cleanup requests must also send `provider.zdr: true`. Provider-level routing does not count as another model attempt. Do not use OpenRouter's automatic multi-model routing; dict8 owns the one explicit model fallback and its notification behavior.

The single explicit fallback per stage is approved. It must be configured centrally, covered by the applicable account-level or per-request ZDR control, and attempted only for the eligible failure classes defined in `PRD.md`.

Use one shared OpenRouter client for:

* Base URL
* Authorization
* Request execution
* HTTP status validation
* Error decoding
* Timing
* Retry logic
* Cancellation
* Shared request metadata

Do not construct OpenRouter requests inside views.

## 13. Speech-to-text

Speech-to-text and cleanup are separate stages.

The STT provider:

* Accepts an audio file URL
* Returns transcript text and metadata
* Rejects empty output
* Distinguishes common failure classes
* Does not perform cleanup
* Does not paste
* Does not update UI directly

For OpenRouter STT:

* Use the dedicated transcription endpoint if currently supported.
* Read and encode the finished audio only when preparing the request.
* Release encoded audio from memory after completion.
* Do not retain request payloads.
* Do not use a multimodal chat endpoint as a shortcut unless the dedicated endpoint is unavailable and the change is explicitly approved.

## 14. Cleanup stage

Cleanup must remain conservative.

Default behavior:

* Add punctuation
* Add capitalization
* Lightly remove filler words
* Remove obvious repetition
* Resolve obvious false starts
* Split long rambles into readable paragraphs
* Infer simple formatting when unambiguous
* Preserve tone
* Preserve meaning
* Preserve level of formality

Cleanup must not:

* Add facts
* Add ideas
* Rewrite substantially
* Make prose corporate
* Make prose more formal by default
* Explain edits
* Wrap output in quotes
* Return Markdown fences
* Return headings unless clearly dictated
* Invent formatting

Use structured system and user messages when supported.

If cleanup fails after the allowed retry:

* Return control to the coordinator.
* Let the coordinator paste the raw transcript.
* Do not disguise cleanup failure as success.
* Do not return the input text as though the cleanup call succeeded.

## 15. Audio recording

Use a temporary file.

Requirements:

* Prefer `.m4a` with AAC.
* Use mono audio.
* Use a speech-appropriate sample rate.
* Support at least 120 seconds.
* Enforce a 180-second hard limit.
* Prevent double start.
* Prevent double stop.
* Expose explicit cancellation.
* Delete temporary files after processing.
* Keep recording logic out of views.
* Do not load the entire recording into memory while recording.
* Keep the UI responsive during recording.
* Handle microphone permission failure explicitly.

## 16. Hotkey handling

Default shortcut:

```text
Control + Option
```

Requirements:

* Detect press and release separately.
* Trigger start once on press.
* Trigger stop once on release.
* Ignore key-repeat events.
* Work while another app is focused.
* Stop listeners cleanly when disabled or quitting.
* Document whether the chosen API swallows the shortcut.
* Document permission requirements.
* Document macOS limitations.
* Ignore the shortcut while dict8 is processing.
* Consume the chord while dict8 is enabled so it does not affect the foreground application.

Do not:

* Use `Command + Space` by default.
* Add configurable hotkeys in v0.
* Implement fn/Globe support in v0.
* Choose an API that only supports activation if hold semantics are required.

Before implementing, verify that the chosen API supports reliable press-and-release behavior.

## 17. Paste behavior

The paste service must:

1. Reject empty text.
2. Write text to `NSPasteboard`.
3. Allow a minimal delay if macOS needs time to observe the pasteboard update.
4. Synthesize `Command + V`.
5. Return a typed error if event creation or posting fails.

Rules:

* Do not modify the clipboard before transcription succeeds.
* On STT failure, leave the clipboard untouched.
* On cleanup failure, paste the raw transcript.
* On paste failure, leave the final text on the clipboard when possible.
* Do not implement clipboard restoration until explicitly requested.
* Do not paste automatically during tests unless the test explicitly targets paste behavior.

## 18. Failure behavior

If transcription fails:

* Paste nothing.
* Leave the clipboard unchanged.
* Delete temporary audio.
* Show a useful content-free error.
* Return to a valid app state.

If cleanup fails:

* Paste the raw transcript.
* Delete temporary audio.
* Show a non-blocking warning.
* Record the failure without storing transcript content.

If paste fails:

* Leave the resulting text on the clipboard when possible.
* Show an error explaining that paste failed.
* Do not lose the generated text unnecessarily.

If cancellation occurs:

* Stop current work.
* Delete temporary files where practical.
* Return the app to a valid state.
* Do not paste partial output.

## 19. Error handling

Use typed errors.

Distinguish where practical:

* Missing microphone permission
* Missing Accessibility permission
* Missing API key
* Recording already active
* No active recording
* Audio encoding failure
* Authentication failure
* Rate limit
* Payload too large
* Unsupported audio
* Network interruption
* Server failure
* Invalid response
* Empty transcript
* Empty cleanup output
* Paste failure
* Cancellation

Do not expose raw server response bodies directly to the user.

Sanitize error messages.

Every failure path must leave the app in a valid state.

Never swallow errors silently.

## 20. Retry behavior

Allow at most two model attempts per AI stage: the pinned model and one configured fallback. Do not combine a same-model retry with fallback in a way that exceeds this total attempt cap.

Use the fallback only for eligible availability or transient failures:

* Network interruption
* HTTP 408
* HTTP 429
* HTTP 500
* HTTP 502
* HTTP 503
* HTTP 504

Use short exponential backoff with jitter when a backoff is needed. Respect a reasonable `Retry-After` value without exceeding the stage deadline.

Do not retry:

* Authentication failures
* Invalid requests
* Unsupported media
* Oversized payloads
* Decoding failures
* Empty successful responses, **except** the cleanup-stage zero-completion accommodation below
* Permission errors
* Local recording-state errors
* Paste failures

Keep attempt and fallback behavior in the shared API client or one shared request-execution layer.

Do not duplicate retry logic across providers.

**Approved exception — cleanup zero-completion retry accommodation (approved 2026-08-13):** The cleanup stage may retry once, within the same stage deadline and using the same single Auto Router request (`openrouter/auto`), when a response decodes successfully but has an empty `choices` array or a `nil` message content (dict8's `missingChoice` case). Rationale:

* OpenRouter's Zero Completion Insurance means a response with no output tokens and a blank/error finish state is never billed, so this retry adds no cost exposure.
* Cleanup does not send a `session_id`, so the Auto Router re-ranks candidates from scratch on the retried request and typically lands on a different underlying model rather than repeating the same failure.
* This is a single same-request retry, not a second explicit model attempt: it does not add a fallback model, does not apply to any other cleanup failure class (malformed response, unexpected finish reason, incomplete output), and does not apply to STT.
* If the retry also returns an empty choice, cleanup fails with `missingChoice` as before and the coordinator pastes the raw transcript per existing failure behavior.

## 21. Metrics

Metrics must be aggregate and content-free.

Allowed:

* Request count
* Total audio seconds
* STT latency
* Cleanup latency
* Total pipeline latency
* Estimated STT cost
* Estimated cleanup cost
* Success count
* Failure count
* Cleanup-fallback count

Forbidden:

* Transcript samples
* Audio samples
* Prompt contents
* Response contents
* Request bodies
* User text excerpts
* Error messages containing user text

Missing cost metadata must not fail the request.

Use simple persistence such as `UserDefaults` only when the metrics phase is requested.

## 22. Testing

Design service boundaries so orchestration can be tested without live APIs.

Use test doubles for:

* Audio recorder
* STT provider
* Cleanup provider
* Paste service
* Metrics service
* API transport
* Hotkey monitor where practical

Core eventual tests:

* Press starts recording once.
* Repeated press does not double-start.
* Release without recording does nothing.
* Successful pipeline pastes cleaned text.
* Cleanup failure pastes raw text.
* STT failure pastes nothing.
* Audio is deleted after success.
* Audio is deleted after STT failure.
* Audio is deleted after cleanup failure.
* Audio is deleted after paste failure.
* Empty STT output fails.
* Empty cleanup output falls back to raw.
* New requests are ignored while busy.
* Metrics contain no text.
* Transient errors retry once.
* Permanent errors do not retry.
* Cancellation does not paste.
* State returns to idle after completion.
* State returns to a valid state after failure.

Do not run live API tests automatically.

Live API tests must be:

* Manual
* Explicitly requested
* Clearly marked as spending API credits

## 23. Build and verification

After every implementation task:

1. Build the project.
2. Run relevant unit tests.
3. Report exact commands used.
4. Report pass/fail results.
5. Fix failures caused by the change.
6. Inspect warnings.
7. Do not claim success without running the build or tests.

When the environment prevents a build or test:

* State exactly what could not run.
* Explain why.
* Provide the exact command the user should run locally.
* Do not fabricate results.

## 24. Git discipline

The Git repository is already initialized.

Before editing:

```bash
git status
git branch --show-current
```

If unexpected modified, staged, or untracked files exist:

* Report them before editing.
* Do not discard them.
* Do not overwrite them.
* Do not reset the repository.
* Do not assume they are safe to delete.

During implementation:

* Keep changes limited to the requested phase.
* Do not mix unrelated refactors into the phase.
* Do not reformat unrelated files.
* Do not alter generated Xcode project files unnecessarily.
* Do not fix unrelated bugs unless requested.
* Report unrelated issues without changing them.

After implementation:

```bash
git status
git diff --stat
git diff
```

Inspect the complete diff before committing.

Do not:

* Rewrite history
* Rebase
* Reset
* Force-push
* Amend earlier commits
* Delete user branches
* Delete unrelated untracked files
* Stash user work without explicit instruction
* Commit secrets
* Commit build artifacts
* Commit DerivedData
* Commit local environment files

## 25. Phase commit policy

Create one commit after each completed phase.

A phase may be committed only when:

* Requested scope is complete.
* The project builds, or the environment limitation is explicitly documented.
* Relevant tests pass, or the inability to run them is explicitly documented.
* The diff has been reviewed.
* No secrets are included.
* No unrelated changes are included.

Do not combine multiple phases into one commit.

Do not create WIP commits unless explicitly requested.

Do not make multiple commits for one phase unless necessary to preserve user work or explicitly requested.

Commit message format:

```text
<type>: <short description>
```

Preferred types:

* `feat`
* `fix`
* `refactor`
* `test`
* `docs`
* `chore`

Examples:

```text
feat: create menu bar application shell
feat: add paste service
feat: implement audio recording
feat: add OpenRouter client
feat: add speech transcription
feat: add transcript cleanup
feat: implement push-to-talk pipeline
feat: add usage metrics
fix: prevent duplicate recording sessions
refactor: simplify pipeline coordinator
test: add cleanup fallback coverage
docs: update local setup instructions
```

Commit body format:

```text
Summary:
- ...
- ...

Tests:
- ...

Notes:
- ...
```

Before committing, run:

```bash
git status
git diff --stat
git diff
```

Then stage only phase-related files.

Prefer explicit staging:

```bash
git add path/to/file1 path/to/file2
```

Avoid:

```bash
git add .
git add -A
```

unless every changed file has been reviewed and belongs to the phase.

After committing, run:

```bash
git status
git log -1 --stat --oneline
```

Report:

* Commit hash
* Commit title
* Files changed
* Insertions and deletions
* Build result
* Test result

If the phase should not be committed, explain exactly why.

## 26. GitHub remote policy

Assume a GitHub remote may already exist.

Inspect with:

```bash
git remote -v
```

Do not create or replace a remote unless explicitly requested.

Never run without explicit user instruction:

```bash
git push
git push --force
git push --force-with-lease
gh pr create
gh repo delete
gh repo rename
```

Do not:

* Push automatically after a phase.
* Open pull requests automatically.
* Modify branch protection.
* Change repository visibility.
* Create releases.
* Create GitHub Actions workflows unless requested.
* Create issues unless requested.

Commits are local by default.

## 27. Branch policy

Work on the current branch unless explicitly instructed otherwise.

Do not create a new branch automatically.

Do not rename the current branch.

Do not merge branches.

Do not rebase.

If the current branch is unclear or appears protected, report it before editing.

## 28. `.gitignore`

Ensure the repository ignores relevant local and generated files.

Typical entries may include:

```text
.DS_Store
DerivedData/
.build/
xcuserdata/
*.xcuserstate
.env
.env.*
```

Do not blindly replace an existing `.gitignore`.

Merge only necessary entries.

Never ignore source files or project configuration required to build the app.

## 29. Dependency policy

Prefer Apple frameworks and the Swift standard library.

Do not add third-party dependencies unless:

1. The task genuinely requires one.
2. Native APIs are materially worse.
3. The dependency is actively maintained.
4. Its license is acceptable.
5. The reason is documented.
6. The user explicitly approves it.

Do not add a dependency merely to avoid writing a small amount of straightforward code.

If proposing a dependency, stop before adding it and report:

* Package name
* Purpose
* Why native APIs are insufficient
* Maintenance status
* License
* Alternatives considered

## 30. Documentation

Keep `PRD.md` authoritative for product behavior, scope, and phase numbering.

Update documentation when behavior or setup changes.

Document:

* Environment variables
* Required permissions
* Local run steps
* Manual testing steps
* Known macOS limitations
* Model configuration
* Required Xcode setup
* Any non-obvious security or privacy behavior

Do not let README instructions drift from actual behavior.

Do not duplicate large sections of `PRD.md` into README.

## 31. Xcode project discipline

Avoid unnecessary churn in:

* `.pbxproj`
* Schemes
* Workspace files
* User-specific Xcode settings

Do not commit:

* `xcuserdata`
* Personal schemes unless intentionally shared
* DerivedData
* User breakpoints
* Local signing credentials
* Team-specific provisioning data unless required

If project-file changes are necessary:

* Keep them minimal.
* Explain what changed.
* Verify the project still opens and builds.

## 32. Manual verification

Each phase must include exact manual verification steps.

Steps should specify:

* Which app to open
* Which control to click
* Which shortcut to use
* What input to provide
* What visible result to expect
* What failure behavior to verify

Do not write vague instructions such as:

```text
Test that it works.
```

Prefer:

```text
1. Launch dict8 from Xcode.
2. Open TextEdit and place the cursor in a blank document.
3. Open dict8 Settings.
4. Click “Paste Test Text.”
5. Confirm the expected text appears in TextEdit.
```

## 33. Reporting format after each task

After implementation, respond with exactly these sections:

### Approach

Briefly explain the implementation and major decisions.

### Relevant tree

Show the relevant updated directory tree using:

```text
(+) new
(~) modified
(-) deleted
```

### Files changed

For each file:

* Path
* What changed
* Why it belongs there

### Build and tests

List:

* Commands run
* Results
* Warnings
* Tests not run
* Environment limitations

### Manual verification

Give exact numbered verification steps.

### Git commit

Include:

* Commit created: yes/no
* Commit hash
* Commit title
* Files changed
* Insertions/deletions

If no commit was created, explain why.

### Remaining limitations

List only real current limitations.

### Next phase

Name the next numbered phase.

Do not implement it.

## 34. Stop conditions

Stop and report rather than improvising when:

* Official API documentation contradicts `PRD.md`.
* A model identifier cannot be verified.
* Required macOS behavior is impossible with the chosen API.
* A permission requirement changes product behavior.
* The repository is conflicted.
* The working tree contains unexpected user changes that overlap with the task.
* Existing architecture materially conflicts with the requested phase.
* A requested action risks deleting user work.
* A secret appears committed.
* A third-party dependency appears necessary.
* Signing, entitlements, or provisioning require user-specific choices.
* The build environment is missing required Xcode components.
* The current branch or remote state creates risk.

Do not conceal uncertainty.

Do not invent a workaround and present it as verified.

## 35. Default phase procedure

For every phase, beginning with Phase 0 and preserving the Phase 0–9 numbering in `PRD.md`:

1. Read `PRD.md`.
2. Read `AGENTS.md`.
3. Inspect the repository.
4. Run `git status`.
5. Run `git branch --show-current`.
6. Run `git remote -v`.
7. Show the relevant tree.
8. Explain the minimal approach.
9. List planned files.
10. Implement only the requested scope.
11. Add or update tests.
12. Build.
13. Run relevant tests.
14. Inspect warnings.
15. Run `git status`.
16. Run `git diff --stat`.
17. Run `git diff`.
18. Verify no secrets or unrelated changes are present.
19. Stage only phase files.
20. Commit the phase.
21. Run `git status`.
22. Run `git log -1 --stat --oneline`.
23. Report using the required format.
24. Stop.

## 36. First-run behavior

When first asked to work in this repository:

1. Read `PRD.md`.
2. Read `AGENTS.md`.
3. Inspect the repository.
4. Show the current directory tree.
5. Report git status, current branch, and remotes.
6. Summarize the product in five bullets.
7. Summarize the engineering constraints in ten bullets.
8. Identify contradictions, missing setup, or ambiguity.
9. Propose the smallest plan for Phase 0.
10. List the exact files expected to change.
11. Stop before implementation unless the user explicitly requested implementation in the same message.
