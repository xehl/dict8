import SwiftUI

@main
struct Dict8App: App {
    @StateObject private var appState: AppState
    private let coordinator: AppCoordinator

    init() {
        let state = AppState()
        let accessibility = SystemAccessibilityService()
        let microphonePermission = SystemMicrophonePermissionService()
        let audioRecorder = SystemAudioRecordingService(
            permissionStatus: { microphonePermission.status }
        )
        let pasteService = SystemTextPasteService(accessibility: accessibility)
        let coordinator = AppCoordinator(
            state: state,
            apiKeyStore: SystemAPIKeyStore(),
            launchAtLoginService: SystemLaunchAtLoginService(),
            accessibility: accessibility,
            microphonePermission: microphonePermission,
            audioRecorder: audioRecorder,
            audioPlayback: SystemAudioPlaybackService(),
            pasteService: pasteService,
            lastDictationCache: LastDictationCache(),
            pasteLastMonitor: SystemPasteLastHotkeyMonitor(),
            hud: RecordingHUDController()
        )
        _appState = StateObject(wrappedValue: state)
        self.coordinator = coordinator
        coordinator.startIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra(
            "dict8",
            systemImage: appState.isEnabled ? "mic.fill" : "mic.slash"
        ) {
            MenuBarView(coordinator: coordinator)
                .environmentObject(appState)
                .onAppear {
                    coordinator.startIfNeeded()
                }
        }

        Settings {
            SettingsView(coordinator: coordinator)
                .environmentObject(appState)
        }
    }
}
