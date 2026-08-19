import Foundation
import XCTest

@testable import dict8

@MainActor
final class PhaseThreeAudioTests: XCTestCase {
    func testRecorderRejectsMissingPermissionWithoutCreatingAFile() {
        var factoryCalled = false
        let service = SystemAudioRecordingService(
            permissionStatus: { .denied },
            recorderFactory: { _, _ in
                factoryCalled = true
                return FakeRecorderDriver()
            }
        )

        XCTAssertThrowsError(try service.start()) { error in
            XCTAssertEqual(error as? AudioRecordingError, .microphonePermissionRequired)
        }
        XCTAssertFalse(factoryCalled)
        XCTAssertFalse(service.isRecording)
    }

    func testRecorderRejectsDoubleStartAndDoubleStop() throws {
        let directory = temporaryTestDirectory()
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let driver = FakeRecorderDriver(elapsedTime: 2)
        let service = makeRecordingService(directory: directory, driver: driver)

        try service.start()
        XCTAssertEqual(driver.requestedDuration, SystemAudioRecordingService.maximumDuration)
        XCTAssertThrowsError(try service.start()) { error in
            XCTAssertEqual(error as? AudioRecordingError, .alreadyRecording)
        }

        let recording = try service.stop()
        XCTAssertEqual(recording.duration, 2)
        XCTAssertEqual(recording.sampleRate, 16_000)
        XCTAssertEqual(recording.channelCount, 1)
        XCTAssertEqual(recording.bitRate, 32_000)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recording.url.path))
        XCTAssertThrowsError(try service.stop()) { error in
            XCTAssertEqual(error as? AudioRecordingError, .noActiveRecording)
        }

        try service.delete(recording)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recording.url.path))
    }

    func testCancelDeletesPartialRecording() throws {
        let directory = temporaryTestDirectory()
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let driver = FakeRecorderDriver(elapsedTime: 1)
        var createdURL: URL?
        let service = SystemAudioRecordingService(
            temporaryRoot: directory,
            permissionStatus: { .granted },
            recorderFactory: { url, _ in
                createdURL = url
                try Data([0x01]).write(to: url)
                return driver
            }
        )

        try service.start()
        try service.cancel()

        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(driver.stopCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(createdURL).path))
    }

    func testMaximumDurationReturnsCompletedArtifactExactlyOnce() async throws {
        let directory = temporaryTestDirectory()
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let driver = FakeRecorderDriver(elapsedTime: 180)
        let service = makeRecordingService(directory: directory, driver: driver)
        let completion = expectation(description: "maximum-duration completion")
        var result: Result<RecordedAudioFile, AudioRecordingError>?
        service.onMaximumDurationReached = { receivedResult in
            result = receivedResult
            completion.fulfill()
        }

        try service.start()
        driver.finish(succeeded: true)
        driver.finish(succeeded: true)
        await fulfillment(of: [completion], timeout: 1)

        let recording = try XCTUnwrap(result).get()
        XCTAssertEqual(recording.duration, 180)
        XCTAssertFalse(service.isRecording)
        try service.delete(recording)
    }

    func testEarlyRecorderFinishFailsAndDeletesPartialArtifact() async throws {
        let directory = temporaryTestDirectory()
        defer { XCTAssertNoThrow(try FileManager.default.removeItem(at: directory)) }
        let driver = FakeRecorderDriver(elapsedTime: 12)
        let service = makeRecordingService(directory: directory, driver: driver)
        let completion = expectation(description: "early completion rejected")
        var result: Result<RecordedAudioFile, AudioRecordingError>?
        service.onMaximumDurationReached = { receivedResult in
            result = receivedResult
            completion.fulfill()
        }

        try service.start()
        driver.finish(succeeded: true)
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertThrowsError(try XCTUnwrap(result).get()) { error in
            XCTAssertEqual(error as? AudioRecordingError, .encodingFailed)
        }
        XCTAssertFalse(service.isRecording)
        let recordingDirectory = directory.appending(component: "dict8-recordings")
        let remaining = try FileManager.default.contentsOfDirectory(
            at: recordingDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(remaining.isEmpty)
    }

    func testCoordinatorOrdersStartCueBeforeRecordingAndDeletesAfterPreview() async throws {
        let eventLog = EventLog()
        let recorder = FakeAudioRecorder(eventLog: eventLog)
        let playback = FakeAudioPlayback(eventLog: eventLog)
        let hud = FakeAudioHUD(eventLog: eventLog)
        let recordingStarted = expectation(description: "recording HUD shown")
        hud.onShowRecording = { recordingStarted.fulfill() }
        let state = AppState(defaults: isolatedDefaults())
        let coordinator = makeCoordinator(
            state: state,
            recorder: recorder,
            playback: playback,
            hud: hud
        )

        coordinator.startTestRecording()
        await fulfillment(of: [recordingStarted], timeout: 1)

        XCTAssertEqual(Array(eventLog.events.prefix(3)), ["start cue", "record start", "HUD show"])
        XCTAssertEqual(state.status, .recording)
        XCTAssertTrue(recorder.isRecording)

        coordinator.stopTestRecording()
        XCTAssertTrue(state.audioTestStatus.hasRecordingReady)
        XCTAssertFalse(recorder.isRecording)

        let deleted = expectation(description: "preview artifact deleted")
        recorder.onDelete = { deleted.fulfill() }
        coordinator.playAndDeleteTestRecording()
        await fulfillment(of: [deleted], timeout: 1)

        XCTAssertEqual(state.audioTestStatus, .idle)
        XCTAssertTrue(eventLog.events.contains("preview"))
    }

    func testDisableCancelsActiveRecordingAndDeletesCompletedArtifact() async {
        let eventLog = EventLog()
        let recorder = FakeAudioRecorder(eventLog: eventLog)
        let hud = FakeAudioHUD(eventLog: eventLog)
        let recordingStarted = expectation(description: "recording started")
        hud.onShowRecording = { recordingStarted.fulfill() }
        let coordinator = makeCoordinator(
            recorder: recorder,
            playback: FakeAudioPlayback(eventLog: eventLog),
            hud: hud
        )

        coordinator.startTestRecording()
        await fulfillment(of: [recordingStarted], timeout: 1)
        coordinator.setEnabled(false)

        XCTAssertEqual(recorder.cancelCount, 1)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertTrue(eventLog.events.contains("HUD hide"))
    }

    func testPushToTalkRefusesKnownSecureFieldBeforeRecording() {
        let eventLog = EventLog()
        let recorder = FakeAudioRecorder(eventLog: eventLog)
        let monitor = FakeAudioPasteLastMonitor()
        let accessibility = FakeAudioAccessibility(secureFieldStatus: .secure)
        let state = AppState(defaults: isolatedDefaults())
        let coordinator = makeCoordinator(
            state: state,
            recorder: recorder,
            playback: FakeAudioPlayback(eventLog: eventLog),
            hud: FakeAudioHUD(eventLog: eventLog),
            accessibility: accessibility,
            monitor: monitor
        )

        monitor.onPushToTalkPressed?()

        XCTAssertEqual(state.lastError, .secureFieldRefused)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(eventLog.events.contains("start cue"))
        XCTAssertTrue(eventLog.events.contains("HUD feedback"))
        withExtendedLifetime(coordinator) {}
    }

    func testPushToTalkReleaseDuringStartCueCancelsWithoutRecording() async {
        let eventLog = EventLog()
        let recorder = FakeAudioRecorder(eventLog: eventLog)
        let monitor = FakeAudioPasteLastMonitor()
        let state = AppState(defaults: isolatedDefaults())
        let coordinator = makeCoordinator(
            state: state,
            recorder: recorder,
            playback: FakeAudioPlayback(eventLog: eventLog),
            hud: FakeAudioHUD(eventLog: eventLog),
            monitor: monitor
        )

        monitor.onPushToTalkPressed?()
        XCTAssertEqual(state.audioTestStatus, .starting)
        monitor.onPushToTalkReleased?()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(state.audioTestStatus, .idle)
        XCTAssertFalse(eventLog.events.contains("record start"))
        XCTAssertEqual(recorder.cancelCount, 1)
        withExtendedLifetime(coordinator) {}
    }

    func testPushToTalkPressAndReleaseProduceOneRecording() async {
        let eventLog = EventLog()
        let recorder = FakeAudioRecorder(eventLog: eventLog)
        let monitor = FakeAudioPasteLastMonitor()
        let hud = FakeAudioHUD(eventLog: eventLog)
        let recordingStarted = expectation(description: "push-to-talk recording started")
        hud.onShowRecording = { recordingStarted.fulfill() }
        let state = AppState(defaults: isolatedDefaults())
        let coordinator = makeCoordinator(
            state: state,
            recorder: recorder,
            playback: FakeAudioPlayback(eventLog: eventLog),
            hud: hud,
            monitor: monitor
        )

        monitor.onPushToTalkPressed?()
        await fulfillment(of: [recordingStarted], timeout: 1)
        monitor.onPushToTalkReleased?()

        XCTAssertEqual(eventLog.events.filter { $0 == "record start" }.count, 1)
        XCTAssertEqual(eventLog.events.filter { $0 == "record stop" }.count, 1)
        XCTAssertFalse(state.audioTestStatus.hasRecordingReady)
        withExtendedLifetime(coordinator) {}
    }

    func testPushToTalkStartsAfterCompletedTranscriptAndClearsIt() async {
        let eventLog = EventLog()
        let recorder = FakeAudioRecorder(eventLog: eventLog)
        let monitor = FakeAudioPasteLastMonitor()
        let hud = FakeAudioHUD(eventLog: eventLog)
        let recordingStarted = expectation(description: "recording restarted after transcript")
        hud.onShowRecording = { recordingStarted.fulfill() }
        let state = AppState(defaults: isolatedDefaults())
        state.setAudioTestStatus(.transcribed(usedFallback: false))
        state.setTestTranscript("synthetic prior transcript")
        let coordinator = makeCoordinator(
            state: state,
            recorder: recorder,
            playback: FakeAudioPlayback(eventLog: eventLog),
            hud: hud,
            monitor: monitor
        )

        monitor.onPushToTalkPressed?()
        await fulfillment(of: [recordingStarted], timeout: 1)

        XCTAssertTrue(recorder.isRecording)
        XCTAssertNil(state.testTranscript)
        monitor.onPushToTalkReleased?()
        withExtendedLifetime(coordinator) {}
    }

    func testStoppedTestRecordingExpiresAndDeletes() async {
        let eventLog = EventLog()
        let recorder = FakeAudioRecorder(eventLog: eventLog)
        let hud = FakeAudioHUD(eventLog: eventLog)
        let recordingStarted = expectation(description: "recording started")
        hud.onShowRecording = { recordingStarted.fulfill() }
        let state = AppState(
            defaults: isolatedDefaults(),
            configuration: audioConfiguration(recordingLifetime: .zero)
        )
        let coordinator = makeCoordinator(
            state: state,
            recorder: recorder,
            playback: FakeAudioPlayback(eventLog: eventLog),
            hud: hud
        )

        coordinator.startTestRecording()
        await fulfillment(of: [recordingStarted], timeout: 1)
        let deleted = expectation(description: "expired recording deleted")
        recorder.onDelete = { deleted.fulfill() }
        coordinator.stopTestRecording()
        await fulfillment(of: [deleted], timeout: 1)

        XCTAssertEqual(state.audioTestStatus, .idle)
    }

    func testTranscriptionDeletesAudioAndSettingsCloseClearsTransientText() async {
        let eventLog = EventLog()
        let recorder = FakeAudioRecorder(eventLog: eventLog)
        let hud = FakeAudioHUD(eventLog: eventLog)
        let started = expectation(description: "recording started")
        hud.onShowRecording = { started.fulfill() }
        let speechToText = FakeAudioSpeechToText(
            result: .success(
                SpeechTranscription(
                    text: "synthetic transient transcript",
                    model: "synthetic/primary",
                    usedFallback: false,
                    latency: .milliseconds(10),
                    recordedDuration: 2,
                    usage: nil
                )
            )
        )
        let state = AppState(defaults: isolatedDefaults())
        let coordinator = makeCoordinator(
            state: state,
            recorder: recorder,
            playback: FakeAudioPlayback(eventLog: eventLog),
            hud: hud,
            speechToText: speechToText
        )

        coordinator.startTestRecording()
        await fulfillment(of: [started], timeout: 1)
        coordinator.stopTestRecording()
        let deleted = expectation(description: "transcribed audio deleted")
        recorder.onDelete = { deleted.fulfill() }
        coordinator.transcribeAndDeleteTestRecording()
        await fulfillment(of: [deleted], timeout: 1)

        XCTAssertEqual(state.testTranscript, "synthetic transient transcript")
        XCTAssertEqual(state.audioTestStatus, .transcribed(usedFallback: false))
        XCTAssertEqual(state.status, .completed)
        XCTAssertEqual(state.audioTranscriptionTestMetadata?.model, "synthetic/primary")
        XCTAssertEqual(
            state.audioTranscriptionTestMetadata?.latencySeconds ?? -1,
            0.01,
            accuracy: 0.000_001
        )

        coordinator.closeSettingsValidation()

        XCTAssertNil(state.testTranscript)
        XCTAssertNil(state.audioTranscriptionTestMetadata)
        XCTAssertEqual(state.audioTestStatus, .idle)
    }

    func testTranscriptionFailureStillDeletesAudioAndKeepsClipboardIndependent() async {
        let eventLog = EventLog()
        let recorder = FakeAudioRecorder(eventLog: eventLog)
        let hud = FakeAudioHUD(eventLog: eventLog)
        let started = expectation(description: "recording started")
        hud.onShowRecording = { started.fulfill() }
        let state = AppState(defaults: isolatedDefaults())
        let coordinator = makeCoordinator(
            state: state,
            recorder: recorder,
            playback: FakeAudioPlayback(eventLog: eventLog),
            hud: hud,
            speechToText: FakeAudioSpeechToText(
                result: .failure(.transport(.authentication))
            )
        )

        coordinator.startTestRecording()
        await fulfillment(of: [started], timeout: 1)
        coordinator.stopTestRecording()
        let deleted = expectation(description: "failed transcription audio deleted")
        recorder.onDelete = { deleted.fulfill() }
        coordinator.transcribeAndDeleteTestRecording()
        await fulfillment(of: [deleted], timeout: 1)

        XCTAssertNil(state.testTranscript)
        XCTAssertEqual(
            state.lastError,
            .transcriptionFailed(.transport(.authentication))
        )
        XCTAssertEqual(state.audioTestStatus, .idle)
    }

    private func makeRecordingService(
        directory: URL,
        driver: FakeRecorderDriver
    ) -> SystemAudioRecordingService {
        SystemAudioRecordingService(
            temporaryRoot: directory,
            permissionStatus: { .granted },
            recorderFactory: { url, _ in
                try Data([0x01, 0x02]).write(to: url)
                return driver
            }
        )
    }

    private func temporaryTestDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(component: "PhaseThreeAudioTests-\(UUID().uuidString)")
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PhaseThreeAudioTests.\(UUID().uuidString)") ?? .standard
    }

    private func audioConfiguration(recordingLifetime: Duration) -> AppConfiguration {
        AppConfiguration(
            hotkeyDisplayName: "Control + Option",
            pasteLastHotkeyDisplayName: "Command + Control + V",
            hudPreviewDuration: .zero,
            testPasteDelay: .zero,
            testPasteText: "synthetic paste",
            testRecordingLifetime: recordingLifetime,
            testTranscriptLifetime: .seconds(120)
        )
    }

    private func makeCoordinator(
        state: AppState? = nil,
        recorder: FakeAudioRecorder,
        playback: FakeAudioPlayback,
        hud: FakeAudioHUD,
        speechToText: any SpeechToTextProviding = UnavailableSpeechToTextService(),
        accessibility: FakeAudioAccessibility = FakeAudioAccessibility(),
        monitor: FakeAudioPasteLastMonitor = FakeAudioPasteLastMonitor()
    ) -> AppCoordinator {
        AppCoordinator(
            state: state ?? AppState(defaults: isolatedDefaults()),
            apiKeyStore: FakeAudioAPIKeyStore(),
            launchAtLoginService: FakeAudioLaunchAtLogin(),
            accessibility: accessibility,
            microphonePermission: FakeAudioMicrophonePermission(),
            audioRecorder: recorder,
            audioPlayback: playback,
            speechToText: speechToText,
            pasteService: FakeAudioTextPaste(),
            lastDictationCache: FakeAudioCache(),
            hotkeyMonitor: monitor,
            hud: hud
        )
    }
}

