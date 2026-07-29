import CoreGraphics
import XCTest

@testable import dict8

final class PhaseSevenHotkeyTests: XCTestCase {
    private let leftControl: Int64 = 59
    private let rightControl: Int64 = 62
    private let leftOption: Int64 = 58
    private let rightOption: Int64 = 61
    private let command: Int64 = 55
    private let v: Int64 = 9

    func testPushToTalkConsumesOnlyChordCompletingModifierAndItsRelease() {
        var machine = HotkeyStateMachine()
        machine.arm(initialFlagsRawValue: 0)

        XCTAssertEqual(flags(&machine, leftControl, [.maskControl]), .pass)
        XCTAssertEqual(
            flags(&machine, leftOption, [.maskControl, .maskAlternate]),
            HotkeyDecision(consume: true, actions: [.pushToTalkPressed])
        )
        XCTAssertEqual(
            flags(&machine, leftControl, [.maskAlternate]),
            HotkeyDecision(consume: false, actions: [.pushToTalkReleased])
        )
        XCTAssertEqual(
            flags(&machine, leftOption, []),
            HotkeyDecision(consume: true, actions: [])
        )
    }

    func testReverseOrderAndRightSideModifiersRemainBalanced() {
        var machine = HotkeyStateMachine()
        machine.arm(initialFlagsRawValue: 0)

        XCTAssertEqual(flags(&machine, rightOption, [.maskAlternate]), .pass)
        XCTAssertEqual(
            flags(&machine, rightControl, [.maskControl, .maskAlternate]),
            HotkeyDecision(consume: true, actions: [.pushToTalkPressed])
        )
        XCTAssertEqual(
            flags(&machine, rightControl, [.maskAlternate]),
            HotkeyDecision(consume: true, actions: [.pushToTalkReleased])
        )
        XCTAssertEqual(flags(&machine, rightOption, []), .pass)
    }

    func testDuplicateEventsDoNotDuplicatePressOrRelease() {
        var machine = HotkeyStateMachine()
        machine.arm(initialFlagsRawValue: 0)
        _ = flags(&machine, leftControl, [.maskControl])

        XCTAssertEqual(
            flags(&machine, leftOption, [.maskControl, .maskAlternate]).actions,
            [.pushToTalkPressed]
        )
        XCTAssertTrue(flags(&machine, leftOption, [.maskControl, .maskAlternate]).actions.isEmpty)
        XCTAssertEqual(
            flags(&machine, leftOption, [.maskControl]).actions,
            [.pushToTalkReleased]
        )
        XCTAssertTrue(flags(&machine, leftOption, [.maskControl]).actions.isEmpty)
        _ = flags(&machine, leftControl, [])
    }

    func testCommandOrShiftRejectExactChordWhileCapsLockAndFnAreAllowed() {
        var rejected = HotkeyStateMachine()
        rejected.arm(initialFlagsRawValue: 0)
        _ = flags(&rejected, leftControl, [.maskControl])
        XCTAssertTrue(
            flags(
                &rejected,
                leftOption,
                [.maskControl, .maskAlternate, .maskCommand]
            ).actions.isEmpty
        )

        var allowed = HotkeyStateMachine()
        allowed.arm(initialFlagsRawValue: 0)
        _ = flags(&allowed, leftControl, [.maskControl, .maskAlphaShift])
        let decision = flags(
            &allowed,
            leftOption,
            [.maskControl, .maskAlternate, .maskAlphaShift, .maskSecondaryFn]
        )
        XCTAssertEqual(decision.actions, [.pushToTalkPressed])
    }

    func testAddingCommandReleasesActiveChordWithoutConsumingCommand() {
        var machine = HotkeyStateMachine()
        machine.arm(initialFlagsRawValue: 0)
        _ = flags(&machine, leftControl, [.maskControl])
        _ = flags(&machine, leftOption, [.maskControl, .maskAlternate])

        XCTAssertEqual(
            flags(
                &machine,
                command,
                [.maskControl, .maskAlternate, .maskCommand]
            ),
            HotkeyDecision(consume: false, actions: [.pushToTalkReleased])
        )
    }

    func testInterruptionReleasesOnceAndRequiresFullReleaseBeforeRearming() {
        var machine = HotkeyStateMachine()
        machine.arm(initialFlagsRawValue: 0)
        _ = flags(&machine, leftControl, [.maskControl])
        _ = flags(&machine, leftOption, [.maskControl, .maskAlternate])

        XCTAssertEqual(machine.interrupt(), [.pushToTalkReleased])
        XCTAssertTrue(flags(&machine, leftOption, [.maskControl, .maskAlternate]).actions.isEmpty)
        _ = flags(&machine, leftOption, [.maskControl])
        _ = flags(&machine, leftControl, [])
        _ = flags(&machine, leftControl, [.maskControl])
        XCTAssertEqual(
            flags(&machine, leftOption, [.maskControl, .maskAlternate]).actions,
            [.pushToTalkPressed]
        )
    }

    func testArmingWhileHeldWaitsForFullRelease() {
        var machine = HotkeyStateMachine()
        machine.arm(initialFlagsRawValue: flagsRaw([.maskControl, .maskAlternate]))

        XCTAssertTrue(flags(&machine, leftOption, [.maskControl, .maskAlternate]).actions.isEmpty)
        _ = flags(&machine, leftOption, [.maskControl])
        _ = flags(&machine, leftControl, [])
        _ = flags(&machine, leftOption, [.maskAlternate])
        XCTAssertEqual(
            flags(&machine, leftControl, [.maskControl, .maskAlternate]).actions,
            [.pushToTalkPressed]
        )
    }

