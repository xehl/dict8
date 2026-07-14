import Combine
import Foundation

enum AppStatus: Equatable, Sendable {
    case disabled
    case idle
    case recording
    case encoding
    case transcribing
    case cleaning
    case pasting
    case completed
    case warning
    case error

    var displayName: String {
        switch self {
        case .disabled: "Disabled"
        case .idle: "Ready"
        case .recording: "Recording"
        case .encoding: "Preparing audio"
        case .transcribing: "Transcribing"
        case .cleaning: "Cleaning up"
        case .pasting: "Pasting"
        case .completed: "Completed"
        case .warning: "Warning"
        case .error: "Error"
        }
    }
}

enum APIKeyStatus: Equatable, Sendable {
    case checking
    case missing
    case storedInKeychain
    case developmentOverride
    case unavailable

    var displayName: String {
        switch self {
        case .checking: "Checking"
        case .missing: "Missing"
        case .storedInKeychain: "Configured in Keychain"
        case .developmentOverride: "Development override active"
        case .unavailable: "Unavailable"
        }
    }

    var canRemoveStoredKey: Bool {
        self == .storedInKeychain || self == .developmentOverride
    }
}

enum LaunchAtLoginStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable

    var isRequested: Bool {
        self == .enabled || self == .requiresApproval
    }

    var displayName: String {
        switch self {
        case .notRegistered: "Off"
        case .enabled: "On"
        case .requiresApproval: "Approval required"
        case .unavailable: "Unavailable"
        }
    }
}

enum TestPasteStatus: Equatable, Sendable {
    case idle
    case armed
    case pasted
    case pastedWithUnknownSecurity
    case copiedBecauseFocusChanged
    case failed

    var displayName: String {
        switch self {
        case .idle: "Ready"
        case .armed: "Focus a text field — pasting in 3 seconds"
        case .pasted: "Test text pasted"
        case .pastedWithUnknownSecurity: "Pasted after verifying the target app"
        case .copiedBecauseFocusChanged: "Copied because focus changed"
        case .failed: "Test paste failed — see Last error"
        }
    }
}

enum AudioTestStatus: Equatable, Sendable {
    case idle
    case starting
    case recording(elapsedSeconds: Int)
    case ready(durationSeconds: Int)
    case playing

    var displayName: String {
        switch self {
        case .idle: "Ready"
        case .starting: "Starting"
        case let .recording(elapsedSeconds):
            "Recording \(Self.time(elapsedSeconds))"
        case let .ready(durationSeconds):
            "Recorded \(Self.time(durationSeconds)) — temporary"
        case .playing: "Playing, then deleting"
        }
    }

    var isStartingOrRecording: Bool {
        switch self {
        case .starting, .recording: true
        default: false
        }
    }

    var hasRecordingReady: Bool {
        if case .ready = self { true } else { false }
    }