private actor FakeAudioSpeechToText: SpeechToTextProviding {
    private let result: Result<SpeechTranscription, SpeechToTextError>

    init(result: Result<SpeechTranscription, SpeechToTextError>) {
        self.result = result
    }

    func transcribe(_ recording: RecordedAudioFile) throws -> SpeechTranscription {
        try result.get()
    }
}

@MainActor
private final class FakeRecorderDriver: AudioRecorderDriving {
    var elapsedTime: TimeInterval
    var onFinished: ((Bool) -> Void)?
    private(set) var requestedDuration: TimeInterval?
    private(set) var stopCount = 0

    init(elapsedTime: TimeInterval = 1) {
        self.elapsedTime = elapsedTime
    }

    func prepareToRecord() -> Bool { true }

    func record(forDuration duration: TimeInterval) -> Bool {
        requestedDuration = duration
        return true
    }

    func stop() { stopCount += 1 }
    func finish(succeeded: Bool) { onFinished?(succeeded) }
}

@MainActor
private final class EventLog {
    private(set) var events: [String] = []
    func append(_ event: String) { events.append(event) }
}

@MainActor
private final class FakeAudioRecorder: AudioRecording {
    var isRecording = false
    var elapsedTime: TimeInterval = 1
    var onMaximumDurationReached: ((Result<RecordedAudioFile, AudioRecordingError>) -> Void)?
    var onDelete: (() -> Void)?
    private(set) var cancelCount = 0
    private let eventLog: EventLog
    private let recording = RecordedAudioFile(
        url: URL(fileURLWithPath: "/tmp/synthetic-phase-three.m4a"),
        duration: 2,
        sampleRate: 16_000,
        channelCount: 1,
        bitRate: 32_000
    )

