import ApplicationServices
import CoreGraphics
import Foundation

enum PasteLastHotkeyError: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case eventTapCreationFailed
}

@MainActor
protocol PasteLastHotkeyMonitoring: AnyObject {
    var isRunning: Bool { get }
    var onPasteLast: (() -> Void)? { get set }
    func start() throws
    func stop()
}

@MainActor
final class SystemPasteLastHotkeyMonitor: PasteLastHotkeyMonitoring {
    private static let vKeyCode: Int64 = 9

    private(set) var isRunning = false
    var onPasteLast: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isTrackingShortcut = false
    private var vKeyIsDown = false

    func start() throws {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            throw PasteLastHotkeyError.accessibilityPermissionRequired
        }

        let interestedEvents = [
            CGEventType.keyDown,
            CGEventType.keyUp,
            CGEventType.flagsChanged,
        ]
        let mask = interestedEvents.reduce(CGEventMask(0)) { partialResult, eventType in
            partialResult | CGEventMask(1 << eventType.rawValue)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw PasteLastHotkeyError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
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
        isTrackingShortcut = false
        vKeyIsDown = false
        isRunning = false
    }

    private func handle(
        typeRawValue: UInt32,
        keyCode: Int64,
        flagsRawValue: UInt64,
        marker: Int64
    ) -> Bool {
        if marker == SystemPasteEventPoster.syntheticEventMarker {
            return false
        }

        let flags = CGEventFlags(rawValue: flagsRawValue)
        let hasRequiredModifiers = flags.contains(.maskCommand)
            && flags.contains(.maskControl)
        let hasEitherRequiredModifier = flags.contains(.maskCommand)
            || flags.contains(.maskControl)

        switch typeRawValue {
        case CGEventType.keyDown.rawValue where keyCode == Self.vKeyCode && hasRequiredModifiers:
            isTrackingShortcut = true
            vKeyIsDown = true
            return true

        case CGEventType.keyUp.rawValue where keyCode == Self.vKeyCode && isTrackingShortcut:
            vKeyIsDown = false
            triggerIfReleased(hasEitherRequiredModifier: hasEitherRequiredModifier)
            return true

        case CGEventType.flagsChanged.rawValue where isTrackingShortcut:
            triggerIfReleased(hasEitherRequiredModifier: hasEitherRequiredModifier)
            return false

        default:
            return false
        }
    }

    private func triggerIfReleased(hasEitherRequiredModifier: Bool) {
        guard isTrackingShortcut,
              !vKeyIsDown,
              !hasEitherRequiredModifier else {
            return
        }

        isTrackingShortcut = false
        onPasteLast?()
    }

    private func reenableAfterSystemDisable() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private nonisolated static let eventTapCallback: CGEventTapCallBack = {
        _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let monitor = Unmanaged<SystemPasteLastHotkeyMonitor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                monitor.reenableAfterSystemDisable()
            }
            return Unmanaged.passUnretained(event)
        }

        let typeRawValue = type.rawValue
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flagsRawValue = event.flags.rawValue
        let marker = event.getIntegerValueField(.eventSourceUserData)

        let shouldConsume = MainActor.assumeIsolated {
            monitor.handle(
                typeRawValue: typeRawValue,
                keyCode: keyCode,
                flagsRawValue: flagsRawValue,
                marker: marker
            )
        }
        return shouldConsume ? nil : Unmanaged.passUnretained(event)
    }
}
