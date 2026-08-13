import AppKit
import Foundation
import XCTest

@testable import dict8

@MainActor
final class PhaseEightPipelineTests: XCTestCase {
    func testSuccessfulPipelinePastesCleanedTextDeletesAudioCachesAndReportsTiming() async {
        let harness = PipelineHarness()

        await runDictation(harness)
        await waitUntil { harness.paste.texts.count == 1 && harness.state.status == .completed }

        XCTAssertEqual(harness.paste.texts, ["Cleaned synthetic transcript."])
        XCTAssertEqual(harness.cache.value(), "Cleaned synthetic transcript.")
        XCTAssertEqual(harness.recorder.deleteCount, 1)
        XCTAssertNil(harness.state.lastError)
        XCTAssertEqual(harness.metrics.snapshot.requestCount, 1)
        XCTAssertEqual(harness.metrics.snapshot.successCount, 1)
        XCTAssertEqual(harness.metrics.snapshot.totalTranscriptionCost, 0.003)
        XCTAssertEqual(harness.metrics.snapshot.totalCleanupCost, 0.000_02)
        let timing = try? XCTUnwrap(harness.timing.value)
        XCTAssertNotNil(timing?.transcription)
        XCTAssertNotNil(timing?.cleanup)
        XCTAssertNotNil(timing?.paste)
        XCTAssertEqual(harness.hud.processingShowCount, 1)
        XCTAssertEqual(harness.hud.processingFinishCount, 1)
    }

    func testCleanupFailurePastesRawTranscriptAndWarns() async {
        let harness = PipelineHarness(
            cleanupResult: .failure(.suspiciousOutput(.substantialExpansion))
        )

        await runDictation(harness)
        await waitUntil { harness.state.status == .warning }

        XCTAssertEqual(harness.paste.texts, ["raw synthetic transcript"])
        XCTAssertEqual(
            harness.state.lastError,
            .cleanupFailed(.suspiciousOutput(.substantialExpansion))
        )
        XCTAssertTrue(harness.hud.feedback.contains(.cleanupRawFallback))
        XCTAssertEqual(harness.recorder.deleteCount, 1)
        XCTAssertEqual(harness.metrics.snapshot.cleanupFallbackCount, 1)
    }

    func testTranscriptionFailureDeletesAudioWithoutCleanupPasteOrCache() async {
        let failure = SpeechToTextError.emptyTranscript
        let harness = PipelineHarness(transcriptionResult: .failure(failure))

        await runDictation(harness)
        await waitUntil { harness.state.lastError == .transcriptionFailed(failure) }

        XCTAssertTrue(harness.paste.texts.isEmpty)
        XCTAssertNil(harness.cache.value())
        let cleanupCalls = await harness.cleanup.callCount()
        XCTAssertEqual(cleanupCalls, 0)
        XCTAssertEqual(harness.recorder.deleteCount, 1)
        XCTAssertEqual(harness.metrics.snapshot.failureCount, 1)
    }

    func testTranscriptionAndDeletionFailureReportsCombinedSanitizedError() async {
        let failure = SpeechToTextError.emptyTranscript
        let harness = PipelineHarness(
            transcriptionResult: .failure(failure),
            deleteFailuresBeforeSuccess: 2
        )

        await runDictation(harness)
        await waitUntil {
            harness.state.lastError == .transcriptionAndAudioCleanupFailed(failure)
        }

        XCTAssertEqual(harness.recorder.deleteCount, 2)
        XCTAssertTrue(harness.paste.texts.isEmpty)
        XCTAssertNil(harness.cache.value())
        XCTAssertEqual(harness.metrics.snapshot.failureCount, 1)
    }

    func testFocusChangeCopiesCachesAndWarns() async {
        let harness = PipelineHarness(pasteResult: .success(.copiedBecauseTargetChanged))

        await runDictation(harness)
        await waitUntil { harness.state.lastError == .focusChangedCopied }

        XCTAssertEqual(harness.cache.value(), "Cleaned synthetic transcript.")
        XCTAssertTrue(harness.hud.feedback.contains(.copiedBecauseFocusChanged))
        XCTAssertEqual(harness.metrics.snapshot.successCount, 1)
    }

