import ServiceManagement

@MainActor
protocol LaunchAtLoginControlling: AnyObject {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ isEnabled: Bool) throws
    func openSystemSettings()
}

@MainActor
final class SystemLaunchAtLoginService: LaunchAtLoginControlling {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        Self.map(service.status)
    }

    func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            guard Self.shouldAttemptRegistration(for: service.status) else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    static func map(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    static func shouldAttemptRegistration(for status: SMAppService.Status) -> Bool {
        switch status {
        case .enabled, .requiresApproval:
            false
        case .notRegistered, .notFound:
            true
        @unknown default:
            true
        }
    }
}
