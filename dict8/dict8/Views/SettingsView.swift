import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var apiKey = ""

    let coordinator: AppCoordinator

    var body: some View {
        Form {
            Section("General") {
                Toggle(
                    "Enabled",
                    isOn: Binding(
                        get: { appState.isEnabled },
                        set: { isEnabled in
                            coordinator.setEnabled(isEnabled)
                        }
                    )
                )
                LabeledContent("Status", value: appState.status.displayName)
                LabeledContent("Push to talk", value: appState.configuration.hotkeyDisplayName)
            }

            Section("Permissions") {
                LabeledContent(
                    "Accessibility",
                    value: appState.accessibilityStatus.displayName
                )

                HStack {
                    Button("Request Accessibility") {
                        coordinator.requestAccessibilityPermission()
                    }
                    .disabled(appState.accessibilityStatus == .granted)

                    Button("Open Accessibility Settings") {
                        coordinator.openAccessibilitySettings()
                    }

                    Button("Refresh") {
                        coordinator.refreshAccessibilityPermission()
                    }
                }

                Text("Accessibility lets dict8 inspect the focused target and synthesize paste without reading field contents.")
                    .foregroundStyle(.secondary)
            }

            Section("Paste") {
                LabeledContent(
                    "Paste last dictation",
                    value: appState.configuration.pasteLastHotkeyDisplayName
                )
                LabeledContent("Test status", value: appState.testPasteStatus.displayName)

                Button("Paste Test Text in 3 Seconds") {
                    coordinator.testPaste()
                }
                .disabled(
                    !appState.isEnabled
                        || appState.accessibilityStatus != .granted
                        || appState.testPasteStatus == .armed
                )

                Text("After clicking, focus a TextEdit document. A successful test seeds Paste Last for ten minutes.")
                    .foregroundStyle(.secondary)
            }

            Section("OpenRouter") {
                LabeledContent("API key", value: appState.apiKeyStatus.displayName)

                SecureField("OpenRouter API key", text: $apiKey)
                    .textContentType(.password)

                HStack {
                    Button("Save or Replace") {
                        let keyToSave = apiKey
                        apiKey = ""
                        coordinator.saveAPIKey(keyToSave)
                    }
                    .disabled(apiKey.isEmpty)

                    Button("Remove", role: .destructive) {
                        apiKey = ""
                        coordinator.removeAPIKey()
                    }
                    .disabled(!appState.apiKeyStatus.canRemoveStoredKey)
                }

                if appState.apiKeyStatus == .developmentOverride {
                    Text("OPENROUTER_API_KEY takes precedence for this development launch.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Startup") {
                Toggle(
                    "Launch at Login",
                    isOn: Binding(
                        get: { appState.launchAtLoginStatus.isRequested },
                        set: { isEnabled in
                            coordinator.setLaunchAtLogin(isEnabled)
                        }
                    )
                )
                LabeledContent("Registration", value: appState.launchAtLoginStatus.displayName)

                if appState.launchAtLoginStatus == .requiresApproval {
                    Button("Open Login Items Settings") {
                        coordinator.openLoginItemsSettings()
                    }
                }
            }

            Section("Recording HUD") {
                Button("Preview Recording HUD") {
                    coordinator.previewHUD()
                }
                Text("The preview disappears automatically and must not take keyboard focus.")
                    .foregroundStyle(.secondary)
            }

            Section("Models") {
                let models = AIModelConfiguration.phaseZeroVerified
                LabeledContent("Transcription", value: models.transcriptionModel)
                LabeledContent("Transcription fallback", value: models.transcriptionFallbackModel)
                LabeledContent("Cleanup", value: models.cleanupModel)
                LabeledContent("Cleanup fallback", value: models.cleanupFallbackModel)
            }

            if let lastError = appState.lastError {
                Section("Last error") {
                    Text(lastError.localizedDescription)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 760)
        .onAppear {
            coordinator.refreshConfiguration()
        }
        .onDisappear {
            apiKey = ""
        }
    }
}