    func testPasteEventFailureCachesClipboardTextAndReportsError() async {
        let harness = PipelineHarness(pasteResult: .failure(.eventCreationFailed))

        await runDictation(harness)
        await waitUntil { harness.state.lastError == .pasteEventCreationFailed }

        XCTAssertEqual(harness.cache.value(), "Cleaned synthetic transcript.")
        XCTAssertEqual(harness.paste.texts, ["Cleaned synthetic transcript."])
        XCTAssertEqual(harness.metrics.snapshot.successCount, 1)
    }

    func testClipboardFailureDoesNotSeedCache() async {
        let harness = PipelineHarness(pasteResult: .failure(.clipboardWriteFailed))

        await runDictation(harness)
        await waitUntil { harness.state.lastError == .clipboardWriteFailed }

        XCTAssertNil(harness.cache.value())
        XCTAssertEqual(harness.metrics.snapshot.failureCount, 1)
    }

    func testAudioDeletionFailureRetriesAndStillPastes() async {
        let harness = PipelineHarness(deleteFailuresBeforeSuccess: 2)

        await runDictation(harness)
        await waitUntil { harness.state.lastError == .temporaryAudioCleanupFailed }

        XCTAssertEqual(harness.recorder.deleteCount, 2)
        XCTAssertEqual(harness.paste.texts, ["Cleaned synthetic transcript."])
        XCTAssertTrue(harness.hud.feedback.contains(.temporaryAudioCleanupFailed))
    }

    func testTranscriptionFallbackNotificationIsContentFreeAndFinalWarningReflectsIt() async {
        let harness = PipelineHarness(
            transcriptionResult: .success(Self.transcription(usedFallback: true)),
            cleanupResult: .success(Self.cleanup())
        )

        await runDictation(harness)
        await waitUntil { harness.state.lastError == .transcriptionFallbackUsed }

        XCTAssertTrue(harness.hud.feedback.contains(.transcriptionFallbackUsed))
        XCTAssertFalse(
            harness.hud.feedback.map(\.message).contains {
                $0.contains("raw synthetic transcript")
            }
        )
    }

    func testDisableCancelsSuspendedPipelineDeletesAudioAndRejectsNewPress() async {
        let harness = PipelineHarness(transcriptionDelay: .seconds(60))

        harness.monitor.onPushToTalkPressed?()
        await waitUntil { harness.recorder.isRecording }
        harness.monitor.onPushToTalkReleased?()
        await waitUntil { harness.state.status == .transcribing }

        harness.monitor.onPushToTalkPressed?()
        XCTAssertEqual(harness.recorder.startCount, 1)
        XCTAssertTrue(harness.hud.isProcessingVisible)
        harness.coordinator.setEnabled(false)
        await waitUntil { harness.recorder.deleteCount == 1 }

        XCTAssertTrue(harness.paste.texts.isEmpty)
        XCTAssertEqual(harness.state.status, .disabled)
        XCTAssertNil(harness.cache.value())
        XCTAssertEqual(harness.metrics.snapshot.requestCount, 1)
        XCTAssertEqual(harness.metrics.snapshot.successCount, 0)
        XCTAssertEqual(harness.metrics.snapshot.failureCount, 0)
        XCTAssertEqual(harness.metrics.snapshot.cancellationCount, 1)
        XCTAssertFalse(harness.hud.isProcessingVisible)
    }

    func testWorkspaceLifecycleNotificationsCancelPipelineAndClearCache() async {
        let notifications = [
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
        ]

        for notification in notifications {
            let harness = PipelineHarness(transcriptionDelay: .seconds(60))
            harness.coordinator.startIfNeeded()

            harness.monitor.onPushToTalkPressed?()
            await waitUntil { harness.recorder.isRecording }
            harness.monitor.onPushToTalkReleased?()
            await waitUntil { harness.state.status == .transcribing }
            harness.cache.store("synthetic cached result")

            NSWorkspace.shared.notificationCenter.post(name: notification, object: nil)
            await waitUntil { harness.recorder.deleteCount == 1 }

            XCTAssertTrue(harness.paste.texts.isEmpty)
            XCTAssertNil(harness.cache.value())
            XCTAssertEqual(harness.metrics.snapshot.cancellationCount, 1)
        }
    }

