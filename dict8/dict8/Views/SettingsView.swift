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
            .scrollDisabled(true)
            .frame(width: 330, height: columnHeight, alignment: .top)

            Divider()

            Form {
                usageOverviewSection
                modelsSection
                #if DEBUG
                audioRecordingTestSection
                cleanupTestSection
                #endif
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 375, height: columnHeight, alignment: .top)

            Divider()

            Form {
                latencySection
                costSection
                lastIssueSection
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 375, height: columnHeight, alignment: .top)

            Form {
                perModelMetricsSection
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 375, height: columnHeight, alignment: .top)
            .padding(.trailing, 16)
        }
        .frame(width: 1485, height: columnHeight)
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

    /// Fixed height shared by all three columns so their forms line up
    /// evenly regardless of which column's content happens to be tallest;
    /// the shortest columns get trailing empty space instead of the window
    /// resizing to their content. Lowered by ~80pt (roughly two form rows,
    /// 2026-08-13 per Eric) to trim unneeded trailing whitespace below the
    /// shorter columns' content.
    private let columnHeight: CGFloat = 800

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

                Button("Microphone Settings") {
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

                Button("Accessibility Settings") {
                    coordinator.openAccessibilitySettings()
                }
            }
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
        Section("Models & Pipeline") {
            let models = AIModelConfiguration.phaseZeroVerified
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Transcription Model")
                Text(models.localTranscriptionModel)
                    .font(.body)
                Text("On-Device (Apple Neural Engine)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Picker("Cleanup Candidate", selection: Binding(
                get: { appState.selectedCleanupModel },
                set: { coordinator.setSelectedCleanupModel($0) }
            )) {
                ForEach(AIModelConfiguration.fastCleanupCandidates, id: \.self) { candidate in
                    Text(candidate).tag(candidate)
                }
            }
            .pickerStyle(.menu)

            if appState.selectedCleanupModel == "openrouter/auto" {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cleanup routing")
                    Text(
                        "Auto Router — cost tier: \(OpenRouterTextCleanupService.autoRouterSettings.costTier.rawValue)"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            } else {
                LabeledContent("Routing Mode", value: "Pinned Fast Cloud Candidate")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Custom Vocabulary")
                TextField(
                    "e.g. OpenRouter, Infisical, Devin, Jon Tuite, Abdalla",
                    text: Binding(
                        get: { appState.customVocabulary },
                        set: { coordinator.setCustomVocabulary($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                Text("Comma-separated proper nouns, acronyms, or phonetic spellings (e.g. Devin, Infisical).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
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
            LabeledContent("Success rate", value: successRate(metrics.successRate))
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
            LabeledContent(
                "Startup audio cleanup",
                value: appState.temporaryAudioMaintenanceStatus.displayName
            )
            LabeledContent(
                "Last issue",
                value: metrics.lastIssueCategory?.displayName ?? "None"
            )
            if let top = metrics.topCleanupFallbackReason {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top fallback reason")
                    Text("\(top.reason.displayName) (\(top.count.formatted()))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var latencySection: some View {
        Section("Latency") {
            let metrics = appState.usageMetrics
            LatencyStatRow(
                label: "Transcription",
                average: metrics.averageTranscriptionLatencySeconds,
                p50: metrics.p50TranscriptionLatencySeconds,
                p95: metrics.p95TranscriptionLatencySeconds
            )
            LatencyStatRow(
                label: "Cleanup",
                average: metrics.averageCleanupLatencySeconds,
                p50: metrics.p50CleanupLatencySeconds,
                p95: metrics.p95CleanupLatencySeconds
            )
            LatencyStatRow(
                label: "End-to-end",
                average: metrics.averagePipelineLatencySeconds,
                p50: metrics.p50PipelineLatencySeconds,
                p95: metrics.p95PipelineLatencySeconds
            )

            if let rtf = metrics.transcriptionRealTimeFactor {
                LabeledContent(
                    "Real-time factor (RTF)",
                    value: rtf.formatted(.number.precision(.fractionLength(3))) + "x"
                )
            }
            if let wps = metrics.transcriptionWordsPerSecond {
                LabeledContent(
                    "Transcription throughput",
                    value: wps.formatted(.number.precision(.fractionLength(1))) + " wps"
                )
            }

            Text("Estimated over the most recent \(UsageMetricsSnapshot.latencySampleCap) requests per stage.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var costSection: some View {
        Section("Cost") {
            let metrics = appState.usageMetrics
            VStack(alignment: .leading, spacing: 8) {
                Text("Inference costs (all time)")
                    .font(.body)
                HStack(spacing: 0) {
                    CostStatCell(caption: "transcription", value: metrics.totalTranscriptionCost)
                    StatDivider()
                    CostStatCell(caption: "cleanup", value: metrics.totalCleanupCost)
                    StatDivider()
                    CostStatCell(caption: "total", value: metrics.totalReportedCost)
                    Spacer()
                }
            }
            .padding(.vertical, 2)

            LabeledContent(
                "Cost per request",
                value: formattedCost(metrics.averageCostPerRequest)
            )
            LabeledContent(
                "Cost per audio minute",
                value: formattedCost(metrics.costPerAudioMinute)
            )
        }
    }

    private func formattedCost(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "$" + value.formatted(.number.precision(.fractionLength(6)))
    }

    private func formatStatSeconds(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(3))) + "s"
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

    @ViewBuilder
    private var perModelMetricsSection: some View {
        Section("Per-Model Cleanup") {
            let cleanupMetrics = appState.usageMetrics.cleanupModelMetrics
            let activeCandidates = Set(AIModelConfiguration.fastCleanupCandidates)
            let displayModels = Array(cleanupMetrics.keys.filter { activeCandidates.contains($0) }.sorted())
            if displayModels.isEmpty {
                Text("No metrics for active cleanup candidates yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayModels, id: \.self) { model in
                    if let stats = cleanupMetrics[model] {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model)
                                .font(.subheadline.bold())
                            HStack(spacing: 8) {
                                Text("\(formatStatSeconds(stats.averageLatencySeconds)) avg")
                                Text("·")
                                Text("\(formatStatSeconds(stats.p50LatencySeconds)) p50")
                                Text("·")
                                Text("\(formatStatSeconds(stats.p95LatencySeconds)) p95")
                            }
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)

                            HStack {
                                Text("\(stats.count) req · \(formattedCost(stats.totalCost))")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }

        Section("Recent Dictation Diagnostics") {
            let diagnostics = appState.cleanupDiagnostics
            if diagnostics.isEmpty {
                Text("No recent dictation diagnostics.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("\(diagnostics.count) recent event(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        coordinator.clearCleanupDiagnostics()
                    }
                    .font(.caption)
                }
                ForEach(diagnostics.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.model)
                                .font(.caption.bold())
                            Spacer()
                            if let failure = entry.failure {
                                Text(failure.displayName)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.orange)
                            } else {
                                Text("Cleaned")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.green)
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("In:")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text(entry.input)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Out:")
                                .font(.caption2.bold())
                                .foregroundStyle(.primary)
                            Text(entry.candidateOutput)
                                .font(.caption2)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                        HStack(spacing: 8) {
                            Text("Novel: \(entry.novelWordCount)w (\(Int(entry.novelWordRatio * 100))%)")
                                .font(.caption2)
                            Text("Exp: \(entry.expansionRatio.formatted(.number.precision(.fractionLength(2))))x")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func successRate(_ value: Double?) -> String {
        guard let value else { return "Not available" }
        return value.formatted(.percent.precision(.fractionLength(1)))
    }
}

/// Compact avg/p50/p95 latency row: the stage label on one line, then the
/// three stats laid out in a fixed-width mini table so they read as columns
/// rather than a single wrapped string, avoiding the empty gutter under the
/// label that a wrapped `LabeledContent` value produces.
private struct LatencyStatRow: View {
    let label: String
    let average: Double?
    let p50: Double?
    let p95: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.body)
            HStack(spacing: 0) {
                LatencyStatCell(caption: "avg", value: average)
                StatDivider()
                LatencyStatCell(caption: "p50", value: p50)
                StatDivider()
                LatencyStatCell(caption: "p95", value: p95)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StatDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .padding(.vertical, 2)
            .padding(.horizontal, 8)
    }
}

private struct LatencyStatCell: View {
    let caption: String
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(formatted)
                .font(.callout.monospacedDigit())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formatted: String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(3))) + "s"
    }
}

private struct CostStatCell: View {
    let caption: String
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(formatted)
                .font(.callout.monospacedDigit())
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 100, alignment: .leading)
    }

    private var formatted: String {
        guard let value else { return "—" }
        return "$" + value.formatted(.number.precision(.fractionLength(6)))
    }
}
