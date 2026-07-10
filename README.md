# dict8

dict8 is a native macOS push-to-talk dictation utility. Hold `Control + Option`, speak, release, and dict8 transcribes, lightly cleans, and pastes the result into the originating application when it is still safely focused.

The intended cleanup style is: **“Me but punctuated.”**

## Current status

This repository is at the planning and skeleton stage. It intentionally contains no application implementation or Xcode project yet.

- Product requirements and phased delivery plan: [PRD.md](PRD.md)
- Architecture decisions to resolve before implementation: [docs/ARCHITECTURE_DECISIONS.md](docs/ARCHITECTURE_DECISIONS.md)

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