    private static func time(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

enum AppShellError: Equatable, LocalizedError, Sendable {
    case apiKeyStatusUnavailable
    case apiKeyInvalid
    case apiKeySaveFailed
    case apiKeyRemovalFailed
    case launchAtLoginUpdateFailed
    case accessibilityPermissionRequired
    case accessibilitySettingsUnavailable
    case pasteTargetUnavailable
    case secureFieldRefused
    case clipboardWriteFailed
    case pasteEventCreationFailed
    case pasteFailed
    case pasteLastMonitorFailed
    case microphonePermissionRequired
    case microphonePermissionRestricted
    case microphoneSettingsUnavailable
    case recordingAlreadyActive
    case noActiveRecording
    case recordingStartFailed
    case recordingEncodingFailed
    case temporaryAudioCleanupFailed
    case audioPlaybackFailed

    var errorDescription: String? {
        switch self {
        case .apiKeyStatusUnavailable:
            "dict8 could not check Keychain configuration."
        case .apiKeyInvalid:
            "Enter a non-empty OpenRouter API key."
        case .apiKeySaveFailed:
            "dict8 could not save the API key to Keychain."
        case .apiKeyRemovalFailed:
            "dict8 could not remove the API key from Keychain."
        case .launchAtLoginUpdateFailed:
            "dict8 could not update Launch at Login."
        case .accessibilityPermissionRequired:
            "Accessibility permission is required to inspect the target and paste."
        case .accessibilitySettingsUnavailable:
            "dict8 could not open Accessibility settings."
        case .pasteTargetUnavailable:
            "dict8 could not identify the focused application."
        case .secureFieldRefused:
            "dict8 will not paste into a known secure field."
        case .clipboardWriteFailed:
            "dict8 could not copy the text to the clipboard."
        case .pasteEventCreationFailed:
            "The text was copied, but dict8 could not create the paste event."
        case .pasteFailed:
            "dict8 could not complete the paste."
        case .pasteLastMonitorFailed:
            "dict8 could not start the Paste Last shortcut monitor."
        case .microphonePermissionRequired:
            "Microphone permission is required to record dictation."
        case .microphonePermissionRestricted:
            "Microphone access is restricted on this Mac."
        case .microphoneSettingsUnavailable:
            "dict8 could not open Microphone settings."
        case .recordingAlreadyActive:
            "A recording is already active."
        case .noActiveRecording:
            "There is no active recording to stop."
        case .recordingStartFailed:
            "dict8 could not start recording from the current microphone."
        case .recordingEncodingFailed:
            "dict8 could not finish the audio recording."
        case .temporaryAudioCleanupFailed:
            "dict8 could not remove a temporary audio file."
        case .audioPlaybackFailed:
            "dict8 could not play the temporary recording."
        }
    }
}

struct AppConfiguration: Equatable, Sendable {
    let hotkeyDisplayName: String
    let pasteLastHotkeyDisplayName: String
    let hudPreviewDuration: Duration
    let testPasteDelay: Duration
    let testPasteText: String
    let testRecordingLifetime: Duration

    static let v0 = AppConfiguration(
        hotkeyDisplayName: "Control + Option",
        pasteLastHotkeyDisplayName: "Command + Control + V",
        hudPreviewDuration: .seconds(2),
        testPasteDelay: .seconds(3),
        testPasteText: "dict8 paste test",
        testRecordingLifetime: .seconds(10 * 60)
    )
}

@MainActor
final class AppState: ObservableObject {
    static let enabledDefaultsKey = "dict8.isEnabled"

    @Published private(set) var status: AppStatus
    @Published private(set) var apiKeyStatus: APIKeyStatus = .checking
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered
    @Published private(set) var accessibilityStatus: AccessibilityPermissionStatus = .checking
    @Published private(set) var microphonePermissionStatus: MicrophonePermissionStatus = .checking
    @Published private(set) var testPasteStatus: TestPasteStatus = .idle
    @Published private(set) var audioTestStatus: AudioTestStatus = .idle
    @Published private(set) var lastError: AppShellError?

    let configuration: AppConfiguration

    private let defaults: UserDefaults
    private var enabledPreference: Bool

    init(
        defaults: UserDefaults = .standard,
        configuration: AppConfiguration = .v0
    ) {
        self.defaults = defaults
        self.configuration = configuration

        if defaults.object(forKey: Self.enabledDefaultsKey) == nil {
            enabledPreference = true
            status = .idle
            defaults.set(true, forKey: Self.enabledDefaultsKey)
        } else {
            enabledPreference = defaults.bool(forKey: Self.enabledDefaultsKey)
            status = enabledPreference ? .idle : .disabled
        }
    }

    var isEnabled: Bool {
        enabledPreference
    }

    func setEnabled(_ isEnabled: Bool) {
        enabledPreference = isEnabled
        status = isEnabled ? .idle : .disabled
        defaults.set(isEnabled, forKey: Self.enabledDefaultsKey)
        lastError = nil
    }

    func setAPIKeyStatus(_ status: APIKeyStatus) {
        apiKeyStatus = status
    }

    func setLaunchAtLoginStatus(_ status: LaunchAtLoginStatus) {
        launchAtLoginStatus = status
    }

    func setAccessibilityStatus(_ status: AccessibilityPermissionStatus) {
        accessibilityStatus = status
    }

    func setMicrophonePermissionStatus(_ status: MicrophonePermissionStatus) {
        microphonePermissionStatus = status
    }

    func setTestPasteStatus(_ status: TestPasteStatus) {
        testPasteStatus = status
    }

    func setAudioTestStatus(_ status: AudioTestStatus) {
        audioTestStatus = status
    }

    func setStatus(_ status: AppStatus) {
        self.status = enabledPreference ? status : .disabled
    }

    func setError(_ error: AppShellError) {
        lastError = error
        status = enabledPreference ? .error : .disabled
    }

    func clearError() {
        lastError = nil
        if status == .error || status == .disabled {
            status = enabledPreference ? .idle : .disabled
        }
    }
}
