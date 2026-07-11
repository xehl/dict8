import AppKit
import ApplicationServices
import Foundation

struct FocusedElementSnapshot: Equatable {
    let bundleIdentifier: String?
    let role: String?
    let subrole: String?
    let isSecureTextField: Bool
    let diagnostic: String
}

enum FocusedElementProbe {
    static func capture() -> FocusedElementSnapshot {
        let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard AXIsProcessTrusted() else {
            return FocusedElementSnapshot(
                bundleIdentifier: bundleIdentifier,
                role: nil,
                subrole: nil,
                isSecureTextField: false,
                diagnostic: "Accessibility permission is not granted."
            )
        }

        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedApplication = elementAttribute(
            kAXFocusedApplicationAttribute,
            from: systemWideElement
        ) else {
            return unavailableSnapshot(
                bundleIdentifier: bundleIdentifier,
                diagnostic: "No focused application AX element was available."
            )
        }

        guard let focusedElement = elementAttribute(
            kAXFocusedUIElementAttribute,
            from: focusedApplication
        ) else {
            return unavailableSnapshot(
                bundleIdentifier: bundleIdentifier,
                diagnostic: "No focused UI element was available."
            )
        }

        let role = stringAttribute(kAXRoleAttribute, from: focusedElement)
        let subrole = stringAttribute(kAXSubroleAttribute, from: focusedElement)
        let isSecure = subrole == kAXSecureTextFieldSubrole

        return FocusedElementSnapshot(
            bundleIdentifier: bundleIdentifier,
            role: role,
            subrole: subrole,
            isSecureTextField: isSecure,
            diagnostic: "Focused element inspected without reading its value."
        )
    }

    private static func elementAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    private static func stringAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private static func unavailableSnapshot(
        bundleIdentifier: String?,
        diagnostic: String
    ) -> FocusedElementSnapshot {
        FocusedElementSnapshot(
            bundleIdentifier: bundleIdentifier,
            role: nil,
            subrole: nil,
            isSecureTextField: false,
            diagnostic: diagnostic
        )
    }
}
