# dict8

dict8 is a native macOS push-to-talk dictation utility. Hold `Control + Option`, speak, release, and dict8 transcribes, lightly cleans, and pastes the result into the originating application when it is still safely focused.

The intended cleanup style is: **“Me but punctuated.”**

## Current status

Phase 2 provides the dockless menu bar shell plus Accessibility guidance, safe focused-application paste, secure-field refusal, a fixed Settings paste test, and a ten-minute memory-only Paste Last cache triggered by `Command + Control + V`. Recording begins in Phase 3; the OpenRouter pipeline follows in later phases.

- Authoritative product requirements and numbered phase plan: [PRD.md](PRD.md)
- Architecture decisions to resolve before implementation: [docs/ARCHITECTURE_DECISIONS.md](docs/ARCHITECTURE_DECISIONS.md)
- Phase 0 validation and manual checks: [docs/PHASE_ZERO_VALIDATION.md](docs/PHASE_ZERO_VALIDATION.md)
- Phase 1 validation and manual checks: [docs/PHASE_ONE_VALIDATION.md](docs/PHASE_ONE_VALIDATION.md)
- Phase 2 validation and manual checks: [docs/PHASE_TWO_VALIDATION.md](docs/PHASE_TWO_VALIDATION.md)
- Verified OpenRouter contracts and candidate models: [docs/OPENROUTER_CONTRACTS.md](docs/OPENROUTER_CONTRACTS.md)
- Privacy and logging rules: [docs/PRIVACY_AND_LOGGING.md](docs/PRIVACY_AND_LOGGING.md)

## Source layout

```text
dict8/
├── dict8/
│   ├── dict8/           # Xcode-synchronized macOS application source root
│   │   ├── App/         # Observable state and coordinator
│   │   ├── Services/    # Native macOS service boundaries
│   │   ├── Views/       # Menu bar, Settings, and HUD UI
│   │   └── PhaseZero/   # Retained validation harness
│   └── dict8.xcodeproj/
├── Supporting/          # Shared model configuration
├── Tests/Unit/          # Hosted macOS unit tests
├── Scripts/             # Explicit, opt-in development tools
└── docs/                # Engineering decisions and validation notes
```

## Development principles

- Native Swift/SwiftUI; AppKit and AVFoundation where required.
- No transcript or audio history; only the last successful output may remain in memory for up to ten minutes for Paste Last Dictation.
- OpenRouter-specific details stay behind provider protocols.
- Every OpenRouter attempt enforces Zero Data Retention.
- Never log API keys, audio, or transcript text.
- Build and verify one phase at a time.
