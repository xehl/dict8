import ServiceManagement
import XCTest

@testable import dict8

@MainActor
final class PhaseOneAppShellTests: XCTestCase {
    func testEnabledStateDefaultsOnAndPersistsChanges() throws {
        let suiteName = "PhaseOneAppShellTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initialState = AppState(defaults: defaults)
        XCTAssertTrue(initialState.isEnabled)
        XCTAssertEqual(initialState.status, .idle)

        initialState.setEnabled(false)
        let restoredState = AppState(defaults: defaults)

        XCTAssertFalse(restoredState.isEnabled)
        XCTAssertEqual(restoredState.status, .disabled)
    }

    func testTranscriptionEngineAndCleanupModelPersistChanges() throws {
        let suiteName = "PhaseOnePipelineSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initialState = AppState(defaults: defaults)
        XCTAssertEqual(initialState.transcriptionEngine, .local)
        XCTAssertEqual(initialState.selectedCleanupModel, "meta-llama/llama-3.1-8b-instruct:nitro")

        initialState.setTranscriptionEngine(.cloud)
        initialState.setSelectedCleanupModel("meta-llama/llama-3.2-3b-instruct")

        let restoredState = AppState(defaults: defaults)
        XCTAssertEqual(restoredState.transcriptionEngine, .cloud)
        XCTAssertEqual(restoredState.selectedCleanupModel, "meta-llama/llama-3.2-3b-instruct")
    }

    func testCoordinatorUpdatesEnabledStateAndPresentsHUD() {
        let suiteName = "PhaseOneAppShellTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = AppState(defaults: defaults)
        let hud = FakeRecordingHUD()
        let coordinator = AppCoordinator(
            state: state,
            apiKeyStore: FakeAPIKeyStore(),
            launchAtLoginService: FakeLaunchAtLoginService(),
            accessibility: FakeAccessibilityService(),
            microphonePermission: FakeMicrophonePermissionService(),
            audioRecorder: FakeAudioRecorder(),
            audioPlayback: FakeAudioPlayback(),
            pasteService: FakeTextPasteService(),
            lastDictationCache: FakeLastDictationCache(),
            hotkeyMonitor: FakePasteLastHotkeyMonitor(),
            hud: hud
        )

        coordinator.setEnabled(false)
        coordinator.previewHUD()

        XCTAssertEqual(state.status, .disabled)
        XCTAssertEqual(hud.previewDurations, [.seconds(2)])
    }

    func testDevelopmentAPIKeyOverrideTakesPrecedenceWithoutReadingKeychain() async throws {
        let store = SystemAPIKeyStore(environment: ["OPENROUTER_API_KEY": "development-override"])

        let status = try await store.status()

        XCTAssertEqual(status, .developmentOverride)
    }

    func testLaunchAtLoginStatusTracksRequestedState() {
        XCTAssertFalse(LaunchAtLoginStatus.notRegistered.isRequested)
        XCTAssertTrue(LaunchAtLoginStatus.enabled.isRequested)
        XCTAssertTrue(LaunchAtLoginStatus.requiresApproval.isRequested)
        XCTAssertFalse(LaunchAtLoginStatus.unavailable.isRequested)
    }

    func testLaunchAtLoginAttemptsRegistrationWhenServiceIsNotFound() {
        XCTAssertTrue(
            SystemLaunchAtLoginService.shouldAttemptRegistration(for: .notFound)
        )
        XCTAssertTrue(
            SystemLaunchAtLoginService.shouldAttemptRegistration(for: .notRegistered)
        )
        XCTAssertFalse(
            SystemLaunchAtLoginService.shouldAttemptRegistration(for: .enabled)
        )
        XCTAssertFalse(
            SystemLaunchAtLoginService.shouldAttemptRegistration(for: .requiresApproval)
        )
    }

