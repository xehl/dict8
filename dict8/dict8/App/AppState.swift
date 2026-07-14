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

enum AppShellError: Equatable, LocalizedError, Sendable {
    case apiKeyStatusUnavailable
    case apiKeyInvalid
    case apiKeySaveFailed
    case apiKeyRemovalFailed
    case launchAtLoginUpdateFailed

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
        }
    }
}

struct AppConfiguration: Equatable, Sendable {
    let hotkeyDisplayName: String
    let hudPreviewDuration: Duration

    static let v0 = AppConfiguration(
        hotkeyDisplayName: "Control + Option",
        hudPreviewDuration: .seconds(2)
    )
}

@MainActor
final class AppState: ObservableObject {
    static let enabledDefaultsKey = "dict8.isEnabled"

    @Published private(set) var status: AppStatus
    @Published private(set) var apiKeyStatus: APIKeyStatus = .checking
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered
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
