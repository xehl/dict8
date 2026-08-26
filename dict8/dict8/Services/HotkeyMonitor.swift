import ApplicationServices
import CoreGraphics
import Foundation

nonisolated enum HotkeyMonitorError: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case eventTapCreationFailed
}

nonisolated enum HotkeyAction: Equatable, Sendable {
    case pushToTalkPressed
    case pushToTalkReleased
    case pasteLast
}

nonisolated struct HotkeyDecision: Equatable, Sendable {
    let consume: Bool
    let actions: [HotkeyAction]

    init(
        consume: Bool,
        actions: [HotkeyAction]
    ) {
        self.consume = consume
        self.actions = actions
    }

    static let pass = HotkeyDecision(consume: false, actions: [])
}

nonisolated struct HotkeyStateMachine: Sendable {
    private static let vKeyCode: Int64 = 9
    private static let controlKeyCodes: Set<Int64> = [59, 62]
    private static let optionKeyCodes: Set<Int64> = [58, 61]

    private var pushToTalkIsLatched = false
    private var pushToTalkReleaseWasSent = false
    private var consumedChordKeyCode: Int64?
    private var requiresFullModifierRelease = false
    private var pasteLastIsTracking = false
    private var pasteLastVIsDown = false

    mutating func arm(initialFlagsRawValue: UInt64) {
        reset()
        let flags = CGEventFlags(rawValue: initialFlagsRawValue)
        requiresFullModifierRelease = Self.hasControl(flags) || Self.hasOption(flags)
    }

    mutating func reset() {
        pushToTalkIsLatched = false
        pushToTalkReleaseWasSent = false
        consumedChordKeyCode = nil
        requiresFullModifierRelease = false
        pasteLastIsTracking = false
        pasteLastVIsDown = false
    }

    mutating func interrupt() -> [HotkeyAction] {
        let shouldRelease = pushToTalkIsLatched && !pushToTalkReleaseWasSent
        pushToTalkIsLatched = false
        pushToTalkReleaseWasSent = true
        requiresFullModifierRelease = true
        pasteLastIsTracking = false
        pasteLastVIsDown = false
        return shouldRelease ? [.pushToTalkReleased] : []
    }

    mutating func process(
        typeRawValue: UInt32,
        keyCode: Int64,
        flagsRawValue: UInt64,
        marker: Int64
    ) -> HotkeyDecision {
        guard marker != SystemPasteEventPoster.syntheticEventMarker else { return .pass }

        let flags = CGEventFlags(rawValue: flagsRawValue)
        var actions: [HotkeyAction] = []
        var consume = false

        processPasteLast(
            typeRawValue: typeRawValue,
            keyCode: keyCode,
            flags: flags,
            consume: &consume,
            actions: &actions
        )

        if typeRawValue == CGEventType.flagsChanged.rawValue {
            processPushToTalk(
                keyCode: keyCode,
                flags: flags,
                consume: &consume,
                actions: &actions
            )
        }

        return HotkeyDecision(
            consume: consume,
            actions: actions
        )
    }

    private mutating func processPushToTalk(
        keyCode: Int64,
        flags: CGEventFlags,
        consume: inout Bool,
        actions: inout [HotkeyAction]
    ) {
        let hasControl = Self.hasControl(flags)
        let hasOption = Self.hasOption(flags)

        if requiresFullModifierRelease {
            if keyCode == consumedChordKeyCode {
                consume = true
            }
            if !hasControl && !hasOption {
                pushToTalkIsLatched = false
                pushToTalkReleaseWasSent = false
                consumedChordKeyCode = nil
                requiresFullModifierRelease = false
            }
            return
        }

        let exactChord = hasControl
            && hasOption
            && !flags.contains(.maskCommand)
            && !flags.contains(.maskShift)

        if !pushToTalkIsLatched,
           exactChord,
           Self.isControlOrOptionKeyCode(keyCode) {
            pushToTalkIsLatched = true
            pushToTalkReleaseWasSent = false
            consumedChordKeyCode = keyCode
            consume = true
            actions.append(.pushToTalkPressed)
            return
        }

        guard pushToTalkIsLatched else { return }
        if keyCode == consumedChordKeyCode {
            consume = true
        }
        guard !exactChord, !pushToTalkReleaseWasSent else { return }

        pushToTalkReleaseWasSent = true
        requiresFullModifierRelease = true
        actions.append(.pushToTalkReleased)
        if !hasControl && !hasOption {
            pushToTalkIsLatched = false
            consumedChordKeyCode = nil
            requiresFullModifierRelease = false
        }
    }

    private mutating func processPasteLast(
        typeRawValue: UInt32,
        keyCode: Int64,
        flags: CGEventFlags,
        consume: inout Bool,
        actions: inout [HotkeyAction]
    ) {
        let hasCommand = flags.contains(.maskCommand)
        let hasControl = Self.hasControl(flags)
        let exactModifiers = hasCommand
            && hasControl
            && !Self.hasOption(flags)
            && !flags.contains(.maskShift)

        switch typeRawValue {
        case CGEventType.keyDown.rawValue where keyCode == Self.vKeyCode && exactModifiers:
            pasteLastIsTracking = true
            pasteLastVIsDown = true
            consume = true

        case CGEventType.keyUp.rawValue where keyCode == Self.vKeyCode && pasteLastIsTracking:
            pasteLastVIsDown = false
            consume = true
            triggerPasteLastIfReleased(
                hasEitherModifier: hasCommand || hasControl,
                actions: &actions
            )

        case CGEventType.flagsChanged.rawValue where pasteLastIsTracking:
            triggerPasteLastIfReleased(
                hasEitherModifier: hasCommand || hasControl,
                actions: &actions
            )

        default:
            break
        }
    }

    private mutating func triggerPasteLastIfReleased(
        hasEitherModifier: Bool,
        actions: inout [HotkeyAction]
    ) {
        guard pasteLastIsTracking,
              !pasteLastVIsDown,
              !hasEitherModifier else { return }
        pasteLastIsTracking = false
        actions.append(.pasteLast)
    }

    private static func hasControl(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskControl)
    }

    private static func hasOption(_ flags: CGEventFlags) -> Bool {
        flags.contains(.maskAlternate)
    }

    private static func isControlOrOptionKeyCode(_ keyCode: Int64) -> Bool {
        controlKeyCodes.contains(keyCode) || optionKeyCodes.contains(keyCode)
    }
}

