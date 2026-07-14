import AppKit
import CoreGraphics
import Foundation

enum TextPasteError: Error, Equatable, Sendable {
    case emptyText
    case accessibilityPermissionRequired
    case targetUnavailable
    case secureField
    case clipboardWriteFailed
    case eventCreationFailed
}

enum TextPasteResult: Equatable, Sendable {
    case pasted(secureFieldStatusUnknown: Bool)
    case copiedBecauseTargetChanged
}

@MainActor
protocol TextPasting: AnyObject {
    func paste(_ text: String, originatingTarget: PasteTarget) async throws -> TextPasteResult
}

@MainActor
protocol PlainTextClipboardWriting: AnyObject {
    func write(_ text: String) throws
}

@MainActor
protocol PasteEventPosting: AnyObject {
    func postPaste() async throws
}

@MainActor
final class SystemTextPasteService: TextPasting {
    private let accessibility: any AccessibilityInspecting
    private let clipboard: any PlainTextClipboardWriting
    private let eventPoster: any PasteEventPosting

    init(
        accessibility: any AccessibilityInspecting,
        clipboard: any PlainTextClipboardWriting = SystemPlainTextClipboard(),
        eventPoster: any PasteEventPosting = SystemPasteEventPoster()
    ) {
        self.accessibility = accessibility
        self.clipboard = clipboard
        self.eventPoster = eventPoster
    }

    func paste(_ text: String, originatingTarget: PasteTarget) async throws -> TextPasteResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextPasteError.emptyText
        }
        guard accessibility.permissionStatus == .granted else {
            throw TextPasteError.accessibilityPermissionRequired
        }

        let currentTarget = accessibility.captureTarget()
        guard originatingTarget.bundleIdentifier != nil,
              originatingTarget.processIdentifier != nil,
              currentTarget.bundleIdentifier != nil,
              currentTarget.processIdentifier != nil else {
            throw TextPasteError.targetUnavailable
        }

        guard originatingTarget.identifiesSameApplication(as: currentTarget) else {
            try clipboard.write(text)
            return .copiedBecauseTargetChanged
        }

        guard currentTarget.secureFieldStatus != .secure else {
            throw TextPasteError.secureField
        }

        try clipboard.write(text)
        try await eventPoster.postPaste()
        return .pasted(secureFieldStatusUnknown: currentTarget.secureFieldStatus == .unknown)
    }
}

@MainActor
final class SystemPlainTextClipboard: PlainTextClipboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func write(_ text: String) throws {
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw TextPasteError.clipboardWriteFailed
        }
    }
}

@MainActor
final class SystemPasteEventPoster: PasteEventPosting {
    static let syntheticEventMarker: Int64 = 0xD1C8

    func postPaste() async throws {
        try await Task.sleep(for: .milliseconds(40))

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: false
              ) else {
            throw TextPasteError.eventCreationFailed
        }

        for event in [keyDown, keyUp] {
            event.flags = .maskCommand
            event.setIntegerValueField(
                .eventSourceUserData,
                value: Self.syntheticEventMarker
            )
            event.post(tap: .cghidEventTap)
        }
    }
}
