import AppKit
import Foundation

nonisolated struct DictationPipelineTiming: Equatable, Sendable {
    let transcription: Duration?
    let cleanup: Duration?
    let paste: Duration?
    let total: Duration
}

private enum ProductionPasteOutcome: Equatable {
    case pasted
    case copiedBecauseTargetChanged
}

@MainActor
final class AppCoordinator {
    let state: AppState

    private let apiKeyStore: any APIKeyStoring
    private let launchAtLoginService: any LaunchAtLoginControlling
    private let accessibility: any AccessibilityInspecting
    private let microphonePermission: any MicrophonePermissionControlling
    private let audioRecorder: any AudioRecording
    private let audioPlayback: any AudioPlaybackProviding
    private let speechToText: any SpeechToTextProviding
    private let localSpeechToText: (any SpeechToTextProviding)?
    private let textCleanup: any TextCleanupProviding
    private let openRouterClient: (any OpenRouterTransporting)?
    private let pasteService: any TextPasting
    private let lastDictationCache: any LastDictationCaching
    private let cleanupDiagnosticStore: any CleanupDiagnosticLogging
    private let hotkeyMonitor: any HotkeyMonitoring
    private let hud: any RecordingHUDPresenting
    private let pipelineTimingHandler: @MainActor (DictationPipelineTiming) -> Void
    private let metricsStore: any UsageMetricsRecording
    private let temporaryAudioMaintenance: any TemporaryAudioMaintaining
    private var keychainTask: Task<Void, Never>?
    private var pasteTask: Task<Void, Never>?
    private var microphonePermissionTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var elapsedAudioTask: Task<Void, Never>?
    private var audioExpirationTask: Task<Void, Never>?
    private var transcriptExpirationTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var cleanupExpirationTask: Task<Void, Never>?
    private var pipelineTask: Task<Void, Never>?
    private var completionResetTask: Task<Void, Never>?
    private var temporaryAudioMaintenanceTask: Task<Void, Never>?
    private var testRecording: RecordedAudioFile?
    private var recordingOriginatingTarget: PasteTarget?
    private var productionRecording: (generation: Int, file: RecordedAudioFile)?
    private var audioGeneration = 0
    private var pasteGeneration = 0
    private var cleanupGeneration = 0
    private var pipelineGeneration = 0
    private var hasStarted = false
    private var lifecycleObservers: [NSObjectProtocol] = []

    init(
        state: AppState,
        apiKeyStore: any APIKeyStoring,
        launchAtLoginService: any LaunchAtLoginControlling,
        accessibility: any AccessibilityInspecting,
        microphonePermission: any MicrophonePermissionControlling,
        audioRecorder: any AudioRecording,
        audioPlayback: any AudioPlaybackProviding,
        speechToText: any SpeechToTextProviding = UnavailableSpeechToTextService(),
        localSpeechToText: (any SpeechToTextProviding)? = nil,
        textCleanup: any TextCleanupProviding = UnavailableTextCleanupService(),
        openRouterClient: (any OpenRouterTransporting)? = nil,
        pasteService: any TextPasting,
        lastDictationCache: any LastDictationCaching,
        cleanupDiagnosticStore: any CleanupDiagnosticLogging = NoOpCleanupDiagnosticStore(),
        hotkeyMonitor: any HotkeyMonitoring,
        hud: any RecordingHUDPresenting,
        pipelineTimingHandler: @escaping @MainActor (DictationPipelineTiming) -> Void = { _ in },
        metricsStore: any UsageMetricsRecording = NoOpUsageMetricsStore(),
        temporaryAudioMaintenance: any TemporaryAudioMaintaining = NoOpTemporaryAudioMaintenance()
    ) {
        self.state = state
        self.apiKeyStore = apiKeyStore
        self.launchAtLoginService = launchAtLoginService
        self.accessibility = accessibility
        self.microphonePermission = microphonePermission
        self.audioRecorder = audioRecorder
        self.audioPlayback = audioPlayback
        self.speechToText = speechToText
        self.localSpeechToText = localSpeechToText
        self.textCleanup = textCleanup
        self.openRouterClient = openRouterClient
        self.pasteService = pasteService
        self.lastDictationCache = lastDictationCache
        self.cleanupDiagnosticStore = cleanupDiagnosticStore
        self.hotkeyMonitor = hotkeyMonitor
        self.hud = hud
        self.pipelineTimingHandler = pipelineTimingHandler
        self.metricsStore = metricsStore
        self.temporaryAudioMaintenance = temporaryAudioMaintenance

        hotkeyMonitor.onPushToTalkPressed = { [weak self] in
            self?.pushToTalkPressed()
        }
        hotkeyMonitor.onPushToTalkReleased = { [weak self] in
            self?.pushToTalkReleased()
        }
        hotkeyMonitor.onPasteLast = { [weak self] in
            self?.pasteLastDictation()
        }
        audioRecorder.onMaximumDurationReached = { [weak self] result in
            self?.handleMaximumDurationResult(result)
        }
    }

    deinit {
        keychainTask?.cancel()
        pasteTask?.cancel()
        microphonePermissionTask?.cancel()
        audioTask?.cancel()
        elapsedAudioTask?.cancel()
        audioExpirationTask?.cancel()
        transcriptExpirationTask?.cancel()
        cleanupTask?.cancel()
        cleanupExpirationTask?.cancel()
        pipelineTask?.cancel()
        completionResetTask?.cancel()
        temporaryAudioMaintenanceTask?.cancel()
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        installLifecycleObservers()
        refreshConfiguration()
        sweepStaleTemporaryAudio()
    }

    func refreshConfiguration() {
        state.setLaunchAtLoginStatus(launchAtLoginService.status)
        refreshAccessibilityPermission()
        refreshMicrophonePermission()
        refreshAPIKeyStatus()
        refreshUsageMetrics()
        refreshCleanupDiagnostics()
    }

    func refreshCleanupDiagnostics() {
        state.setCleanupDiagnostics(cleanupDiagnosticStore.entries())
    }

    func clearCleanupDiagnostics() {
        cleanupDiagnosticStore.clear()
        state.clearCleanupDiagnostics()
    }