    func testPrepareForQuitCancelsPipelineDeletesAudioAndClearsCache() async {
        let harness = PipelineHarness(transcriptionDelay: .seconds(60))

        harness.monitor.onPushToTalkPressed?()
        await waitUntil { harness.recorder.isRecording }
        harness.monitor.onPushToTalkReleased?()
        await waitUntil { harness.state.status == .transcribing }
        harness.cache.store("synthetic cached result")

        harness.coordinator.prepareForQuit()
        await waitUntil { harness.recorder.deleteCount == 1 }

        XCTAssertTrue(harness.paste.texts.isEmpty)
        XCTAssertNil(harness.cache.value())
        XCTAssertEqual(harness.metrics.snapshot.cancellationCount, 1)
    }

    func testAutomaticCutoffStartsPipelineOnceAndReleaseIsHarmless() async {
        let harness = PipelineHarness()

        harness.monitor.onPushToTalkPressed?()
        await waitUntil { harness.recorder.isRecording }
        harness.recorder.finishAutomatically()
        await waitUntil { harness.paste.texts.count == 1 }
        harness.monitor.onPushToTalkReleased?()
        await Task.yield()

        XCTAssertEqual(harness.paste.texts.count, 1)
        XCTAssertEqual(harness.recorder.startCount, 1)
        XCTAssertTrue(harness.hud.feedback.contains(.recordingLimitReached))
    }

    func testStopCueFailureDoesNotBlockDelivery() async {
        let harness = PipelineHarness(stopCueFails: true)

        await runDictation(harness)
        await waitUntil { harness.state.lastError == .recordingCueFailed }

        XCTAssertEqual(harness.paste.texts, ["Cleaned synthetic transcript."])
        XCTAssertTrue(harness.hud.feedback.contains(.recordingCueFailed))
    }

    func testBriefRecordingIsDiscardedWithoutTranscriptionOrPaste() async {
        let harness = PipelineHarness(recordedDuration: 0.2)

        await runDictation(harness)
        await waitUntil { harness.state.status == .idle }

        XCTAssertTrue(harness.paste.texts.isEmpty)
        XCTAssertNil(harness.cache.value())
        let transcriptionCalls = await harness.transcription.callCount()
        XCTAssertEqual(transcriptionCalls, 0)
        let cleanupCalls = await harness.cleanup.callCount()
        XCTAssertEqual(cleanupCalls, 0)
        XCTAssertEqual(harness.recorder.deleteCount, 1)
        XCTAssertNil(harness.state.lastError)
        XCTAssertEqual(harness.metrics.snapshot.requestCount, 0)
    }

    func testSilentRecordingIsDiscardedWithoutTranscriptionOrPaste() async {
        let harness = PipelineHarness(recordedDuration: 3, isSilent: true)

        await runDictation(harness)
        await waitUntil { harness.state.status == .idle }

        XCTAssertTrue(harness.paste.texts.isEmpty)
        XCTAssertNil(harness.cache.value())
        let transcriptionCalls = await harness.transcription.callCount()
        XCTAssertEqual(transcriptionCalls, 0)
        let cleanupCalls = await harness.cleanup.callCount()
        XCTAssertEqual(cleanupCalls, 0)
        XCTAssertEqual(harness.recorder.deleteCount, 1)
        XCTAssertNil(harness.state.lastError)
        XCTAssertEqual(harness.metrics.snapshot.requestCount, 0)
    }

    private func runDictation(_ harness: PipelineHarness) async {
        harness.monitor.onPushToTalkPressed?()
        await waitUntil { harness.recorder.isRecording }
        harness.monitor.onPushToTalkReleased?()
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for pipeline state", file: file, line: line)
    }

    fileprivate static func transcription(usedFallback: Bool = false) -> SpeechTranscription {
        SpeechTranscription(
            text: "raw synthetic transcript",
            model: usedFallback ? "synthetic/stt-fallback" : "synthetic/stt-primary",
            usedFallback: usedFallback,
            latency: .milliseconds(10),
            recordedDuration: 2,
            usage: SpeechTranscriptionUsage(
                audioSeconds: 2,
                totalTokens: nil,
                inputTokens: nil,
                outputTokens: nil,
                cost: 0.003
            )
        )
    }

    fileprivate static func cleanup() -> TextCleanupResult {
        TextCleanupResult(
            text: "Cleaned synthetic transcript.",
            model: "openrouter/auto",
            latency: .milliseconds(10),
            usage: TextCleanupUsage(
                promptTokens: nil,
                completionTokens: nil,
                totalTokens: nil,
                cost: 0.000_02
            )
        )
    }
}

