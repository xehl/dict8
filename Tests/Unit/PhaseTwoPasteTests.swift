import Foundation
import XCTest

@testable import dict8

@MainActor
final class PhaseTwoPasteTests: XCTestCase {
    func testPasteWritesClipboardAndPostsEventForSameNonSecureTarget() async throws {
        let target = makeTarget(pid: 10, secureFieldStatus: .notSecure)
        let clipboard = FakeClipboard()
        let eventPoster = FakePasteEventPoster()
        let service = SystemTextPasteService(
            accessibility: FakeAccessibility(target: target),
            clipboard: clipboard,
            eventPoster: eventPoster
        )

        let result = try await service.paste("synthetic test", originatingTarget: target)

        XCTAssertEqual(result, .pasted(secureFieldStatusUnknown: false))
        XCTAssertEqual(clipboard.writtenTexts, ["synthetic test"])
        XCTAssertEqual(eventPoster.postCount, 1)
    }

    func testFocusChangeCopiesWithoutPostingPasteEvent() async throws {
        let origin = makeTarget(pid: 10, secureFieldStatus: .notSecure)
        let current = makeTarget(pid: 11, secureFieldStatus: .notSecure)
        let clipboard = FakeClipboard()
        let eventPoster = FakePasteEventPoster()
        let service = SystemTextPasteService(
            accessibility: FakeAccessibility(target: current),
            clipboard: clipboard,
            eventPoster: eventPoster
        )

        let result = try await service.paste("synthetic test", originatingTarget: origin)

        XCTAssertEqual(result, .copiedBecauseTargetChanged)
        XCTAssertEqual(clipboard.writtenTexts, ["synthetic test"])
        XCTAssertEqual(eventPoster.postCount, 0)
    }

    func testSecureFieldRefusalLeavesClipboardUntouched() async {
        let origin = makeTarget(pid: 10, secureFieldStatus: .notSecure)
        let secureTarget = makeTarget(pid: 10, secureFieldStatus: .secure)
        let clipboard = FakeClipboard()
        let eventPoster = FakePasteEventPoster()
        let service = SystemTextPasteService(
            accessibility: FakeAccessibility(target: secureTarget),
            clipboard: clipboard,
            eventPoster: eventPoster
        )

        await XCTAssertThrowsErrorAsync(
            try await service.paste("synthetic test", originatingTarget: origin)
        ) { error in
            XCTAssertEqual(error as? TextPasteError, .secureField)
        }
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
        XCTAssertEqual(eventPoster.postCount, 0)
    }

    func testUnknownSecureStatusProceedsOnlyForSameApplication() async throws {
        let origin = makeTarget(pid: 10, secureFieldStatus: .unknown)
        let clipboard = FakeClipboard()
        let eventPoster = FakePasteEventPoster()
        let service = SystemTextPasteService(
            accessibility: FakeAccessibility(target: origin),
            clipboard: clipboard,
            eventPoster: eventPoster
        )

        let result = try await service.paste("synthetic test", originatingTarget: origin)

        XCTAssertEqual(result, .pasted(secureFieldStatusUnknown: true))
        XCTAssertEqual(eventPoster.postCount, 1)
    }

    func testMissingAccessibilityLeavesClipboardUntouched() async {
        let target = makeTarget(pid: 10, secureFieldStatus: .notSecure)
        let accessibility = FakeAccessibility(target: target)
        accessibility.permissionStatus = .required
        let clipboard = FakeClipboard()
        let service = SystemTextPasteService(
            accessibility: accessibility,
            clipboard: clipboard,
            eventPoster: FakePasteEventPoster()
        )

        await XCTAssertThrowsErrorAsync(
            try await service.paste("synthetic test", originatingTarget: target)
        ) { error in
            XCTAssertEqual(error as? TextPasteError, .accessibilityPermissionRequired)
        }
        XCTAssertTrue(clipboard.writtenTexts.isEmpty)
    }

    func testEventCreationFailureLeavesTextOnClipboard() async {
        let target = makeTarget(pid: 10, secureFieldStatus: .notSecure)
        let clipboard = FakeClipboard()
        let eventPoster = FakePasteEventPoster(error: .eventCreationFailed)
        let service = SystemTextPasteService(
            accessibility: FakeAccessibility(target: target),
            clipboard: clipboard,
            eventPoster: eventPoster
        )

        await XCTAssertThrowsErrorAsync(
            try await service.paste("synthetic test", originatingTarget: target)
        ) { error in
            XCTAssertEqual(error as? TextPasteError, .eventCreationFailed)
        }
        XCTAssertEqual(clipboard.writtenTexts, ["synthetic test"])
    }

    func testCacheExpiresAndReplacementDropsPreviousValue() {
        var now = Date(timeIntervalSinceReferenceDate: 1_000)
        let cache = LastDictationCache(
            lifetime: 600,
            now: { now },
            notificationCenter: NotificationCenter(),
            privacyNotifications: []
        )

        cache.store("first synthetic result")
        cache.store("second synthetic result")
        XCTAssertEqual(cache.value(), "second synthetic result")

        now = now.addingTimeInterval(601)
        XCTAssertNil(cache.value())
    }

