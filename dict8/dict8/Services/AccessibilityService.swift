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
    let windowTitle: String?
    let precedingText: String?

    init(
        bundleIdentifier: String?,
        localizedName: String? = nil,
        processIdentifier: pid_t?,
        secureFieldStatus: SecureFieldStatus,
        windowTitle: String? = nil,
        precedingText: String? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.processIdentifier = processIdentifier
        self.secureFieldStatus = secureFieldStatus
        self.windowTitle = windowTitle
        self.precedingText = precedingText
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

        let windowTitle = focusedWindowTitle(in: applicationElement)

        let subrole = stringAttribute(kAXSubroleAttribute, from: focusedElement)
        if subrole == kAXSecureTextFieldSubrole {
            return target(
                for: application,
                secureFieldStatus: .secure,
                windowTitle: windowTitle,
                precedingText: nil
            )
        }

        let role = stringAttribute(kAXRoleAttribute, from: focusedElement)
        let knownTextRoles = [kAXTextFieldRole, kAXTextAreaRole]
        let status: SecureFieldStatus = knownTextRoles.contains(role ?? "")
            ? .notSecure
            : .unknown

        let preceding = precedingText(from: focusedElement)
        return target(
            for: application,
            secureFieldStatus: status,
            windowTitle: windowTitle,
            precedingText: preceding
        )
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

        // 1. Try direct value attribute (standard native text fields, WebViews)
        if let value = stringAttribute(kAXValueAttribute, from: focusedElement), !value.isEmpty {
            return value
        }

        // 2. Try selected text if highlighted
        if let selected = stringAttribute(kAXSelectedTextAttribute, from: focusedElement), !selected.isEmpty {
            return selected
        }

        // 3. Try description / title for certain editable custom views
        if let title = stringAttribute(kAXTitleAttribute, from: focusedElement), !title.isEmpty {
            return title
        }

        return nil
    }

    private func target(
        for application: NSRunningApplication,
        secureFieldStatus: SecureFieldStatus,
        windowTitle: String? = nil,
        precedingText: String? = nil
    ) -> PasteTarget {
        PasteTarget(
            bundleIdentifier: application.bundleIdentifier,
            localizedName: application.localizedName,
            processIdentifier: application.processIdentifier,
            secureFieldStatus: secureFieldStatus,
            windowTitle: windowTitle,
            precedingText: precedingText
        )
    }

    private func focusedWindowTitle(in applicationElement: AXUIElement) -> String? {
        var windowValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        )
        guard result == .success,
              let windowValue,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            return nil
        }
        let windowElement = unsafeDowncast(windowValue, to: AXUIElement.self)
        return stringAttribute(kAXTitleAttribute, from: windowElement)
    }

    private func precedingText(from element: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        guard let fullText = stringAttribute(kAXValueAttribute, from: element),
              !fullText.isEmpty else {
            return nil
        }

        var rangeValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )

        guard result == .success,
              let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(rangeValue, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        let cursorLocation = range.location
        guard cursorLocation > 0 && cursorLocation <= fullText.utf16.count else {
            return nil
        }

        let utf16 = fullText.utf16
        let prefixEndIndex = utf16.index(utf16.startIndex, offsetBy: cursorLocation)
        let prefixUtf16 = utf16[..<prefixEndIndex]
        let prefixString = String(prefixUtf16) ?? ""
        guard !prefixString.isEmpty else {
            return nil
        }

        // Return up to the last 100 characters before the cursor
        let maxChars = 100
        if prefixString.count > maxChars {
            return String(prefixString.suffix(maxChars))
        }
        return prefixString
    }

    private func focusedElement(in applicationElement: AXUIElement) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(applicationElement, 0.1)
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

        let element = unsafeDowncast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.1)
        return element
    }

    private func stringAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        AXUIElementSetMessagingTimeout(element, 0.1)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }
}