    func setEnabled(_ isEnabled: Bool) {
        state.setEnabled(isEnabled)
        state.setTestPasteStatus(.idle)

        if isEnabled {
            refreshAccessibilityPermission()
        } else {
            cancelProductionPipeline()
            cancelAudioTest()
            cancelCleanupTest(clearInput: true)
            pasteGeneration += 1
            pasteTask?.cancel()
            pasteTask = nil
            hotkeyMonitor.stop()
            state.setHotkeyMonitorStatus(.stopped)
            lastDictationCache.clear()
            cleanupDiagnosticStore.clear()
            state.clearCleanupDiagnostics()
        }
    }

    func setTranscriptionEngine(_ engine: AppState.TranscriptionEngine) {
        state.setTranscriptionEngine(engine)
    }

    func setSelectedCleanupModel(_ model: String) {
        state.setSelectedCleanupModel(model)
    }

    func setCustomVocabulary(_ vocabulary: String) {
        state.setCustomVocabulary(vocabulary)
    }

    private var activeSpeechToText: any SpeechToTextProviding {
        if state.transcriptionEngine == .local, let localSpeechToText {
            return localSpeechToText
        }
        return speechToText
    }

    private var activeTextCleanup: any TextCleanupProviding {
        if let openRouterClient, state.selectedCleanupModel != AIModelConfiguration.phaseZeroVerified.cleanupModel {
            return OpenRouterTextCleanupService(
                transport: openRouterClient,
                model: state.selectedCleanupModel
            )
        }
        return textCleanup
    }

    func requestAccessibilityPermission() {
        refreshAccessibilityPermission()
    }

    func openAccessibilitySettings() {
        guard accessibility.openSystemSettings() else {
            state.setError(.accessibilitySettingsUnavailable)
            return
        }
        state.clearError()
    }

    func refreshAccessibilityPermission() {
        let permissionStatus = accessibility.permissionStatus
        state.setAccessibilityStatus(permissionStatus)
        updateHotkeyMonitor(for: permissionStatus)
    }

