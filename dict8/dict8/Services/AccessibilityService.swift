import AppKit
import ApplicationServices
import Foundation

enum AccessibilityPermissionStatus: Equatable, Sendable {
    case checking
    case granted
    case required

    var displayName: String {
        switch self {
        case .checking: "Checking"
        case .granted: "Granted"
        case .required: "Required"
        }
    }
}

enum SecureFieldStatus: Equatable, Sendable {
    case secure
    case notSecure
    case unknown
}

struct PasteTarget: Equatable, Sendable {
    let bundleIdentifier: String?
    let localizedName: String?
    let processIdentifier: pid_t?
    let secureFieldStatus: SecureFieldStatus

    init(
        bundleIdentifier: String?,
        localizedName: String? = nil,
        processIdentifier: pid_t?,
        secureFieldStatus: SecureFieldStatus
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
        self.secureFieldStatus = secureFieldStatus
    }

    func identifiesSameApplication(as other: PasteTarget) -> Bool {
        guard let bundleIdentifier,
              let processIdentifier,
              let otherBundleIdentifier = other.bundleIdentifier,
              let otherProcessIdentifier = other.processIdentifier else {
            return false
        }

        return bundleIdentifier == otherBundleIdentifier
            && processIdentifier == otherProcessIdentifier
    }
}

@MainActor
protocol AccessibilityInspecting: AnyObject {
    var permissionStatus: AccessibilityPermissionStatus { get }
    func requestPermission()
    func openSystemSettings() -> Bool
    func captureTarget() -> PasteTarget
    func readFocusedElementText(in application: NSRunningApplication?) -> String?
}

@MainActor
final class SystemAccessibilityService: AccessibilityInspecting {
    var permissionStatus: AccessibilityPermissionStatus {
        AXIsProcessTrusted() ? .granted : .required
    }

    func requestPermission() {
        AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
    }

    func openSystemSettings() -> Bool {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    func captureTarget() -> PasteTarget {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return PasteTarget(
                bundleIdentifier: nil,
                processIdentifier: nil,
                secureFieldStatus: .unknown
            )
        }

        guard AXIsProcessTrusted() else {
            return target(for: application, secureFieldStatus: .unknown)
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let focusedElement = focusedElement(in: applicationElement) else {
            return target(for: application, secureFieldStatus: .unknown)
        }

        let subrole = stringAttribute(kAXSubroleAttribute, from: focusedElement)
        if subrole == kAXSecureTextFieldSubrole {
            return target(for: application, secureFieldStatus: .secure)
        }

        let role = stringAttribute(kAXRoleAttribute, from: focusedElement)
        let knownTextRoles = [kAXTextFieldRole, kAXTextAreaRole]
        let status: SecureFieldStatus = knownTextRoles.contains(role ?? "")
            ? .notSecure
            : .unknown
        return target(for: application, secureFieldStatus: status)
    }

    func readFocusedElementText(in application: NSRunningApplication?) -> String? {
        guard AXIsProcessTrusted(),
              let app = application ?? NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let applicationElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let focusedElement = focusedElement(in: applicationElement) else {
            return nil
        }
        return stringAttribute(kAXValueAttribute, from: focusedElement)
    }

    private func target(
        for application: NSRunningApplication,
        secureFieldStatus: SecureFieldStatus
    ) -> PasteTarget {
        PasteTarget(
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName,
            processIdentifier: application.processIdentifier,
            secureFieldStatus: secureFieldStatus
        )
    }

    private func focusedElement(in applicationElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func stringAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }
}
