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
                    "Microphone",
                    value: appState.microphonePermissionStatus.displayName
                )

                HStack {
                    Button("Request Microphone") {
                        coordinator.requestMicrophonePermission()
                    }
                    .disabled(
                        appState.microphonePermissionStatus == .granted
                            || appState.microphonePermissionStatus == .restricted
                    )

                    Button("Open Microphone Settings") {
                        coordinator.openMicrophoneSettings()
                    }

                    Button("Refresh Microphone") {
                        coordinator.refreshMicrophonePermission()
                    }
                }

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

                    Button("Refresh Accessibility") {
                        coordinator.refreshAccessibilityPermission()
                    }
                }

                Text("Accessibility lets dict8 inspect the focused target and synthesize paste without reading field contents.")
                    .foregroundStyle(.secondary)
            }

            Section("Audio recording test") {
                LabeledContent("Status", value: appState.audioTestStatus.displayName)

                if appState.audioTestStatus.isStartingOrRecording {
                    HStack {
                        Button("Stop Test Recording") {
                            coordinator.stopTestRecording()
                        }
                        .disabled(appState.audioTestStatus == .starting)

                        Button("Cancel and Delete", role: .destructive) {
                            coordinator.cancelTestRecording()
                        }
                    }
                } else if appState.audioTestStatus.hasRecordingReady {
                    HStack {
                        Button("Transcribe and Delete") {
                            coordinator.transcribeAndDeleteTestRecording()
                        }

                        Button("Play and Delete") {
                            coordinator.playAndDeleteTestRecording()
                        }

                        Button("Delete Without Playing", role: .destructive) {
                            coordinator.deleteTestRecording()
                        }
                    }
                } else if appState.audioTestStatus == .playing {
                    Button("Stop Playback and Delete", role: .destructive) {
                        coordinator.cancelTestRecording()
                    }
                } else if appState.audioTestStatus == .transcribing {
                    Button("Cancel Transcription and Delete", role: .destructive) {
                        coordinator.cancelTestRecording()
                    }
                } else {
                    Button("Start Test Recording") {
                        coordinator.startTestRecording()
                    }
                    .disabled(
                        !appState.isEnabled
                            || appState.microphonePermissionStatus != .granted
                    )
                }

                if let transcript = appState.testTranscript {
                    ScrollView {
                        Text(transcript)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                        .frame(minHeight: 100, maxHeight: 180)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))

                    if let metadata = appState.audioTranscriptionTestMetadata {
                        LabeledContent("Transcription model", value: metadata.model)
                        LabeledContent(
                            "Model attempt",
                            value: metadata.usedFallback ? "Explicit fallback" : "Primary"
                        )
                        LabeledContent(
                            "Request latency",
                            value: metadata.latencySeconds.formatted(.number.precision(.fractionLength(3))) + " s"
                        )
                        LabeledContent(
                            "Recorded duration",
                            value: metadata.recordedDuration.formatted(.number.precision(.fractionLength(1))) + " s"
                        )
                        LabeledContent(
                            "Reported cost",
                            value: metadata.cost.map {
                                "$" + $0.formatted(.number.precision(.fractionLength(6)))
                            } ?? "Not reported"
                        )
                    }

                    Button("Clear Transcript", role: .destructive) {
                        coordinator.clearTestTranscript()
                    }
                }

                Text("Records mono AAC to an app-owned temporary .m4a file. Transcribe deletes the audio after success or failure. The validation transcript remains only in memory and clears after two minutes, when Settings closes, or during lifecycle cleanup.")
                    .foregroundStyle(.secondary)
            }

            Section("Cleanup test") {
                LabeledContent("Status", value: appState.cleanupTestStatus.displayName)

                Menu("Load Synthetic Sample") {
                    ForEach(CleanupTestFixture.allCases) { fixture in
                        Button(fixture.displayName) {
                            coordinator.loadCleanupTestFixture(fixture)
                        }
                    }
                }
                .disabled(appState.cleanupTestStatus == .cleaning)

                TextEditor(
                    text: Binding(
                        get: { appState.cleanupTestInput },
                        set: { coordinator.setCleanupTestInput($0) }
                    )
                )
                .font(.body)
                .frame(minHeight: 90, maxHeight: 150)
                .disabled(appState.cleanupTestStatus == .cleaning)

                HStack {
                    Button("Clean Text") {
                        coordinator.runCleanupTest()
                    }
                    .disabled(
                        !appState.isEnabled
                            || appState.cleanupTestInput
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                            || appState.cleanupTestStatus == .cleaning
                    )

                    Button("Clear", role: .destructive) {
                        coordinator.clearCleanupTest()
                    }
                    .disabled(
                        appState.cleanupTestInput.isEmpty
                            && appState.cleanupTestOutput == nil
                    )
                }

                if let output = appState.cleanupTestOutput {
                    Text(
                        appState.cleanupTestStatus == .rawFallback
                            ? "Result — raw fallback"
                            : "Cleaned result"
                    )
                    .font(.headline)

                    ScrollView {
                        Text(output)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(minHeight: 90, maxHeight: 180)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                }

                if let metadata = appState.cleanupTestMetadata {
                    LabeledContent("Cleanup model", value: metadata.model)
                    LabeledContent(
                        "Model attempt",
                        value: metadata.usedFallback ? "Explicit fallback" : "Primary"
                    )
                    LabeledContent(
                        "Request latency",
                        value: metadata.latencySeconds
                            .formatted(.number.precision(.fractionLength(3))) + " s"
                    )
                    LabeledContent(
                        "Reported cost",
                        value: metadata.cost.map {
                            "$" + $0.formatted(.number.precision(.fractionLength(6)))
                        } ?? "Not reported"
                    )
                }

                Text("Input and output remain only in memory and clear after two minutes, when Settings closes, or during lifecycle cleanup. A rejected or failed cleanup displays the unchanged raw input.")
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
        .frame(width: 680, height: 920)
        .onAppear {
            coordinator.refreshConfiguration()
        }
        .onDisappear {
            apiKey = ""
            coordinator.closeSettingsValidation()
        }
    }
}