    func testPasteLastFiresOnceAfterWholeChordIsReleased() {
        var machine = HotkeyStateMachine()
        machine.arm(initialFlagsRawValue: 0)
        let modifiers: CGEventFlags = [.maskCommand, .maskControl]

        XCTAssertTrue(key(&machine, .keyDown, v, modifiers).consume)
        XCTAssertTrue(key(&machine, .keyUp, v, modifiers).consume)
        XCTAssertTrue(flags(&machine, command, [.maskControl]).actions.isEmpty)
        XCTAssertEqual(flags(&machine, leftControl, []).actions, [.pasteLast])
        XCTAssertTrue(flags(&machine, leftControl, []).actions.isEmpty)
    }

    func testSyntheticPasteAndUnrelatedKeysPassThrough() {
        var machine = HotkeyStateMachine()
        machine.arm(initialFlagsRawValue: 0)
        let synthetic = machine.process(
            typeRawValue: CGEventType.keyDown.rawValue,
            keyCode: v,
            flagsRawValue: flagsRaw([.maskCommand, .maskControl]),
            marker: SystemPasteEventPoster.syntheticEventMarker
        )
        XCTAssertEqual(synthetic, .pass)

        _ = flags(&machine, leftControl, [.maskControl])
        _ = flags(&machine, leftOption, [.maskControl, .maskAlternate])
        XCTAssertEqual(key(&machine, .keyDown, 0, [.maskControl, .maskAlternate]), .pass)
    }

    func testLeftMouseEventsStripChordModifiersWithoutBeingConsumed() {
        var machine = HotkeyStateMachine()
        machine.arm(initialFlagsRawValue: 0)
        _ = flags(&machine, leftControl, [.maskControl])
        _ = flags(&machine, leftOption, [.maskControl, .maskAlternate])

        for type in [
            CGEventType.leftMouseDown,
            CGEventType.leftMouseDragged,
            CGEventType.leftMouseUp,
        ] {
            let decision = mouse(
                &machine,
                type,
                [.maskControl, .maskAlternate, .maskShift, .maskAlphaShift]
            )
            XCTAssertFalse(decision.consume)
            XCTAssertTrue(decision.actions.isEmpty)
            XCTAssertEqual(
                decision.flagsForDelivery(
                    [.maskControl, .maskAlternate, .maskShift, .maskAlphaShift]
                ),
                [.maskShift, .maskAlphaShift]
            )
        }
    }

    func testLeftMouseEventsRemainUnchangedOutsideActiveChord() {
        var machine = HotkeyStateMachine()
        machine.arm(initialFlagsRawValue: 0)
        let modifiers: CGEventFlags = [.maskControl, .maskAlternate]

        let beforeChord = mouse(&machine, .leftMouseDown, modifiers)
        XCTAssertEqual(beforeChord, .pass)
        XCTAssertEqual(beforeChord.flagsForDelivery(modifiers), modifiers)

        _ = flags(&machine, leftControl, [.maskControl])
        _ = flags(&machine, leftOption, [.maskControl, .maskAlternate])
        _ = flags(&machine, leftOption, [.maskControl])
        _ = flags(&machine, leftControl, [])

        let afterRelease = mouse(&machine, .leftMouseDown, modifiers)
        XCTAssertEqual(afterRelease, .pass)
        XCTAssertEqual(afterRelease.flagsForDelivery(modifiers), modifiers)
    }

    func testNonLeftMouseEventsAreNeverModified() {
        var machine = HotkeyStateMachine()
        machine.arm(initialFlagsRawValue: 0)
        _ = flags(&machine, leftControl, [.maskControl])
        _ = flags(&machine, leftOption, [.maskControl, .maskAlternate])
        let modifiers: CGEventFlags = [.maskControl, .maskAlternate]

        for type in [
            CGEventType.rightMouseDown,
            CGEventType.rightMouseUp,
            CGEventType.otherMouseDown,
            CGEventType.otherMouseUp,
            CGEventType.mouseMoved,
            CGEventType.scrollWheel,
        ] {
            let decision = mouse(&machine, type, modifiers)
            XCTAssertEqual(decision, .pass)
            XCTAssertEqual(decision.flagsForDelivery(modifiers), modifiers)
        }
    }

    private func flags(
        _ machine: inout HotkeyStateMachine,
        _ keyCode: Int64,
        _ flags: CGEventFlags
    ) -> HotkeyDecision {
        machine.process(
            typeRawValue: CGEventType.flagsChanged.rawValue,
            keyCode: keyCode,
            flagsRawValue: flags.rawValue,
            marker: 0
        )
    }

    private func key(
        _ machine: inout HotkeyStateMachine,
        _ type: CGEventType,
        _ keyCode: Int64,
        _ flags: CGEventFlags
    ) -> HotkeyDecision {
        machine.process(
            typeRawValue: type.rawValue,
            keyCode: keyCode,
            flagsRawValue: flags.rawValue,
            marker: 0
        )
    }

    private func mouse(
        _ machine: inout HotkeyStateMachine,
        _ type: CGEventType,
        _ flags: CGEventFlags
    ) -> HotkeyDecision {
        machine.process(
            typeRawValue: type.rawValue,
            keyCode: 0,
            flagsRawValue: flags.rawValue,
            marker: 0
        )
    }

    private func flagsRaw(_ flags: CGEventFlags) -> UInt64 {
        flags.rawValue
    }
}
