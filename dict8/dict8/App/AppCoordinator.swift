import AppKit
import Foundation

@MainActor
final class AppCoordinator {
    let state: AppState

    private let apiKeyStore: any APIKeyStoring
    private let launchAtLoginService: any LaunchAtLoginControlling
    private let hud: any RecordingHUDPresenting
    private var keychainTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        state: AppState,
        apiKeyStore: any APIKeyStoring,
        launchAtLoginService: any LaunchAtLoginControlling,
        hud: any RecordingHUDPresenting
    ) {
        self.state = state
        self.apiKeyStore = apiKeyStore
        self.launchAtLoginService = launchAtLoginService
        self.hud = hud
    }

    deinit {
        keychainTask?.cancel()
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshConfiguration()
    }

    func refreshConfiguration() {
        state.setLaunchAtLoginStatus(launchAtLoginService.status)
        refreshAPIKeyStatus()
    }

    func setEnabled(_ isEnabled: Bool) {
        state.setEnabled(isEnabled)
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

    private func replaceKeychainTask(
        operation: @escaping @MainActor @Sendable () async -> Void
    ) {
        keychainTask?.cancel()
        keychainTask = Task(operation: operation)
    }
}
