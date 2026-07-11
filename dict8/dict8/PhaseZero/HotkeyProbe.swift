import ApplicationServices
import Combine
import CoreGraphics
import Foundation

enum HotkeyProbeError: LocalizedError {
    case accessibilityPermissionRequired
    case eventTapCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required for the active event-tap probe."
        case .eventTapCreationFailed:
            "macOS refused to create the active event tap."
        }
    }
}

@MainActor
final class HotkeyProbe: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var pressCount = 0
    @Published private(set) var releaseCount = 0
    @Published private(set) var lastError: String?

    var onPress: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var chordIsActive = false

    var accessibilityIsTrusted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
    }

    func start() throws {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            throw HotkeyProbeError.accessibilityPermissionRequired
        }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw HotkeyProbeError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        lastError = nil
        isRunning = true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        chordIsActive = false
        isRunning = false
    }

    private func handle(flags: CGEventFlags) {
        let isActive = flags.contains(.maskControl) && flags.contains(.maskAlternate)

        if isActive && !chordIsActive {
            chordIsActive = true
            pressCount += 1
            onPress?()
        } else if !isActive && chordIsActive {
            chordIsActive = false
            releaseCount += 1
        }
    }

    private func reenableAfterSystemDisable() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        lastError = "macOS disabled the event tap temporarily; the probe re-enabled it."
    }

    private nonisolated static let eventTapCallback: CGEventTapCallBack = {
        _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let probe = Unmanaged<HotkeyProbe>.fromOpaque(userInfo).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                probe.reenableAfterSystemDisable()
            }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        Task { @MainActor in
            probe.handle(flags: flags)
        }

        // Control/Option are modifier-only input for this probe. Suppressing all
        // four modifier key codes demonstrates the product tradeoff without
        // changing any production hotkey implementation.
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let controlOrOptionKeyCodes: Set<Int64> = [58, 59, 61, 62]
        if controlOrOptionKeyCodes.contains(keyCode) {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}
