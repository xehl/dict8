import AppKit
import Foundation

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
    private let pasteService: any TextPasting
    private let lastDictationCache: any LastDictationCaching
    private let pasteLastMonitor: any PasteLastHotkeyMonitoring
    private let hud: any RecordingHUDPresenting
    private var keychainTask: Task<Void, Never>?
    private var pasteTask: Task<Void, Never>?
    private var microphonePermissionTask: Task<Void, Never>?
    private var audioTask: Task<Void, Never>?
    private var elapsedAudioTask: Task<Void, Never>?
    private var audioExpirationTask: Task<Void, Never>?
    private var transcriptExpirationTask: Task<Void, Never>?
    private var testRecording: RecordedAudioFile?
    private var audioGeneration = 0
    private var pasteGeneration = 0
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
        pasteService: any TextPasting,
        lastDictationCache: any LastDictationCaching,
        pasteLastMonitor: any PasteLastHotkeyMonitoring,
        hud: any RecordingHUDPresenting
    ) {
        self.state = state
        self.apiKeyStore = apiKeyStore
        self.launchAtLoginService = launchAtLoginService
        self.accessibility = accessibility
        self.microphonePermission = microphonePermission
        self.audioRecorder = audioRecorder
        self.audioPlayback = audioPlayback
        self.speechToText = speechToText
        self.pasteService = pasteService
        self.lastDictationCache = lastDictationCache
        self.pasteLastMonitor = pasteLastMonitor
        self.hud = hud

        pasteLastMonitor.onPasteLast = { [weak self] in
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
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        installLifecycleObservers()
        refreshConfiguration()
    }

    func refreshConfiguration() {
        state.setLaunchAtLoginStatus(launchAtLoginService.status)
        refreshAccessibilityPermission()
        refreshMicrophonePermission()
        refreshAPIKeyStatus()
    }

    func setEnabled(_ isEnabled: Bool) {
        state.setEnabled(isEnabled)
        state.setTestPasteStatus(.idle)

        if isEnabled {
            refreshAccessibilityPermission()
        } else {
            cancelAudioTest()
            pasteGeneration += 1
            pasteTask?.cancel()
            pasteTask = nil
            pasteLastMonitor.stop()
            lastDictationCache.clear()
        }
    }

    func requestAccessibilityPermission() {
        accessibility.requestPermission()
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
        updatePasteLastMonitor(for: permissionStatus)
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
        guard state.isEnabled else { return }
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
                }
            } catch let error as AudioRecordingError {
                self.handleAudioRecordingError(error)
            } catch {
                self.state.setAudioTestStatus(.idle)
                self.state.setError(.audioPlaybackFailed)
            }

            if self.audioGeneration == generation {
                self.audioTask = nil
            }
        }
    }

    func stopTestRecording() {
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
            retainCompletedTestRecording(recording)
            playStopCue(generation: generation)
        } catch let error as AudioRecordingError {
            handleAudioRecordingError(error)
        } catch {
            state.setAudioTestStatus(.idle)
            state.setError(.recordingEncodingFailed)
        }
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
        audioTask = Task { @MainActor [weak self, speechToText] in
            guard let self else { return }
            do {
                let transcription = try await speechToText.transcribe(recording)
                try Task.checkCancellation()
                guard self.audioGeneration == generation else { return }

                do {
                    try self.audioRecorder.delete(recording)
                    self.testRecording = nil
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
    }

    func prepareForQuit() {
        keychainTask?.cancel()
        microphonePermissionTask?.cancel()
        cancelAudioTest()
        pasteGeneration += 1
        pasteTask?.cancel()
        pasteTask = nil
        pasteLastMonitor.stop()
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

    private func deleteAfterTranscription(_ recording: RecordedAudioFile) -> Bool {
        do {
            try audioRecorder.delete(recording)
            testRecording = nil
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
            } catch {
                cleanupFailed = true
            }
        }

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
            retainCompletedTestRecording(recording)
            hud.showFeedback(.recordingLimitReached)
            playStopCue(generation: generation)
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
                    self?.cancelAudioTest()
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

    private func updatePasteLastMonitor(for permissionStatus: AccessibilityPermissionStatus) {
        guard state.isEnabled, permissionStatus == .granted else {
            pasteLastMonitor.stop()
            return
        }

        do {
            try pasteLastMonitor.start()
        } catch PasteLastHotkeyError.accessibilityPermissionRequired {
            state.setAccessibilityStatus(.required)
        } catch {
            state.setError(.pasteLastMonitorFailed)
        }
    }

    private func replaceKeychainTask(
        operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        keychainTask?.cancel()
        keychainTask = Task(operation: operation)
    }
}
