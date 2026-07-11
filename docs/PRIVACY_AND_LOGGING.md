# Privacy and Logging Rules

These rules apply from the first implementation phase.

## Never log or retain beyond an explicit lifecycle

- API keys or authorization headers
- Base64 audio; raw audio outside the app-owned temporary-file lifecycle; or audio file paths outside content-free lifecycle diagnostics
- Raw or cleaned transcript text
- Cleanup prompts or request/response bodies containing user text
- Clipboard contents
- Focused-field values
- Server errors that may echo request content

## Allowed diagnostics

- Content-free stage names and state transitions
- Request attempt number and selected model identifier
- HTTP status and canonical content-free error category
- Per-stage latency and aggregate cost values
- Audio duration, but not audio data
- Target application bundle identifier and AX role/subrole, but never field value
- Whether secure-field detection succeeded, failed, or was unavailable

## Temporary data

- Store recordings only in an app-owned temporary directory.
- Delete them on success, failure, cancellation, Disable, and quit where practical.
- Sweep stale app-owned temporary files at startup.
- Keep raw and cleaned text in the narrowest practical scope.
- The sole exception is one last successful output held in process memory for at most ten minutes for Paste Last Dictation.

## Remote processing

- Explain that audio and transcript text leave the Mac for processing.
- Set `provider.zdr: true` on every OpenRouter request.
- Do not enable OpenRouter prompt logging, debug payloads, plugins, or tools.
- Fail clearly if no endpoint satisfies ZDR rather than silently relaxing the requirement.
