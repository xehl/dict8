import SwiftUI

@main
struct Dict8App: App {
    @StateObject private var appState: AppState
    private let coordinator: AppCoordinator

    init() {
        let state = AppState()
        let apiKeyStore = SystemAPIKeyStore()
        let accessibility = SystemAccessibilityService()
        let microphonePermission = SystemMicrophonePermissionService()
        let audioRecorder = SystemAudioRecordingService(
            permissionStatus: { microphonePermission.status }
        )
        let pasteService = SystemTextPasteService(accessibility: accessibility)
        let openRouter = OpenRouterClient(apiKeyStore: apiKeyStore)
        let speechToText = OpenRouterSpeechToTextService(transport: openRouter)
        let textCleanup = OpenRouterTextCleanupService(transport: openRouter)
        let coordinator = AppCoordinator(
            state: state,
            apiKeyStore: apiKeyStore,
            launchAtLoginService: SystemLaunchAtLoginService(),
            accessibility: accessibility,
            microphonePermission: microphonePermission,
            audioRecorder: audioRecorder,
            audioPlayback: SystemAudioPlaybackService(),
            speechToText: speechToText,
            textCleanup: textCleanup,
            pasteService: pasteService,
            lastDictationCache: LastDictationCache(),
            hotkeyMonitor: SystemHotkeyMonitor(),
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