    init(eventLog: EventLog) {
        self.eventLog = eventLog
    }

    func start() throws {
        eventLog.append("record start")
        isRecording = true
    }

    func stop() throws -> RecordedAudioFile {
        eventLog.append("record stop")
        isRecording = false
        return recording
    }

    func cancel() throws {
        cancelCount += 1
        isRecording = false
        eventLog.append("record cancel")
    }

    func delete(_ recording: RecordedAudioFile) throws {
        eventLog.append("delete")
        onDelete?()
    }
}

@MainActor
private final class FakeAudioPlayback: AudioPlaybackProviding {
    private let eventLog: EventLog

    init(eventLog: EventLog) {
        self.eventLog = eventLog
    }

    func playStartCue() async throws { eventLog.append("start cue") }
    func playStopCue() async throws { eventLog.append("stop cue") }
    func playPreview(at url: URL) async throws { eventLog.append("preview") }
    func stop() {}
}

@MainActor
private final class FakeAudioHUD: RecordingHUDPresenting {
    var onShowRecording: (() -> Void)?
    private let eventLog: EventLog

    init(eventLog: EventLog) {
        self.eventLog = eventLog
    }

    func showPreview(for duration: Duration) {}
    func showRecording() {
        eventLog.append("HUD show")
        onShowRecording?()
    }
    func showFeedback(_ feedback: TransientFeedback) {
        eventLog.append("HUD feedback")
    }
    func hide() { eventLog.append("HUD hide") }
}

