# dict8

dict8 is a native macOS push-to-talk dictation utility. Hold `Control + Option`, speak, and release. dict8 records the utterance, transcribes it, lightly cleans the prose, and pastes the result back into the application where recording began.

## Status

The personal v0 is in routine use on Apple silicon with macOS 26. It supports short and long-form dictation, a three-minute recording limit, target-safe paste, a ten-minute memory-only Paste Last cache, and content-free aggregate usage metrics.

dict8 is currently distributed as source under the [MIT License](LICENSE). There is no notarized public binary or automatic updater.

## Requirements

- Apple silicon Mac running macOS 26 or newer
- Xcode with the macOS 26 SDK
- An Apple Account or development team for local code signing
- An [OpenRouter](https://openrouter.ai/) account and API key
- Permission to grant Microphone and Accessibility access on the Mac

Company-managed Macs may restrict locally signed software, microphone access, Accessibility access, global event taps, or Launch at Login.

## Install from source

See [Installing dict8 from source](docs/INSTALL.md) for the complete signing, build, installation, privacy, and first-run checklist.

At a high level:

1. Clone the repository and open `dict8/dict8.xcodeproj`.
2. Select your signing team and, if necessary, choose a unique bundle identifier.
3. Build and test the `dict8` scheme for **My Mac**.
4. Archive the Release build and copy `dict8.app` to `/Applications`.
5. Launch the installed copy, enter an OpenRouter API key, and grant Microphone and Accessibility access.

## Use

- Hold `Control + Option` to begin recording.
- Speak naturally.
- Release the chord to transcribe, clean, and paste.
- Press `Command + Control + V` to paste the last successful dictation again within ten minutes.
- Disable dict8 from its menu bar menu when the shortcut should not be active.

If the originating application is no longer foreground when processing finishes, dict8 copies the result and notifies instead of pasting into a different application. Known password and secure fields are refused.

## Privacy model

Audio and transcript text leave the Mac for processing through OpenRouter and its selected model providers. dict8 does not log or persist API keys, audio, raw transcripts, cleaned transcripts, or request bodies containing user content.

- Temporary audio is deleted after success, failure, or cancellation where practical.
- The last successful output may remain in process memory for at most ten minutes for Paste Last. It is never persisted and clears on replacement, expiry, Disable, Quit, or screen lock.
- Aggregate request, duration, latency, cost, and outcome metrics contain no dictated text.
- The API key is stored in macOS Keychain. `OPENROUTER_API_KEY` is available only as an explicit development override.

Review [Privacy and logging](docs/PRIVACY_AND_LOGGING.md) and OpenRouter's [Zero Data Retention documentation](https://openrouter.ai/docs/guides/features/zdr) before using dict8 with sensitive speech.

## Architecture

dict8 uses Swift, SwiftUI, AppKit, AVFoundation, Keychain Services, ServiceManagement, `NSPasteboard`, `CGEvent`, `URLSession`, and Swift concurrency. It has no third-party application dependencies.

```text
dict8/
├── dict8/
│   ├── dict8/           # macOS application source
│   │   ├── App/         # observable state and pipeline coordination
│   │   ├── Services/    # recording, AI, hotkey, paste, and system services
│   │   └── Views/       # menu bar and Settings UI
│   └── dict8.xcodeproj/
├── Supporting/          # shared model configuration
├── Tests/Unit/          # hosted macOS unit tests
├── Scripts/             # explicit, opt-in development tools
└── docs/                # requirements, decisions, and validation records
```

The authoritative behavior and project scope live in [PRD.md](PRD.md). Important technical choices are recorded in [Architecture decisions](docs/ARCHITECTURE_DECISIONS.md), and the current OpenRouter assumptions are recorded in [OpenRouter contracts](docs/OPENROUTER_CONTRACTS.md).

## Development and validation

Select the `dict8` scheme and **My Mac** destination in Xcode:

- `Command + U` runs the unit-test suite.
- `Command + R` launches the development copy.
- Live OpenRouter tests are manual and opt-in because they transmit audio and consume API credits.

Do not run the Xcode-launched app and `/Applications/dict8.app` simultaneously. Both instances would monitor the same global shortcut.

Validation procedures are retained under [`docs/`](docs/). Use synthetic or harmless speech; never commit real transcripts, recordings, API keys, or screenshots containing dictated content.

## License

dict8 is released under the [MIT License](LICENSE).
