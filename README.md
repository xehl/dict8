# dict8

dict8 is a native macOS push-to-talk dictation utility. Hold `Control + Option`, speak, release, and dict8 transcribes, lightly cleans, and pastes the result into the originating application when it is still safely focused.

The intended cleanup style is: **“Me but punctuated.”**

## Current status

Phase 0 foundation and validation is complete. The repository contains a signed macOS Xcode project, tests, a temporary validation probe, verified OpenRouter contracts, and content-free benchmark results. It does not yet contain the Phase 1 menu bar/settings application shell or any recording, paste, or AI pipeline implementation.

- Authoritative product requirements and numbered phase plan: [PRD.md](PRD.md)
- Architecture decisions to resolve before implementation: [docs/ARCHITECTURE_DECISIONS.md](docs/ARCHITECTURE_DECISIONS.md)
- Phase 0 validation and manual checks: [docs/PHASE_ZERO_VALIDATION.md](docs/PHASE_ZERO_VALIDATION.md)
- Verified OpenRouter contracts and candidate models: [docs/OPENROUTER_CONTRACTS.md](docs/OPENROUTER_CONTRACTS.md)
- Privacy and logging rules: [docs/PRIVACY_AND_LOGGING.md](docs/PRIVACY_AND_LOGGING.md)

## Planned source layout

```text
dict8/
├── App/                 # App entry point, observable state, coordinator
├── Models/              # Status, settings, results, and aggregate metrics
├── Services/
│   ├── Audio/           # AVFoundation recording
│   ├── Hotkey/          # Global press/release monitoring
│   ├── AI/              # Provider protocols and OpenRouter adapters
│   ├── Paste/           # Clipboard and synthetic paste
│   ├── Permissions/     # Microphone and Accessibility permissions
│   └── Metrics/         # Content-free aggregate usage metrics
├── Views/               # Menu bar and settings UI
├── Supporting/          # Configuration and typed errors
├── Tests/
│   ├── Unit/            # Mock-driven service and coordinator tests
│   └── Integration/     # Manual, opt-in live API tests
└── docs/                # Engineering decisions and supporting notes
```

## Development principles

- Native Swift/SwiftUI; AppKit and AVFoundation where required.
- No transcript or audio history; only the last successful output may remain in memory for up to ten minutes for Paste Last Dictation.
- OpenRouter-specific details stay behind provider protocols.
- Every OpenRouter attempt enforces Zero Data Retention.
- Never log API keys, audio, or transcript text.
- Build and verify one phase at a time.
