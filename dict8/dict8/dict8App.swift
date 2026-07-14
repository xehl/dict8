import SwiftUI

@main
struct Dict8App: App {
    @StateObject private var appState: AppState
    private let coordinator: AppCoordinator

    init() {
        let state = AppState()
        let coordinator = AppCoordinator(
            state: state,
            apiKeyStore: SystemAPIKeyStore(),
            launchAtLoginService: SystemLaunchAtLoginService(),
            hud: RecordingHUDController()
        )
        _appState = StateObject(wrappedValue: state)
        self.coordinator = coordinator
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