@MainActor
private final class PipelineHarness {
    let state: AppState
    let recorder: PipelineRecorder
    let playback: PipelinePlayback
    let transcription: PipelineTranscription
    let cleanup: PipelineCleanup
    let paste: PipelinePaste
    let cache: PipelineCache
    let monitor: PipelineMonitor
    let hud: PipelineHUD
    let timing: PipelineTimingCapture
    let metrics: NoOpUsageMetricsStore
    let coordinator: AppCoordinator

    init(
        transcriptionResult: Result<SpeechTranscription, SpeechToTextError> = .success(
            PhaseEightPipelineTests.transcription()
        ),
        cleanupResult: Result<TextCleanupResult, TextCleanupError> = .success(
            PhaseEightPipelineTests.cleanup()
        ),
        pasteResult: Result<TextPasteResult, TextPasteError> = .success(
            .pasted(secureFieldStatusUnknown: false)
        ),
        transcriptionDelay: Duration = .zero,
        deleteFailuresBeforeSuccess: Int = 0,
        stopCueFails: Bool = false,
        recordedDuration: TimeInterval = 2,
        isSilent: Bool = false
    ) {
        let suite = "PhaseEightPipelineTests.\(UUID().uuidString)"
        state = AppState(defaults: UserDefaults(suiteName: suite) ?? .standard)
        recorder = PipelineRecorder(
            deleteFailuresBeforeSuccess: deleteFailuresBeforeSuccess,
            recordedDuration: recordedDuration
        )
        playback = PipelinePlayback(stopCueFails: stopCueFails)
        transcription = PipelineTranscription(
            result: transcriptionResult,
            delay: transcriptionDelay
        )
        cleanup = PipelineCleanup(result: cleanupResult)
        paste = PipelinePaste(result: pasteResult)
        cache = PipelineCache()
        monitor = PipelineMonitor()
        hud = PipelineHUD()
        timing = PipelineTimingCapture()
        metrics = NoOpUsageMetricsStore()
        coordinator = AppCoordinator(
            state: state,
            apiKeyStore: PipelineAPIKeyStore(),
            launchAtLoginService: PipelineLaunchAtLogin(),
            accessibility: PipelineAccessibility(),
            microphonePermission: PipelineMicrophonePermission(),
            audioRecorder: recorder,
            audioPlayback: playback,
            silenceDetector: PipelineSilenceDetector(isSilent: isSilent),
            speechToText: transcription,
            textCleanup: cleanup,
            pasteService: paste,
            lastDictationCache: cache,
            hotkeyMonitor: monitor,
            hud: hud,
            pipelineTimingHandler: { [timing] value in
                timing.value = value
            },
            metricsStore: metrics
        )
    }
}

private struct PipelineSilenceDetector: SilenceDetecting {
    let isSilent: Bool

    func isSilent(_ recording: RecordedAudioFile) async -> Bool {
        isSilent
    }
}

private actor PipelineTranscription: SpeechToTextProviding {
    private let result: Result<SpeechTranscription, SpeechToTextError>
    private let delay: Duration
    private var calls = 0

    init(result: Result<SpeechTranscription, SpeechToTextError>, delay: Duration) {
        self.result = result
        self.delay = delay
    }

    func transcribe(_ recording: RecordedAudioFile) async throws -> SpeechTranscription {
        calls += 1
        if delay != .zero {
            try await Task.sleep(for: delay)
        }
        return try result.get()
    }

    func callCount() -> Int { calls }
}

private actor PipelineCleanup: TextCleanupProviding {
    private let result: Result<TextCleanupResult, TextCleanupError>
    private var calls = 0

    init(result: Result<TextCleanupResult, TextCleanupError>) {
        self.result = result
    }

    func clean(_ transcript: String) async throws -> TextCleanupResult {
        calls += 1
        return try result.get()
    }

    func callCount() -> Int { calls }
}

@MainActor
private final class PipelineRecorder: AudioRecording {
    var isRecording = false
    var elapsedTime: TimeInterval = 1
    var onMaximumDurationReached: ((Result<RecordedAudioFile, AudioRecordingError>) -> Void)?
    private(set) var startCount = 0
    private(set) var deleteCount = 0
    private let deleteFailuresBeforeSuccess: Int
    private let recording: RecordedAudioFile