    func requestMicrophonePermission() {
        microphonePermissionTask?.cancel()
        state.setMicrophonePermissionStatus(.checking)
        microphonePermissionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await self.microphonePermission.requestPermission()
            guard !Task.isCancelled else { return }
            self.state.setMicrophonePermissionStatus(status)
            if status == .denied {
                self.state.setError(.microphonePermissionRequired)
            } else if status == .restricted {
                self.state.setError(.microphonePermissionRestricted)
            } else {
                self.state.clearError()
            }
            self.microphonePermissionTask = nil
        }
    }

    func openMicrophoneSettings() {
        guard microphonePermission.openSystemSettings() else {
            state.setError(.microphoneSettingsUnavailable)
            return
        }
        state.clearError()
    }

    func refreshMicrophonePermission() {
        state.setMicrophonePermissionStatus(microphonePermission.status)
    }

    func testPaste() {
        guard state.isEnabled, pipelineTask == nil else { return }
        guard accessibility.permissionStatus == .granted else {
            state.setAccessibilityStatus(.required)
            state.setError(.accessibilityPermissionRequired)
            return
        }

        pasteTask?.cancel()
        pasteGeneration += 1
        let generation = pasteGeneration
        state.setTestPasteStatus(.armed)
        state.clearError()

        let text = state.configuration.testPasteText
        let delay = state.configuration.testPasteDelay
        pasteTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, self.state.isEnabled, !Task.isCancelled else { return }

            let target = self.accessibility.captureTarget()
            await self.performPaste(
                text,
                originatingTarget: target,
                seedCache: true,
                isPasteLast: false
            )
            if self.pasteGeneration == generation {
                self.pasteTask = nil
            }
        }
    }

    func saveAPIKey(_ key: String) {
        replaceKeychainTask { [weak self, apiKeyStore] in
            do {
                try await apiKeyStore.save(key)
                guard !Task.isCancelled else { return }
                self?.state.setAPIKeyStatus(try await apiKeyStore.status())
                self?.state.clearError()
            } catch APIKeyStoreError.invalidKey {
                self?.state.setError(.apiKeyInvalid)
            } catch {
                self?.state.setError(.apiKeySaveFailed)
            }
        }
    }

    func removeAPIKey() {
        replaceKeychainTask { [weak self, apiKeyStore] in
            do {
                try await apiKeyStore.remove()
                guard !Task.isCancelled else { return }
                self?.state.setAPIKeyStatus(try await apiKeyStore.status())
                self?.state.clearError()
            } catch {
                self?.state.setError(.apiKeyRemovalFailed)
            }
        }
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            try launchAtLoginService.setEnabled(isEnabled)
            state.setLaunchAtLoginStatus(launchAtLoginService.status)
            state.clearError()
        } catch {
            state.setLaunchAtLoginStatus(launchAtLoginService.status)
            state.setError(.launchAtLoginUpdateFailed)
        }
    }

    func openLoginItemsSettings() {
        launchAtLoginService.openSystemSettings()
    }

    func previewHUD() {
        hud.showPreview(for: state.configuration.hudPreviewDuration)
    }

    func startTestRecording() {
        guard pipelineTask == nil else { return }
        startTestRecording(originatingTarget: nil)
    }

    private func pushToTalkPressed() {
        guard state.isEnabled,
              pipelineTask == nil,
              state.cleanupTestStatus != .cleaning,
              state.testPasteStatus != .armed else { return }
        switch state.audioTestStatus {
        case .idle, .transcribed:
            break
        default:
            return
        }

        let target = accessibility.captureTarget()
        guard target.secureFieldStatus != .secure else {
            state.setError(.secureFieldRefused)
            hud.showFeedback(.secureFieldRefused)
            return
        }
        startTestRecording(originatingTarget: target)
    }

    private func pushToTalkReleased() {
        switch state.audioTestStatus {
        case .starting:
            cancelAudioTest()
        case .recording:
            stopActiveRecording()
        default:
            break
        }
    }

    private func startTestRecording(originatingTarget: PasteTarget?) {
        guard state.isEnabled else { return }
        switch microphonePermission.status {
        case .granted:
            break
        case .restricted:
            state.setMicrophonePermissionStatus(.restricted)
            state.setError(.microphonePermissionRestricted)
            return
        default:
            state.setMicrophonePermissionStatus(microphonePermission.status)
            state.setError(.microphonePermissionRequired)
            return
        }

        guard !state.audioTestStatus.isStartingOrRecording,
              state.audioTestStatus != .playing,
              state.audioTestStatus != .transcribing else {
            state.setError(.recordingAlreadyActive)
            return
        }

        clearTestTranscript()
        guard removeCompletedTestRecording() else { return }
        recordingOriginatingTarget = originatingTarget
        audioGeneration += 1
        let generation = audioGeneration
        audioTask?.cancel()
        audioPlayback.stop()
        state.setAudioTestStatus(.starting)
        state.setStatus(.idle)
        state.clearError()

        audioTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.audioPlayback.playStartCue()
                try Task.checkCancellation()
                guard self.audioGeneration == generation, self.state.isEnabled else { return }

                try self.audioRecorder.start()
                self.state.setAudioTestStatus(.recording(elapsedSeconds: 0))
                self.state.setStatus(.recording)
                self.hud.showRecording()
                self.startElapsedAudioUpdates(generation: generation)
            } catch is CancellationError {
                if self.audioGeneration == generation {
                    self.state.setAudioTestStatus(.idle)
                    self.state.setStatus(.idle)
                    self.recordingOriginatingTarget = nil
                }
            } catch let error as AudioRecordingError {
                self.handleAudioRecordingError(error)
            } catch {
                self.state.setAudioTestStatus(.idle)
                self.recordingOriginatingTarget = nil
                self.state.setError(.audioPlaybackFailed)
            }

            if self.audioGeneration == generation {
                self.audioTask = nil
            }
        }
    }

    func stopTestRecording() {
        stopActiveRecording()
    }

    private func stopActiveRecording() {
        guard audioRecorder.isRecording else {
            state.setError(.noActiveRecording)
            return
        }

        audioGeneration += 1
        let generation = audioGeneration
        elapsedAudioTask?.cancel()
        elapsedAudioTask = nil
        hud.hide()

        do {
            let recording = try audioRecorder.stop()
            guard recording.duration >= SystemAudioRecordingService.minimumDuration else {
                discardBriefRecording(recording, generation: generation)
                return
            }
            guard let target = recordingOriginatingTarget else {
                retainCompletedTestRecording(recording)
                playStopCue(generation: generation)
                return
            }
            recordingOriginatingTarget = nil
            startProductionPipeline(
                recording: recording,
                originatingTarget: target
            )
        } catch let error as AudioRecordingError {
            handleAudioRecordingError(error)
        } catch {
            state.setAudioTestStatus(.idle)
            recordingOriginatingTarget = nil
            state.setError(.recordingEncodingFailed)
        }
    }

    /// Handles a recording shorter than `SystemAudioRecordingService.minimumDuration`:
    /// an accidental or near-instant chord tap with essentially no speech.
    /// Sending audio this short to the STT model reliably produces filler
    /// hallucinations (e.g. "Thank you" for silence), so it is discarded
    /// before transcription — no paste, no error, no HUD feedback, just a
    /// quiet return to idle, matching the deliberate-cancellation path.
    private func discardBriefRecording(_ recording: RecordedAudioFile, generation: Int) {
        do {
            try audioRecorder.delete(recording)
        } catch {
            state.setWarning(.temporaryAudioCleanupFailed)
        }
        recordingOriginatingTarget = nil
        if audioGeneration == generation {
            state.setAudioTestStatus(.idle)
        }
        state.setStatus(.idle)
    }

    func cancelTestRecording() {
        cancelAudioTest()
    }

    func playAndDeleteTestRecording() {
        guard let recording = testRecording else {
            state.setError(.noActiveRecording)
            return
        }

        audioGeneration += 1
        let generation = audioGeneration
        audioExpirationTask?.cancel()
        audioExpirationTask = nil
        state.setAudioTestStatus(.playing)
        state.setStatus(.completed)
        state.clearError()

        audioTask?.cancel()
        audioTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var playbackFailed = false
            do {
                try await self.audioPlayback.playPreview(at: recording.url)
            } catch is CancellationError {
                return
            } catch {
                playbackFailed = true
            }

            guard self.audioGeneration == generation else { return }
            do {
                try self.audioRecorder.delete(recording)
                self.testRecording = nil
                self.recordingOriginatingTarget = nil
                self.state.setAudioTestStatus(.idle)
                if playbackFailed {
                    self.state.setError(.audioPlaybackFailed)
                } else {
                    self.state.setStatus(.idle)
                    self.state.clearError()
                }
            } catch {
                self.state.setAudioTestStatus(
                    .ready(durationSeconds: Int(recording.duration.rounded()))
                )
                self.state.setError(.temporaryAudioCleanupFailed)
            }
            self.audioTask = nil
        }
    }

    func deleteTestRecording() {
        guard testRecording != nil else { return }
        _ = removeCompletedTestRecording()
    }

    func transcribeAndDeleteTestRecording() {
        guard pipelineTask == nil else { return }
        guard let recording = testRecording else {
            state.setError(.noActiveRecording)
            return
        }

        clearTestTranscript()
        audioGeneration += 1
        let generation = audioGeneration
        audioExpirationTask?.cancel()
        audioExpirationTask = nil
        audioPlayback.stop()
        state.setAudioTestStatus(.transcribing)
        state.setStatus(.transcribing)
        state.clearError()

        audioTask?.cancel()
        audioTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let transcription = try await self.activeSpeechToText.transcribe(recording)
                try Task.checkCancellation()
                guard self.audioGeneration == generation else { return }

                do {
                    try self.audioRecorder.delete(recording)
                    self.testRecording = nil
                    self.recordingOriginatingTarget = nil
                } catch {
                    self.state.setAudioTestStatus(
                        .ready(durationSeconds: max(1, Int(recording.duration.rounded())))
                    )
                    self.state.setTestTranscript(transcription.text)
                    self.state.setAudioTranscriptionTestMetadata(
                        AudioTranscriptionTestMetadata(transcription)
                    )
                    self.scheduleTestTranscriptExpiration()
                    self.state.setError(.temporaryAudioCleanupFailed)
                    self.audioTask = nil
                    return
                }

                self.state.setTestTranscript(transcription.text)
                self.state.setAudioTranscriptionTestMetadata(
                    AudioTranscriptionTestMetadata(transcription)
                )
                self.state.setAudioTestStatus(
                    .transcribed(usedFallback: transcription.usedFallback)
                )
                self.state.setStatus(transcription.usedFallback ? .warning : .completed)
                self.state.clearError()
                self.scheduleTestTranscriptExpiration()
            } catch is CancellationError {
                return
            } catch let error as SpeechToTextError {
                guard self.audioGeneration == generation else { return }
                if self.deleteAfterTranscription(recording) {
                    self.state.setError(.transcriptionFailed(error))
                }
            } catch {
                guard self.audioGeneration == generation else { return }
                if self.deleteAfterTranscription(recording) {
                    self.state.setError(.transcriptionFailed(.transport(.networkFailure)))
                }
            }

            if self.audioGeneration == generation {
                self.audioTask = nil
            }
        }
    }

    func clearTestTranscript() {
        transcriptExpirationTask?.cancel()
        transcriptExpirationTask = nil
        state.setTestTranscript(nil)
        state.setAudioTranscriptionTestMetadata(nil)
        if case .transcribed = state.audioTestStatus {
            state.setAudioTestStatus(.idle)
            state.setStatus(.idle)
        }
    }

    func closeSettingsValidation() {
        if state.audioTestStatus == .transcribing {
            cancelAudioTest()
        } else {
            clearTestTranscript()
        }
        cancelCleanupTest(clearInput: true)
    }

    func setCleanupTestInput(_ input: String) {
        let hadCleanupState = state.cleanupTestStatus != .idle
        cleanupGeneration += 1
        cleanupTask?.cancel()
        cleanupTask = nil
        cleanupExpirationTask?.cancel()
        cleanupExpirationTask = nil
        state.setCleanupTestInput(input)
        state.setCleanupTestOutput(nil)
        state.setCleanupTestMetadata(nil)
        state.setCleanupTestStatus(.idle)
        if hadCleanupState {
            resetOverallStatusAfterCleanupIfPossible()
        }
    }

    func loadCleanupTestFixture(_ fixture: CleanupTestFixture) {
        setCleanupTestInput(fixture.text)
    }

    func runCleanupTest() {
        guard state.isEnabled,
              pipelineTask == nil,
              state.cleanupTestStatus != .cleaning else { return }
        let rawText = state.cleanupTestInput
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.setError(.cleanupFailed(.invalidInput))
            return
        }

        cleanupGeneration += 1
        let generation = cleanupGeneration
        cleanupTask?.cancel()
        cleanupExpirationTask?.cancel()
        cleanupExpirationTask = nil
        state.setCleanupTestOutput(nil)
        state.setCleanupTestMetadata(nil)
        state.setCleanupTestStatus(.cleaning)
        state.setStatus(.cleaning)
        state.clearError()

        cleanupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let context = CleanupContext(
                    targetAppName: nil,
                    targetBundleID: nil,
                    customVocabulary: self.state.customVocabulary
                )
                let result = try await self.activeTextCleanup.clean(rawText, context: context)
                try Task.checkCancellation()
                guard self.cleanupGeneration == generation else { return }
                self.state.setCleanupTestOutput(result.text)
                self.state.setCleanupTestMetadata(CleanupTestMetadata(result))
                self.state.setCleanupTestStatus(.cleaned)
                self.state.setStatus(.completed)
                self.state.clearError()
                self.scheduleCleanupTestExpiration()
            } catch is CancellationError {
                return
            } catch let error as TextCleanupError {
                guard self.cleanupGeneration == generation,
                      error != .transport(.cancelled),
                      !Task.isCancelled else { return }
                self.useRawCleanupFallback(rawText, error: error)
            } catch {
                guard self.cleanupGeneration == generation,
                      !Task.isCancelled else { return }
                self.useRawCleanupFallback(
                    rawText,
                    error: .transport(.networkFailure)
                )
            }

            if self.cleanupGeneration == generation {
                self.cleanupTask = nil
            }
        }
    }

    func clearCleanupTest() {
        cancelCleanupTest(clearInput: true)
    }

    func prepareForQuit() {
        keychainTask?.cancel()
        microphonePermissionTask?.cancel()
        temporaryAudioMaintenanceTask?.cancel()
        cancelProductionPipeline()
        cancelAudioTest()
        cancelCleanupTest(clearInput: true)
        pasteGeneration += 1
        pasteTask?.cancel()
        pasteTask = nil
        hotkeyMonitor.stop()
        state.setHotkeyMonitorStatus(.stopped)
        lastDictationCache.clear()
        hud.hide()
    }

    func quit() {
        prepareForQuit()
        NSApplication.shared.terminate(nil)
    }

    private func refreshAPIKeyStatus() {
        replaceKeychainTask { [weak self, apiKeyStore] in
            do {
                let status = try await apiKeyStore.status()
                guard !Task.isCancelled else { return }
                self?.state.setAPIKeyStatus(status)
                self?.state.clearError()
            } catch {
                self?.state.setAPIKeyStatus(.unavailable)
                self?.state.setError(.apiKeyStatusUnavailable)
            }
        }
    }

    private func pasteLastDictation() {
        guard state.isEnabled else { return }
        guard let text = lastDictationCache.value() else {
            hud.showFeedback(.pasteLastUnavailable)
            return
        }

        let target = accessibility.captureTarget()
        pasteTask?.cancel()
        pasteGeneration += 1
        let generation = pasteGeneration
        pasteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performPaste(
                text,
                originatingTarget: target,
                seedCache: false,
                isPasteLast: true
            )
            if self.pasteGeneration == generation {
                self.pasteTask = nil
            }
        }
    }

    private func performPaste(
        _ text: String,
        originatingTarget: PasteTarget,
        seedCache: Bool,
        isPasteLast: Bool
    ) async {
        do {
            let result = try await pasteService.paste(
                text,
                originatingTarget: originatingTarget
            )
            guard !Task.isCancelled else { return }

            if seedCache {
                lastDictationCache.store(text)
            }

            switch result {
            case let .pasted(secureFieldStatusUnknown):
                state.setTestPasteStatus(
                    secureFieldStatusUnknown ? .pastedWithUnknownSecurity : .pasted
                )
                if isPasteLast {
                    hud.showFeedback(.pasteLastSucceeded)
                }
            case .copiedBecauseTargetChanged:
                state.setTestPasteStatus(.copiedBecauseFocusChanged)
                hud.showFeedback(.copiedBecauseFocusChanged)
            }
            state.clearError()
        } catch let error as TextPasteError {
            if seedCache, error == .eventCreationFailed {
                lastDictationCache.store(text)
            }
            if !isPasteLast {
                state.setTestPasteStatus(.failed)
            }
            state.setError(appError(for: error))
        } catch is CancellationError {
            return
        } catch {
            if !isPasteLast {
                state.setTestPasteStatus(.failed)
            }
            state.setError(.pasteFailed)
        }
    }

    private func appError(for error: TextPasteError) -> AppShellError {
        switch error {
        case .emptyText: .pasteFailed
        case .accessibilityPermissionRequired: .accessibilityPermissionRequired
        case .targetUnavailable: .pasteTargetUnavailable
        case .secureField: .secureFieldRefused
        case .clipboardWriteFailed: .clipboardWriteFailed
        case .eventCreationFailed: .pasteEventCreationFailed
        }
    }

    private func startProductionPipeline(
        recording: RecordedAudioFile,
        originatingTarget: PasteTarget
    ) {
        pipelineGeneration += 1
        let generation = pipelineGeneration
        pipelineTask?.cancel()
        completionResetTask?.cancel()
        completionResetTask = nil
        state.setAudioTestStatus(.idle)
        state.setStatus(.encoding)
        state.clearError()
        productionRecording = (generation, recording)
        hud.showProcessing()
        recordMetricsStarted(audioSeconds: recording.duration)

        pipelineTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runProductionPipeline(
                recording: recording,
                originatingTarget: originatingTarget,
                generation: generation
            )
        }
    }

    private func runProductionPipeline(
        recording: RecordedAudioFile,
        originatingTarget: PasteTarget,
        generation: Int
    ) async {
        let clock = ContinuousClock()
        let totalStart = clock.now
        var transcriptionDuration: Duration?
        var cleanupDuration: Duration?
        var pasteDuration: Duration?
        var audioNeedsDeletion = true
        var metricOutcome: DictationMetricOutcome?
        var metricIssue: DictationIssueCategory?
        var transcriptionCost: Double?
        var cleanupCost: Double?
        var usedRawCleanupFallback = false
        var cleanupFailureForMetrics: TextCleanupError?

        var transcriptionModelForMetrics: String?
        var cleanupModelForMetrics: String? = state.selectedCleanupModel
        var transcriptWordCountForMetrics: Int?

        defer {
            hud.finishProcessing()
            if audioNeedsDeletion,
               !deleteProductionRecording(recording, generation: generation) {
                state.setWarning(.temporaryAudioCleanupFailed)
                hud.showFeedback(.temporaryAudioCleanupFailed)
            }
            let timing = DictationPipelineTiming(
                transcription: transcriptionDuration,
                cleanup: cleanupDuration,
                paste: pasteDuration,
                total: totalStart.duration(to: clock.now)
            )
            pipelineTimingHandler(timing)
            if let metricOutcome {
                recordMetricsCompletion(
                    DictationMetricEvent(
                        outcome: metricOutcome,
                        transcriptionLatency: transcriptionDuration,
                        cleanupLatency: cleanupDuration,
                        totalLatency: timing.total,
                        transcriptionCost: transcriptionCost,
                        cleanupCost: cleanupCost,
                        transcriptionModel: transcriptionModelForMetrics,
                        cleanupModel: cleanupModelForMetrics,
                        audioDurationSeconds: recording.duration,
                        transcriptWordCount: transcriptWordCountForMetrics,
                        usedRawCleanupFallback: usedRawCleanupFallback,
                        issueCategory: metricIssue,
                        cleanupFailureReason: cleanupFailureForMetrics.map(CleanupFailureReason.init(cleanupError:))
                    )
                )
            }
            if pipelineGeneration == generation {
                pipelineTask = nil
            }
        }

        var cueFailed = false
        do {
            try await audioPlayback.playStopCue()
            try Task.checkCancellation()
        } catch is CancellationError {
            finishCancelledPipeline(generation: generation)
            return
        } catch {
            guard !Task.isCancelled else {
                finishCancelledPipeline(generation: generation)
                return
            }
            cueFailed = true
            hud.showFeedback(.recordingCueFailed)
        }

        state.setStatus(.transcribing)
        let transcriptionStart = clock.now
        let transcription: SpeechTranscription
        do {
            transcription = try await activeSpeechToText.transcribe(recording)
            transcriptionDuration = transcriptionStart.duration(to: clock.now)
            transcriptionModelForMetrics = transcription.model
            let words = transcription.text.split(whereSeparator: { character in
                !character.isLetter && !character.isNumber
            }).count
            transcriptWordCountForMetrics = words
            try Task.checkCancellation()
        } catch is CancellationError {
            transcriptionDuration = transcriptionStart.duration(to: clock.now)
            finishCancelledPipeline(generation: generation)
            return
        } catch let error as SpeechToTextError {
            transcriptionDuration = transcriptionStart.duration(to: clock.now)
            guard error != .transport(.cancelled), !Task.isCancelled else {
                finishCancelledPipeline(generation: generation)
                return
            }
            let deleted = deleteProductionRecording(recording, generation: generation)
            audioNeedsDeletion = false
            state.setError(
                deleted
                    ? .transcriptionFailed(error)
                    : .transcriptionAndAudioCleanupFailed(error)
            )
            metricOutcome = .failure
            metricIssue = deleted
                ? .transcriptionFailure
                : .temporaryAudioCleanupFailure
            if !deleted {
                hud.showFeedback(.temporaryAudioCleanupFailed)
            }
            return
        } catch {
            transcriptionDuration = transcriptionStart.duration(to: clock.now)
            guard !Task.isCancelled else {
                finishCancelledPipeline(generation: generation)
                return
            }
            let failure = SpeechToTextError.transport(.networkFailure)
            let deleted = deleteProductionRecording(recording, generation: generation)
            audioNeedsDeletion = false
            state.setError(
                deleted
                    ? .transcriptionFailed(failure)
                    : .transcriptionAndAudioCleanupFailed(failure)
            )
            metricOutcome = .failure
            metricIssue = deleted
                ? .transcriptionFailure
                : .temporaryAudioCleanupFailure
            if !deleted {
                hud.showFeedback(.temporaryAudioCleanupFailed)
            }
            return
        }

        if transcription.usedFallback {
            hud.showFeedback(.transcriptionFallbackUsed)
        }
        transcriptionCost = transcription.usage?.cost

        let audioDeleted = deleteProductionRecording(recording, generation: generation)
        audioNeedsDeletion = false
        if !audioDeleted {
            hud.showFeedback(.temporaryAudioCleanupFailed)
        }

        state.setStatus(.cleaning)
        let cleanupStart = clock.now
        var finalText = transcription.text
        var cleanupFailure: TextCleanupError?
        do {
            let context = CleanupContext(
                targetAppName: originatingTarget.localizedName,
                targetBundleID: originatingTarget.bundleIdentifier,
                customVocabulary: state.customVocabulary
            )
            let result = try await activeTextCleanup.clean(transcription.text, context: context)
            cleanupDuration = cleanupStart.duration(to: clock.now)
            cleanupModelForMetrics = result.model
            try Task.checkCancellation()
            finalText = result.text
            cleanupCost = result.usage?.cost
        } catch is CancellationError {
            cleanupDuration = cleanupStart.duration(to: clock.now)
            finishCancelledPipeline(generation: generation)
            return
        } catch let error as TextCleanupError {
            cleanupDuration = cleanupStart.duration(to: clock.now)
            guard error != .transport(.cancelled), !Task.isCancelled else {
                finishCancelledPipeline(generation: generation)
                return
            }
            cleanupFailure = error
            cleanupFailureForMetrics = error
            usedRawCleanupFallback = true
            hud.showFeedback(.cleanupRawFallback)
            if case let .suspiciousOutput(failure, candidateOutput, metrics) = error {
                cleanupDiagnosticStore.record(
                    model: cleanupModelForMetrics ?? state.selectedCleanupModel,
                    input: transcription.text,
                    candidateOutput: candidateOutput,
                    failure: failure,
                    inputWordCount: metrics.inputWordCount,
                    outputWordCount: metrics.outputWordCount,
                    novelWordCount: metrics.novelWordCount,
                    novelWordRatio: metrics.novelWordRatio,
                    expansionRatio: metrics.expansionRatio
                )
                refreshCleanupDiagnostics()
            }
        } catch {
            cleanupDuration = cleanupStart.duration(to: clock.now)
            guard !Task.isCancelled else {
                finishCancelledPipeline(generation: generation)
                return
            }
            cleanupFailure = .transport(.networkFailure)
            cleanupFailureForMetrics = .transport(.networkFailure)
            usedRawCleanupFallback = true
            hud.showFeedback(.cleanupRawFallback)
        }

        state.setStatus(.pasting)
        let pasteStart = clock.now
        let pasteOutcome: ProductionPasteOutcome
        do {
            pasteOutcome = try await pasteProductionText(
                finalText,
                originatingTarget: originatingTarget
            )
            pasteDuration = pasteStart.duration(to: clock.now)
        } catch is CancellationError {
            pasteDuration = pasteStart.duration(to: clock.now)
            finishCancelledPipeline(generation: generation)
            return
        } catch let error as TextPasteError {
            pasteDuration = pasteStart.duration(to: clock.now)
            guard !Task.isCancelled else {
                finishCancelledPipeline(generation: generation)
                return
            }
            state.setError(appError(for: error))
            metricOutcome = error == .eventCreationFailed ? .success : .failure
            metricIssue = audioDeleted ? .pasteFailure : .temporaryAudioCleanupFailure
            return
        } catch {
            pasteDuration = pasteStart.duration(to: clock.now)
            guard !Task.isCancelled else {
                finishCancelledPipeline(generation: generation)
                return
            }
            state.setError(.pasteFailed)
            metricOutcome = .failure
            metricIssue = audioDeleted ? .pasteFailure : .temporaryAudioCleanupFailure
            return
        }

        if pasteOutcome == .copiedBecauseTargetChanged {
            hud.showFeedback(.copiedBecauseFocusChanged)
        }

        let warning: AppShellError? = if !audioDeleted {
            .temporaryAudioCleanupFailed
        } else if pasteOutcome == .copiedBecauseTargetChanged {
            .focusChangedCopied
        } else if let cleanupFailure {
            .cleanupFailed(cleanupFailure)
        } else if transcription.usedFallback {
            .transcriptionFallbackUsed
        } else if cueFailed {
            .recordingCueFailed
        } else {
            nil
        }

        if let warning {
            state.setWarning(warning)
        } else {
            state.setStatus(.completed)
            state.clearError()
            scheduleCompletedStatusReset(generation: generation)
        }
        metricOutcome = .success
        metricIssue = warning.flatMap(metricIssueCategory(for:))
    }

    private func pasteProductionText(
        _ text: String,
        originatingTarget: PasteTarget
    ) async throws -> ProductionPasteOutcome {
        do {
            let result = try await pasteService.paste(
                text,
                originatingTarget: originatingTarget
            )
            try Task.checkCancellation()
            lastDictationCache.store(text)
            return switch result {
            case .pasted: .pasted
            case .copiedBecauseTargetChanged: .copiedBecauseTargetChanged
            }
        } catch let error as TextPasteError {
            try Task.checkCancellation()
            if error == .eventCreationFailed {
                lastDictationCache.store(text)
            }
            throw error
        }
    }

    private func deleteProductionRecording(
        _ recording: RecordedAudioFile,
        generation: Int
    ) -> Bool {
        guard productionRecording?.generation == generation else { return true }
        defer { productionRecording = nil }
        for _ in 0..<2 {
            do {
                try audioRecorder.delete(recording)
                return true
            } catch {
                continue
            }
        }
        return false
    }

    private func cancelProductionPipeline() {
        let ownedRecording = productionRecording
        pipelineGeneration += 1
        pipelineTask?.cancel()
        pipelineTask = nil
        completionResetTask?.cancel()
        completionResetTask = nil
        if state.status.isProcessing {
            state.setStatus(.idle)
        }
        if let ownedRecording,
           !deleteProductionRecording(
               ownedRecording.file,
               generation: ownedRecording.generation
           ) {
            state.setWarning(.temporaryAudioCleanupFailed)
            hud.showFeedback(.temporaryAudioCleanupFailed)
        }
    }

    private func finishCancelledPipeline(generation: Int) {
        guard pipelineGeneration == generation else { return }
        state.setStatus(.idle)
    }

    private func scheduleCompletedStatusReset(generation: Int) {
        completionResetTask?.cancel()
        completionResetTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard let self,
                  self.pipelineGeneration == generation,
                  self.state.status == .completed else { return }
            self.state.setStatus(.idle)
            self.completionResetTask = nil
        }
    }

    private func startElapsedAudioUpdates(generation: Int) {
        elapsedAudioTask?.cancel()
        elapsedAudioTask = Task { @MainActor [weak self] in
            while let self,
                  !Task.isCancelled,
                  self.audioGeneration == generation,
                  self.audioRecorder.isRecording {
                let seconds = Int(self.audioRecorder.elapsedTime.rounded(.down))
                self.state.setAudioTestStatus(.recording(elapsedSeconds: seconds))
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
            }
        }
    }

    private func retainCompletedTestRecording(_ recording: RecordedAudioFile) {
        testRecording = recording
        let duration = max(1, Int(recording.duration.rounded()))
        state.setAudioTestStatus(.ready(durationSeconds: duration))
        state.setStatus(.completed)
        state.clearError()
        scheduleTestRecordingExpiration()
    }

    private func playStopCue(generation: Int) {
        audioTask?.cancel()
        audioTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.audioPlayback.playStopCue()
            } catch is CancellationError {
                return
            } catch {
                if self.audioGeneration == generation {
                    self.state.setError(.audioPlaybackFailed)
                }
            }
            if self.audioGeneration == generation {
                self.audioTask = nil
            }
        }
    }

    private func scheduleTestRecordingExpiration() {
        audioExpirationTask?.cancel()
        let generation = audioGeneration
        let lifetime = state.configuration.testRecordingLifetime
        audioExpirationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: lifetime)
            } catch {
                return
            }
            guard let self, self.audioGeneration == generation else { return }
            _ = self.removeCompletedTestRecording()
            self.audioExpirationTask = nil
        }
    }

    private func scheduleTestTranscriptExpiration() {
        transcriptExpirationTask?.cancel()
        let generation = audioGeneration
        let lifetime = state.configuration.testTranscriptLifetime
        transcriptExpirationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: lifetime)
            } catch {
                return
            }
            guard let self, self.audioGeneration == generation else { return }
            self.clearTestTranscript()
        }
    }

    private func scheduleCleanupTestExpiration() {
        cleanupExpirationTask?.cancel()
        let generation = cleanupGeneration
        let lifetime = state.configuration.testTranscriptLifetime
        cleanupExpirationTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: lifetime)
            } catch {
                return
            }
            guard let self, self.cleanupGeneration == generation else { return }
            self.cancelCleanupTest(clearInput: true)
        }
    }

    private func useRawCleanupFallback(_ rawText: String, error: TextCleanupError) {
        state.setCleanupTestOutput(rawText)
        state.setCleanupTestMetadata(nil)
        state.setCleanupTestStatus(.rawFallback)
        state.setWarning(.cleanupFailed(error))
        if case let .suspiciousOutput(failure, candidateOutput, metrics) = error {
            cleanupDiagnosticStore.record(
                model: state.selectedCleanupModel,
                input: rawText,
                candidateOutput: candidateOutput,
                failure: failure,
                inputWordCount: metrics.inputWordCount,
                outputWordCount: metrics.outputWordCount,
                novelWordCount: metrics.novelWordCount,
                novelWordRatio: metrics.novelWordRatio,
                expansionRatio: metrics.expansionRatio
            )
            refreshCleanupDiagnostics()
        }
        scheduleCleanupTestExpiration()
    }

    private func cancelCleanupTest(clearInput: Bool) {
        let hadCleanupState = state.cleanupTestStatus != .idle
        cleanupGeneration += 1
        cleanupTask?.cancel()
        cleanupTask = nil
        cleanupExpirationTask?.cancel()
        cleanupExpirationTask = nil
        if clearInput {
            state.setCleanupTestInput("")
        }
        state.setCleanupTestOutput(nil)
        state.setCleanupTestMetadata(nil)
        state.setCleanupTestStatus(.idle)
        state.clearCleanupIssue()
        if hadCleanupState {
            resetOverallStatusAfterCleanupIfPossible()
        }
    }

    private func resetOverallStatusAfterCleanupIfPossible() {
        guard pipelineTask == nil,
              !state.audioTestStatus.isStartingOrRecording,
              state.audioTestStatus != .transcribing,
              state.audioTestStatus != .playing else { return }
        state.setStatus(.idle)
    }

    private func deleteAfterTranscription(_ recording: RecordedAudioFile) -> Bool {
        do {
            try audioRecorder.delete(recording)
            testRecording = nil
            recordingOriginatingTarget = nil
            state.setAudioTestStatus(.idle)
            state.setStatus(.idle)
            return true
        } catch {
            state.setAudioTestStatus(
                .ready(durationSeconds: max(1, Int(recording.duration.rounded())))
            )
            state.setError(.temporaryAudioCleanupFailed)
            return false
        }
    }

    private func removeCompletedTestRecording() -> Bool {
        audioExpirationTask?.cancel()
        audioExpirationTask = nil
        guard let testRecording else {
            state.setAudioTestStatus(.idle)
            return true
        }

        do {
            try audioRecorder.delete(testRecording)
            self.testRecording = nil
            recordingOriginatingTarget = nil
            state.setAudioTestStatus(.idle)
            state.setStatus(.idle)
            state.clearError()
            return true
        } catch {
            state.setError(.temporaryAudioCleanupFailed)
            return false
        }
    }

    private func cancelAudioTest() {
        audioGeneration += 1
        audioTask?.cancel()
        audioTask = nil
        elapsedAudioTask?.cancel()
        elapsedAudioTask = nil
        audioExpirationTask?.cancel()
        audioExpirationTask = nil
        transcriptExpirationTask?.cancel()
        transcriptExpirationTask = nil
        state.setTestTranscript(nil)
        state.setAudioTranscriptionTestMetadata(nil)
        audioPlayback.stop()
        hud.hide()

        var cleanupFailed = false
        do {
            try audioRecorder.cancel()
        } catch {
            cleanupFailed = true
        }
        if let testRecording {
            do {
                try audioRecorder.delete(testRecording)
                self.testRecording = nil
                recordingOriginatingTarget = nil
            } catch {
                cleanupFailed = true
            }
        }
        recordingOriginatingTarget = nil

        if cleanupFailed, let testRecording {
            state.setAudioTestStatus(
                .ready(durationSeconds: max(1, Int(testRecording.duration.rounded())))
            )
        } else {
            state.setAudioTestStatus(.idle)
        }
        state.setStatus(.idle)
        if cleanupFailed {
            state.setError(.temporaryAudioCleanupFailed)
        }
    }

    private func handleMaximumDurationResult(
        _ result: Result<RecordedAudioFile, AudioRecordingError>
    ) {
        guard state.audioTestStatus.isStartingOrRecording else {
            if case let .success(recording) = result {
                do {
                    try audioRecorder.delete(recording)
                } catch {
                    state.setError(.temporaryAudioCleanupFailed)
                }
            }
            return
        }

        audioGeneration += 1
        let generation = audioGeneration
        elapsedAudioTask?.cancel()
        elapsedAudioTask = nil
        hud.hide()

        switch result {
        case let .success(recording):
            hud.showFeedback(.recordingLimitReached)
            if let target = recordingOriginatingTarget {
                recordingOriginatingTarget = nil
                startProductionPipeline(
                    recording: recording,
                    originatingTarget: target
                )
            } else {
                retainCompletedTestRecording(recording)
                playStopCue(generation: generation)
            }
        case let .failure(error):
            handleAudioRecordingError(error)
        }
    }

    private func handleAudioRecordingError(_ error: AudioRecordingError) {
        elapsedAudioTask?.cancel()
        elapsedAudioTask = nil
        hud.hide()
        state.setAudioTestStatus(.idle)

        let appError: AppShellError = switch error {
        case .microphonePermissionRequired: .microphonePermissionRequired
        case .alreadyRecording: .recordingAlreadyActive
        case .noActiveRecording: .noActiveRecording
        case .temporaryFileCleanupFailed: .temporaryAudioCleanupFailed
        case .encodingFailed, .invalidRecording: .recordingEncodingFailed
        case .temporaryDirectoryCreationFailed,
             .recorderCreationFailed,
             .recordingStartFailed: .recordingStartFailed
        }
        state.setError(appError)
        recordingOriginatingTarget = nil
    }

    private func installLifecycleObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let workspaceNotifications = [
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
        ]
        lifecycleObservers += workspaceNotifications.map { notificationName in
            workspaceCenter.addObserver(
                forName: notificationName,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.cancelProductionPipeline()
                    self?.cancelAudioTest()
                    self?.cancelCleanupTest(clearInput: true)
                    self?.lastDictationCache.clear()
                }
            }
        }

        lifecycleObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.prepareForQuit()
                }
            }
        )
    }

    private func updateHotkeyMonitor(for permissionStatus: AccessibilityPermissionStatus) {
        guard state.isEnabled, permissionStatus == .granted else {
            hotkeyMonitor.stop()
            state.setHotkeyMonitorStatus(.stopped)
            return
        }

        do {
            try hotkeyMonitor.start()
            state.setHotkeyMonitorStatus(.running)
        } catch HotkeyMonitorError.accessibilityPermissionRequired {
            state.setAccessibilityStatus(.required)
            state.setHotkeyMonitorStatus(.unavailable)
        } catch {
            state.setHotkeyMonitorStatus(.unavailable)
            state.setError(.hotkeyMonitorFailed)
        }
    }

    private func refreshUsageMetrics() {
        state.setUsageMetrics(metricsStore.snapshot, status: metricsStore.status)
    }

    private func recordMetricsStarted(audioSeconds: Double) {
        do {
            let snapshot = try metricsStore.recordStarted(audioSeconds: audioSeconds)
            state.setUsageMetrics(snapshot, status: metricsStore.status)
        } catch {
            state.setUsageMetrics(metricsStore.snapshot, status: .persistenceFailed)
        }
    }

    private func recordMetricsCompletion(_ event: DictationMetricEvent) {
        do {
            let snapshot = try metricsStore.recordCompletion(event)
            state.setUsageMetrics(snapshot, status: metricsStore.status)
        } catch {
            state.setUsageMetrics(metricsStore.snapshot, status: .persistenceFailed)
        }
    }

    private func metricIssueCategory(for warning: AppShellError) -> DictationIssueCategory? {
        switch warning {
        case .temporaryAudioCleanupFailed, .transcriptionAndAudioCleanupFailed:
            .temporaryAudioCleanupFailure
        case .focusChangedCopied:
            .focusChanged
        case .cleanupFailed:
            .cleanupRawFallback
        case .transcriptionFallbackUsed:
            .transcriptionFallback
        case .recordingCueFailed:
            .recordingCueFailure
        default:
            nil
        }
    }

    private func sweepStaleTemporaryAudio() {
        temporaryAudioMaintenanceTask?.cancel()
        state.setTemporaryAudioMaintenanceStatus(.pending)
        let cutoff = Date().addingTimeInterval(
            -SystemTemporaryAudioMaintenance.v0StaleRecordingAge
        )
        temporaryAudioMaintenanceTask = Task { @MainActor [weak self, temporaryAudioMaintenance] in
            guard let self else { return }
            do {
                let removedCount = try await temporaryAudioMaintenance
                    .sweepStaleRecordings(olderThan: cutoff)
                guard !Task.isCancelled else { return }
                self.state.setTemporaryAudioMaintenanceStatus(
                    removedCount == 0 ? .clean : .removed(removedCount)
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.state.setTemporaryAudioMaintenanceStatus(.failed)
            }
            self.temporaryAudioMaintenanceTask = nil
        }
    }

    private func replaceKeychainTask(
        operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        keychainTask?.cancel()
        keychainTask = Task(operation: operation)
    }
}