    func testCacheClearsOnEveryV0PrivacyNotification() async {
        let notificationCenter = NotificationCenter()
        let cache = LastDictationCache(
            notificationCenter: notificationCenter,
            privacyNotifications: LastDictationCache.v0PrivacyNotifications
        )

        for privacyNotification in LastDictationCache.v0PrivacyNotifications {
            cache.store("synthetic result")
            notificationCenter.post(name: privacyNotification, object: nil)
            await Task.yield()

            XCTAssertNil(cache.value(), "Expected cache clearing for \(privacyNotification.rawValue)")
        }
    }

    func testDisableAndQuitClearCacheAndStopMonitor() {
        let cache = FakeCache(value: "synthetic result")
        let monitor = FakePasteLastMonitor()
        let coordinator = makeCoordinator(cache: cache, monitor: monitor)
        coordinator.startIfNeeded()
        XCTAssertTrue(monitor.isRunning)

        coordinator.setEnabled(false)
        XCTAssertNil(cache.value())
        XCTAssertFalse(monitor.isRunning)

        cache.store("synthetic result")
        coordinator.prepareForQuit()
        XCTAssertNil(cache.value())
        XCTAssertFalse(monitor.isRunning)
    }

    func testSettingsPasteSeedsCache() async {
        let suiteName = "PhaseTwoPasteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configuration = AppConfiguration(
            hotkeyDisplayName: "Control + Option",
            pasteLastHotkeyDisplayName: "Command + Control + V",
            hudPreviewDuration: .zero,
            testPasteDelay: .zero,
            testPasteText: "synthetic settings paste",
            testRecordingLifetime: .seconds(600)
        )
        let state = AppState(defaults: defaults, configuration: configuration)
        let cache = FakeCache()
        let cacheWrite = expectation(description: "Settings paste seeds Paste Last cache")
        cache.onStore = { _ in cacheWrite.fulfill() }
        let coordinator = makeCoordinator(state: state, cache: cache)

        coordinator.testPaste()
        await fulfillment(of: [cacheWrite], timeout: 1)

        XCTAssertEqual(cache.value(), "synthetic settings paste")
        XCTAssertEqual(state.testPasteStatus, .pasted)
    }

    private func makeCoordinator(
        state: AppState? = nil,
        cache: FakeCache = FakeCache(),
        monitor: FakePasteLastMonitor = FakePasteLastMonitor()
    ) -> AppCoordinator {
        AppCoordinator(
            state: state ?? AppState(defaults: isolatedDefaults()),
            apiKeyStore: FakeAPIKeyStore(),
            launchAtLoginService: FakeLaunchAtLoginService(),
            accessibility: FakeAccessibility(
                target: makeTarget(pid: 10, secureFieldStatus: .notSecure)
            ),
            microphonePermission: FakeMicrophonePermission(),
            audioRecorder: FakeAudioRecorder(),
            audioPlayback: FakeAudioPlayback(),
            pasteService: FakeTextPasteService(),
            lastDictationCache: cache,
            pasteLastMonitor: monitor,
            hud: FakeHUD()
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PhaseTwoPasteTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    private func makeTarget(
        pid: pid_t,
        secureFieldStatus: SecureFieldStatus
    ) -> PasteTarget {
        PasteTarget(
            bundleIdentifier: "com.example.target",
            processIdentifier: pid,
            secureFieldStatus: secureFieldStatus
        )
    }
}

@MainActor
private final class FakeAccessibility: AccessibilityInspecting {
    var permissionStatus: AccessibilityPermissionStatus = .granted
    var target: PasteTarget

    init(target: PasteTarget) {
        self.target = target
    }

    func requestPermission() {}
    func openSystemSettings() -> Bool { true }
    func captureTarget() -> PasteTarget { target }
}

@MainActor
private final class FakeClipboard: PlainTextClipboardWriting {
    private(set) var writtenTexts: [String] = []

    func write(_ text: String) throws {
        writtenTexts.append(text)
    }
}

@MainActor
private final class FakePasteEventPoster: PasteEventPosting {
    private(set) var postCount = 0
    let error: TextPasteError?

    init(error: TextPasteError? = nil) {
        self.error = error
    }

    func postPaste() async throws {
        postCount += 1
        if let error { throw error }
    }
}

private actor FakeAPIKeyStore: APIKeyStoring {
    func status() -> APIKeyStatus { .missing }
    func save(_ key: String) {}
    func remove() {}
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus = .notRegistered
    func setEnabled(_ isEnabled: Bool) {}
    func openSystemSettings() {}
}

@MainActor
private final class FakeTextPasteService: TextPasting {
    func paste(_ text: String, originatingTarget: PasteTarget) async throws -> TextPasteResult {
        .pasted(secureFieldStatusUnknown: false)
    }
}

@MainActor
private final class FakeCache: LastDictationCaching {
    private var storedValue: String?
    var onStore: ((String) -> Void)?

    init(value: String? = nil) {
        storedValue = value
    }

    func store(_ text: String) {
        storedValue = text
        onStore?(text)
    }
    func value() -> String? { storedValue }
    func clear() { storedValue = nil }
}

@MainActor
private final class FakePasteLastMonitor: PasteLastHotkeyMonitoring {
    private(set) var isRunning = false
    var onPasteLast: (() -> Void)?

    func start() throws { isRunning = true }
    func stop() { isRunning = false }
}

@MainActor
private final class FakeHUD: RecordingHUDPresenting {
    func showPreview(for duration: Duration) {}
    func showRecording() {}
    func showFeedback(_ feedback: TransientFeedback) {}
    func hide() {}
}

@MainActor
private final class FakeMicrophonePermission: MicrophonePermissionControlling {
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

@MainActor
private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
