import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    let state: AppState

    private let apiKeyStore: any APIKeyStoring
    private let launchAtLoginService: any LaunchAtLoginControlling
    private let accessibility: any AccessibilityInspecting
    private let pasteService: any TextPasting
    private let lastDictationCache: any LastDictationCaching
    private let pasteLastMonitor: any PasteLastHotkeyMonitoring
    private let hud: any RecordingHUDPresenting
    private var keychainTask: Task<Void, Never>?
    private var pasteTask: Task<Void, Never>?
    private var pasteGeneration = 0
    private var hasStarted = false

    init(
        state: AppState,
        apiKeyStore: any APIKeyStoring,
        launchAtLoginService: any LaunchAtLoginControlling,
        accessibility: any AccessibilityInspecting,
        pasteService: any TextPasting,
        lastDictationCache: any LastDictationCaching,
        pasteLastMonitor: any PasteLastHotkeyMonitoring,
        hud: any RecordingHUDPresenting
    ) {
        self.state = state
        self.apiKeyStore = apiKeyStore
        self.launchAtLoginService = launchAtLoginService
        self.accessibility = accessibility
        self.pasteService = pasteService
        self.lastDictationCache = lastDictationCache
        self.pasteLastMonitor = pasteLastMonitor
        self.hud = hud

        pasteLastMonitor.onPasteLast = { [weak self] in
            self?.pasteLastDictation()
        }
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshConfiguration()
    }

    func refreshConfiguration() {
        state.setLaunchAtLoginStatus(launchAtLoginService.status)
        refreshAccessibilityPermission()
        refreshAPIKeyStatus()
    }

    func setEnabled(_ isEnabled: Bool) {
        state.setEnabled(isEnabled)
        state.setTestPasteStatus(.idle)

        if isEnabled {
            refreshAccessibilityPermission()
        } else {
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

    func prepareForQuit() {
        keychainTask?.cancel()
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