    init(deleteFailuresBeforeSuccess: Int, recordedDuration: TimeInterval = 2) {
        self.deleteFailuresBeforeSuccess = deleteFailuresBeforeSuccess
        self.recording = RecordedAudioFile(
            url: URL(fileURLWithPath: "/tmp/synthetic-phase-eight.m4a"),
            duration: recordedDuration,
            sampleRate: 16_000,
            channelCount: 1,
            bitRate: 32_000
        )
    }

    func start() throws {
        startCount += 1
        isRecording = true
    }

    func stop() throws -> RecordedAudioFile {
        guard isRecording else { throw AudioRecordingError.noActiveRecording }
        isRecording = false
        return recording
    }

    func cancel() throws { isRecording = false }

    func delete(_ recording: RecordedAudioFile) throws {
        deleteCount += 1
        if deleteCount <= deleteFailuresBeforeSuccess {
            throw AudioRecordingError.temporaryFileCleanupFailed
        }
    }

    func finishAutomatically() {
        isRecording = false
        onMaximumDurationReached?(.success(recording))
    }
}

@MainActor
private final class PipelinePlayback: AudioPlaybackProviding {
    private let stopCueFails: Bool

    init(stopCueFails: Bool) {
        self.stopCueFails = stopCueFails
    }

    func playStartCue() async throws {}
    func playStopCue() async throws {
        if stopCueFails { throw CocoaError(.fileReadUnknown) }
    }
    func playPreview(at url: URL) async throws {}
    func stop() {}
}

@MainActor
private final class PipelinePaste: TextPasting {
    private let result: Result<TextPasteResult, TextPasteError>
    private(set) var texts: [String] = []

    init(result: Result<TextPasteResult, TextPasteError>) {
        self.result = result
    }

    func paste(_ text: String, originatingTarget: PasteTarget) async throws -> TextPasteResult {
        texts.append(text)
        return try result.get()
    }
}

@MainActor
private final class PipelineCache: LastDictationCaching {
    private var stored: String?
    func store(_ text: String) { stored = text }
    func value() -> String? { stored }
    func clear() { stored = nil }
}

@MainActor
private final class PipelineMonitor: HotkeyMonitoring {
    var isRunning = false
    var onPushToTalkPressed: (() -> Void)?
    var onPushToTalkReleased: (() -> Void)?
    var onPasteLast: (() -> Void)?
    func start() throws { isRunning = true }
    func stop() { isRunning = false }
}

@MainActor
private final class PipelineHUD: RecordingHUDPresenting {
    private(set) var feedback: [TransientFeedback] = []
    private(set) var processingShowCount = 0
    private(set) var processingFinishCount = 0
    private(set) var isProcessingVisible = false
    func showPreview(for duration: Duration) {}
    func showRecording() {}
    func showProcessing() {
        processingShowCount += 1
        isProcessingVisible = true
    }
    func showFeedback(_ feedback: TransientFeedback) { self.feedback.append(feedback) }
    func finishProcessing() {
        processingFinishCount += 1
        isProcessingVisible = false
    }
    func hide() { isProcessingVisible = false }
}

@MainActor
private final class PipelineTimingCapture {
    var value: DictationPipelineTiming?
}

private actor PipelineAPIKeyStore: APIKeyStoring {
    func status() -> APIKeyStatus { .storedInKeychain }
    func apiKey() throws -> String { throw APIKeyStoreError.missingKey }
    func save(_ key: String) {}
    func remove() {}
}

@MainActor
private final class PipelineLaunchAtLogin: LaunchAtLoginControlling {
    var status: LaunchAtLoginStatus = .notRegistered
    func setEnabled(_ isEnabled: Bool) {}
    func openSystemSettings() {}
}

@MainActor
private final class PipelineAccessibility: AccessibilityInspecting {
    var permissionStatus: AccessibilityPermissionStatus = .granted
    func requestPermission() {}
    func openSystemSettings() -> Bool { true }
    func captureTarget() -> PasteTarget {
        PasteTarget(
            bundleIdentifier: "com.example.origin",
            processIdentifier: 42,
            secureFieldStatus: .notSecure
        )
    }
}

@MainActor
private final class PipelineMicrophonePermission: MicrophonePermissionControlling {
    var status: MicrophonePermissionStatus = .granted
    func requestPermission() async -> MicrophonePermissionStatus { status }
    func openSystemSettings() -> Bool { true }
}