@MainActor
protocol HotkeyMonitoring: AnyObject {
    var isRunning: Bool { get }
    var onPushToTalkPressed: (() -> Void)? { get set }
    var onPushToTalkReleased: (() -> Void)? { get set }
    var onPasteLast: (() -> Void)? { get set }
    func start() throws
    func stop()
}

@MainActor
final class SystemHotkeyMonitor: HotkeyMonitoring {
    private(set) var isRunning = false
    var onPushToTalkPressed: (() -> Void)?
    var onPushToTalkReleased: (() -> Void)?
    var onPasteLast: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var stateMachine = HotkeyStateMachine()
    private var watchdogTimer: Timer?

    func start() throws {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            throw HotkeyMonitorError.accessibilityPermissionRequired
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
            throw HotkeyMonitorError.eventTapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        stateMachine.arm(
            initialFlagsRawValue: CGEventSource.flagsState(.combinedSessionState).rawValue
        )
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        isRunning = true
        startWatchdog()
    }

    func stop() {
        stopWatchdog()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        stateMachine.reset()
        isRunning = false
    }

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.verifyEventTapHealth()
            }
        }
    }

    private func stopWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = nil
    }

    private func verifyEventTapHealth() {
        guard isRunning, let eventTap else { return }
        if !CGEvent.tapIsEnabled(tap: eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func handle(
        typeRawValue: UInt32,
        keyCode: Int64,
        flagsRawValue: UInt64,
        marker: Int64
    ) -> HotkeyDecision {
        let decision = stateMachine.process(
            typeRawValue: typeRawValue,
            keyCode: keyCode,
            flagsRawValue: flagsRawValue,
            marker: marker
        )
        deliver(decision.actions)
        return decision
    }

    private func handleInterruption() {
        deliver(stateMachine.interrupt())
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func deliver(_ actions: [HotkeyAction]) {
        for action in actions {
            switch action {
            case .pushToTalkPressed: onPushToTalkPressed?()
            case .pushToTalkReleased: onPushToTalkReleased?()
            case .pasteLast: onPasteLast?()
            }
        }
    }

    private nonisolated static let eventTapCallback: CGEventTapCallBack = {
        _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<SystemHotkeyMonitor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated {
                monitor.handleInterruption()
            }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flagsRawValue = event.flags.rawValue
        let marker = event.getIntegerValueField(.eventSourceUserData)
        let decision = MainActor.assumeIsolated {
            monitor.handle(
                typeRawValue: type.rawValue,
                keyCode: keyCode,
                flagsRawValue: flagsRawValue,
                marker: marker
            )
        }
        return decision.consume ? nil : Unmanaged.passUnretained(event)
    }
}