private actor FakeAudioAPIKeyStore: APIKeyStoring {
    func status() -> APIKeyStatus { .missing }
    func apiKey() throws -> String { throw APIKeyStoreError.missingKey }
    func save(_ key: String) {}
    func remove() {}
}

@MainActor
private final class FakeAudioLaunchAtLogin: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus = .notRegistered
    func setEnabled(_ isEnabled: Bool) {}
    func openSystemSettings() {}
}

@MainActor
private final class FakeAudioAccessibility: AccessibilityInspecting {
    var permissionStatus: AccessibilityPermissionStatus = .granted
    private let secureFieldStatus: SecureFieldStatus

    init(secureFieldStatus: SecureFieldStatus = .notSecure) {
        self.secureFieldStatus = secureFieldStatus
    }

    func requestPermission() {}
    func openSystemSettings() -> Bool { true }
    func captureTarget() -> PasteTarget {
        PasteTarget(
            bundleIdentifier: "com.example.target",
            processIdentifier: 1,
            secureFieldStatus: secureFieldStatus
        )
    }
    func readFocusedElementText(in application: NSRunningApplication?) -> String? { nil }
}

@MainActor
private final class FakeAudioMicrophonePermission: MicrophonePermissionControlling {
    var status: MicrophonePermissionStatus = .granted
    func requestPermission() async -> MicrophonePermissionStatus { status }
    func openSystemSettings() -> Bool { true }
}

@MainActor
private final class FakeAudioTextPaste: TextPasting {
    func paste(_ text: String, originatingTarget: PasteTarget) async throws -> TextPasteResult {
        .pasted(secureFieldStatusUnknown: false)
    }
}

@MainActor
private final class FakeAudioCache: LastDictationCaching {
    func store(_ text: String) {}
    func value() -> String? { nil }
    func clear() {}
}

@MainActor
private final class FakeAudioPasteLastMonitor: HotkeyMonitoring {
    var isRunning = false
    var onPushToTalkPressed: (() -> Void)?
    var onPushToTalkReleased: (() -> Void)?
    var onPasteLast: (() -> Void)?
    func start() throws { isRunning = true }
    func stop() { isRunning = false }
}