    func testErrorsAreContentFree() {
        let messages = [
            AppShellError.apiKeyStatusUnavailable,
            .apiKeyInvalid,
            .apiKeySaveFailed,
            .apiKeyRemovalFailed,
            .launchAtLoginUpdateFailed,
            .accessibilityPermissionRequired,
            .accessibilitySettingsUnavailable,
            .pasteTargetUnavailable,
            .secureFieldRefused,
            .clipboardWriteFailed,
            .pasteEventCreationFailed,
            .pasteFailed,
            .hotkeyMonitorFailed,
            .microphonePermissionRequired,
            .microphonePermissionRestricted,
            .microphoneSettingsUnavailable,
            .recordingAlreadyActive,
            .noActiveRecording,
            .recordingStartFailed,
            .recordingEncodingFailed,
            .temporaryAudioCleanupFailed,
            .audioPlaybackFailed,
            .recordingCueFailed,
            .transcriptionFallbackUsed,
            .focusChangedCopied,
            .transcriptionAndAudioCleanupFailed(.emptyTranscript),
            .transcriptionFailed(.emptyTranscript),
            .cleanupFailed(.emptyOutput),
        ].compactMap(\.errorDescription)

        XCTAssertEqual(messages.count, 28)
        XCTAssertTrue(messages.allSatisfy { !$0.contains("development-override") })
    }
}

private actor FakeAPIKeyStore: APIKeyStoring {
    func status() -> APIKeyStatus { .missing }
    func apiKey() throws -> String { throw APIKeyStoreError.missingKey }
    func save(_ key: String) {}
    func remove() {}
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginControlling {
    private(set) var status: LaunchAtLoginStatus = .notRegistered

    func setEnabled(_ isEnabled: Bool) {
        status = isEnabled ? .enabled : .notRegistered
    }

    func openSystemSettings() {}
}

@MainActor
private final class FakeAccessibilityService: AccessibilityInspecting {
    var permissionStatus: AccessibilityPermissionStatus = .granted

    func requestPermission() {}
    func openSystemSettings() -> Bool { true }
    func captureTarget() -> PasteTarget {
        PasteTarget(
            bundleIdentifier: "com.example.target",
            processIdentifier: 1,
            secureFieldStatus: .notSecure
        )
    }
    func readFocusedElementText(in application: NSRunningApplication?) -> String? { nil }
}

@MainActor
private final class FakeTextPasteService: TextPasting {
    func paste(_ text: String, originatingTarget: PasteTarget) async throws -> TextPasteResult {
        .pasted(secureFieldStatusUnknown: false)
    }
}

@MainActor
private final class FakeLastDictationCache: LastDictationCaching {
    func store(_ text: String) {}
    func value() -> String? { nil }
    func clear() {}
}

@MainActor
private final class FakePasteLastHotkeyMonitor: HotkeyMonitoring {
    private(set) var isRunning = false
    var onPushToTalkPressed: (() -> Void)?
    var onPushToTalkReleased: (() -> Void)?
    var onPasteLast: (() -> Void)?

    func start() throws { isRunning = true }
    func stop() { isRunning = false }
}

@MainActor
private final class FakeRecordingHUD: RecordingHUDPresenting {
    private(set) var previewDurations: [Duration] = []

    func showPreview(for duration: Duration) {
        previewDurations.append(duration)
    }

    func showRecording() {}
    func showFeedback(_ feedback: TransientFeedback) {}

    func hide() {}
}

@MainActor
private final class FakeMicrophonePermissionService: MicrophonePermissionControlling {
    var status: MicrophonePermissionStatus = .granted
    func requestPermission() async -> MicrophonePermissionStatus { status }
    func openSystemSettings() -> Bool { true }
}

@MainActor
private final class FakeAudioRecorder: AudioRecording {
    var isRecording = false
    var elapsedTime: TimeInterval = 0
    var onMaximumDurationReached: ((Result<RecordedAudioFile, AudioRecordingError>) -> Void)?

    func start() throws { isRecording = true }
    func stop() throws -> RecordedAudioFile { throw AudioRecordingError.noActiveRecording }
    func cancel() throws { isRecording = false }
    func delete(_ recording: RecordedAudioFile) throws {}
}

@MainActor
private final class FakeAudioPlayback: AudioPlaybackProviding {
    func playStartCue() async throws {}
    func playStopCue() async throws {}
    func playPreview(at url: URL) async throws {}
    func stop() {}
}
