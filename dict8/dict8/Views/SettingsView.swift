import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var apiKey = ""

    let coordinator: AppCoordinator

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Form {
                generalSection
                permissionsSection
                openRouterSection
                #if DEBUG
                recordingHUDSection
                #endif
            }
            .formStyle(.grouped)
            .frame(width: 360)

            Divider()

            Form {
                usageOverviewSection
                modelsSection
                #if DEBUG
                audioRecordingTestSection
                cleanupTestSection
                #endif
                lastIssueSection
            }
            .formStyle(.grouped)
            .frame(width: 360)

            Divider()

            Form {
                latencySection
                costSection
            }
            .formStyle(.grouped)
            .frame(width: 360)
        }
        .frame(width: 1080, height: 820)
        .onAppear {
            coordinator.refreshConfiguration()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            coordinator.refreshMicrophonePermission()
            coordinator.refreshAccessibilityPermission()
        }
        .onDisappear {
            apiKey = ""
            coordinator.closeSettingsValidation()
        }
    }

    @ViewBuilder
    private var generalSection: some View {
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
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { appState.launchAtLoginStatus.isRequested },
                    set: { isEnabled in
                        coordinator.setLaunchAtLogin(isEnabled)
                    }
                )
            )
            if appState.launchAtLoginStatus == .requiresApproval {
                Button("Open Login Items Settings") {
                    coordinator.openLoginItemsSettings()
                }
            }
            LabeledContent("Status", value: appState.status.displayName)
            LabeledContent("Push to talk", value: appState.configuration.hotkeyDisplayName)
            LabeledContent(
                "Paste last dictation",
                value: appState.configuration.pasteLastHotkeyDisplayName
            )

            #if DEBUG
            LabeledContent("Test status", value: appState.testPasteStatus.displayName)

            Button("Paste Test Text in 3 Seconds") {
                coordinator.testPaste()
            }
            .disabled(
                !appState.isEnabled
                    || appState.accessibilityStatus != .granted
                    || appState.testPasteStatus == .armed
                    || appState.status.isProcessing
            )

            Text("After clicking, focus a TextEdit document. A successful test seeds Paste Last for ten minutes.")
                .foregroundStyle(.secondary)
            #endif
        }
    }

    @ViewBuilder
    private var openRouterSection: some View {
        Section("OpenRouter") {
            LabeledContent("API key", value: appState.apiKeyStatus.displayName)

            SecureField("OpenRouter API key", text: $apiKey)
                .textContentType(nil)

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
    }

    @ViewBuilder
    private var permissionsSection: some View {
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
            }

            LabeledContent(
                "Accessibility",
                value: appState.accessibilityStatus.displayName
            )
            LabeledContent(
                "Global shortcuts",
                value: appState.hotkeyMonitorStatus.displayName
            )

            HStack {
                Button("Request Accessibility") {
                    coordinator.requestAccessibilityPermission()
                }
                .disabled(appState.accessibilityStatus == .granted)

                Button("Open Accessibility Settings") {
                    coordinator.openAccessibilitySettings()
                }
            }

            Text("Accessibility lets dict8 inspect the focused target and synthesize paste without reading field contents.")
                .foregroundStyle(.secondary)
        }
    }

    #if DEBUG
    @ViewBuilder
    private var recordingHUDSection: some View {
        Section("Recording HUD") {
            Button("Preview Recording HUD") {
                coordinator.previewHUD()
            }
            Text("The preview disappears automatically and must not take keyboard focus.")
                .foregroundStyle(.secondary)
        }
    }
    #endif

    @ViewBuilder
    private var modelsSection: some View {
        Section("Models") {
            let models = AIModelConfiguration.phaseZeroVerified
            LabeledContent("Transcription", value: models.transcriptionModel)
            LabeledContent("Transcription fallback", value: models.transcriptionFallbackModel)
            LabeledContent("Cleanup", value: models.cleanupModel)
            LabeledContent(
                "Cleanup routing",
                value: "Auto Router — cost tier: \(OpenRouterTextCleanupService.autoRouterSettings.costTier.rawValue)"
            )
        }
    }

    @ViewBuilder
    private var usageOverviewSection: some View {
        Section("Usage") {
            let metrics = appState.usageMetrics
            LabeledContent("Storage", value: appState.metricsStatus.displayName)
            LabeledContent("Dictation requests", value: metrics.requestCount.formatted())
            LabeledContent("Successful", value: metrics.successCount.formatted())
            LabeledContent("Failed", value: metrics.failureCount.formatted())
            LabeledContent(
                "Audio minutes",
                value: metrics.audioMinutes.formatted(
                    .number.precision(.fractionLength(2))
                )
            )
            LabeledContent(
                "Raw cleanup fallbacks",
                value: metrics.cleanupFallbackCount.formatted()
            )
            if let top = metrics.topCleanupFallbackReason {
                LabeledContent(
                    "Top fallback reason",
                    value: "\(top.reason.displayName) (\(top.count.formatted()))"
                )
            }
            LabeledContent(
                "Last issue",
                value: metrics.lastIssueCategory?.displayName ?? "None"
            )
            LabeledContent(
                "Startup audio cleanup",
                value: appState.temporaryAudioMaintenanceStatus.displayName
            )

            Text("Metrics are aggregate and content-free.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var latencySection: some View {
        Section("Latency") {
            let metrics = appState.usageMetrics
            LabeledContent(
                "Average transcription",
                value: latency(metrics.averageTranscriptionLatencySeconds)
            )
            LabeledContent(
                "Transcription p50",
                value: latency(metrics.p50TranscriptionLatencySeconds)
            )
            LabeledContent(
                "Transcription p95",
                value: latency(metrics.p95TranscriptionLatencySeconds)
            )
            LabeledContent(
                "Average cleanup",
                value: latency(metrics.averageCleanupLatencySeconds)
            )
            LabeledContent(
                "Cleanup p50",
                value: latency(metrics.p50CleanupLatencySeconds)
            )
            LabeledContent(
                "Cleanup p95",
                value: latency(metrics.p95CleanupLatencySeconds)
            )
            LabeledContent(
                "Average end-to-end",
                value: latency(metrics.averagePipelineLatencySeconds)
            )

            Text("Percentiles are estimated over the most recent \(UsageMetricsSnapshot.latencySampleCap) requests per stage.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var costSection: some View {
        Section("Cost") {
            let metrics = appState.usageMetrics
            LabeledContent(
                "Reported transcription cost",
                value: currency(metrics.totalTranscriptionCost)
            )
            LabeledContent(
                "Reported cleanup cost",
                value: currency(metrics.totalCleanupCost)
            )
            LabeledContent(
                "Reported total cost",
                value: currency(metrics.totalReportedCost)
            )

            Text("Reported cost may be partial when OpenRouter omits usage metadata.")
                .foregroundStyle(.secondary)
        }
    }

    #if DEBUG
    @ViewBuilder
    private var audioRecordingTestSection: some View {
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
                        || appState.status.isProcessing
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
                        "Provider audio duration",
                        value: metadata.providerAudioSeconds.map {
                            $0.formatted(.number.precision(.fractionLength(1))) + " s"
                        } ?? "Not reported"
                    )
                    LabeledContent(
                        "Coverage diagnostic",
                        value: metadata.coverageDiagnostic.displayName
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
    }

    @ViewBuilder
    private var cleanupTestSection: some View {
        Section("Cleanup test") {
            LabeledContent("Status", value: appState.cleanupTestStatus.displayName)

            Menu("Load Synthetic Sample") {
                ForEach(CleanupTestFixture.allCases) { fixture in
                    Button(fixture.displayName) {
                        coordinator.loadCleanupTestFixture(fixture)
                    }
                }
            }
            .disabled(
                appState.cleanupTestStatus == .cleaning
                    || appState.status.isProcessing
            )

            TextEditor(
                text: Binding(
                    get: { appState.cleanupTestInput },
                    set: { coordinator.setCleanupTestInput($0) }
                )
            )
            .font(.body)
            .frame(minHeight: 90, maxHeight: 150)
            .disabled(
                appState.cleanupTestStatus == .cleaning
                    || appState.status.isProcessing
            )

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
                        || appState.status.isProcessing
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
    }
    #endif

    @ViewBuilder
    private var lastIssueSection: some View {
        if let lastError = appState.lastError {
            Section(appState.status == .warning ? "Last warning" : "Last error") {
                Text(lastError.localizedDescription)
                    .foregroundStyle(appState.status == .warning ? .orange : .red)
            }
        }
    }

    private func currency(_ value: Double) -> String {
        "$" + value.formatted(.number.precision(.fractionLength(6)))
    }

    private func latency(_ value: Double?) -> String {
        guard let value else { return "Not available" }
        return value.formatted(.number.precision(.fractionLength(3))) + " s"
    }
}
