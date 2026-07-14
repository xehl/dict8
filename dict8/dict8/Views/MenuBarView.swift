import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    let coordinator: AppCoordinator

    var body: some View {
        Text(appState.status.displayName)

        Button(appState.isEnabled ? "Disable" : "Enable") {
            coordinator.setEnabled(!appState.isEnabled)
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Quit dict8") {
            coordinator.quit()
        }
        .keyboardShortcut("q")
    }
}
