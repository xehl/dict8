import AppKit
import AVFoundation

enum MicrophonePermissionStatus: Equatable, Sendable {
    case checking
    case notDetermined
    case granted
    case denied
    case restricted

    var displayName: String {
        switch self {
        case .checking: "Checking"
        case .notDetermined: "Not requested"
        case .granted: "Granted"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
    }
}

@MainActor
protocol MicrophonePermissionControlling: AnyObject {
    var status: MicrophonePermissionStatus { get }
    func requestPermission() async -> MicrophonePermissionStatus
    func openSystemSettings() -> Bool
}

@MainActor
final class SystemMicrophonePermissionService: MicrophonePermissionControlling {
    var status: MicrophonePermissionStatus {
        Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func requestPermission() async -> MicrophonePermissionStatus {
        guard status == .notDetermined else { return status }
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        return status
    }

    func openSystemSettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    private static func map(_ status: AVAuthorizationStatus) -> MicrophonePermissionStatus {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }
}
