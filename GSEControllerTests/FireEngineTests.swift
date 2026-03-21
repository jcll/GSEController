import Testing
@testable import GSEController

// MARK: - Rate Clamping

@Suite struct RateClampingTests {
    // TEST-10 fix: assert against known-correct constants, not derived values
    @Test func clampedIntervalAtSlow()     { #expect(abs(FireEngine.clampedInterval(rate: 6)  - (1.0/6))  < 1e-9) }
    @Test func clampedIntervalAtStandard() { #expect(abs(FireEngine.clampedInterval(rate: 10) - 0.1)      < 1e-9) }
    @Test func clampedIntervalAtFast()     { #expect(abs(FireEngine.clampedInterval(rate: 15) - (1.0/15)) < 1e-9) }
    @Test func clampedIntervalAtVeryFast() { #expect(abs(FireEngine.clampedInterval(rate: 20) - 0.05)     < 1e-9) }

    @Test(arguments: [
        (0.0,   1.0),
        (-5.0,  1.0),
        (1.0,   1.0),
        (31.0,  1.0/30),
        (100.0, 1.0/30),
    ] as [(Double, Double)])
    func clampedIntervalBoundaryBehavior(rate: Double, expected: Double) {
        let result = FireEngine.clampedInterval(rate: rate)
        #expect(abs(result - expected) < 1e-9)
    }
}

// MARK: - Timer Lifecycle

@Suite @MainActor struct TimerLifecycleTests {
    // startFiring creates a DispatchSourceTimer on fireQueue; KeySimulator.pressKey is a
    // no-op when the helper fd is -1 (not running), so tests are safe without side effects.

    @Test func startFiringSetsIsFiringTrue() {
        let engine = FireEngine()
        engine.startFiring(binding: MacroBinding(button: .rightShoulder))
        #expect(engine.isFiring == true)
        engine.stopAll()
    }

    @Test func stopFiringLastButtonSetsIsFiringFalse() {
        let engine = FireEngine()
        engine.startFiring(binding: MacroBinding(button: .rightShoulder))
        engine.stopFiring(button: .rightShoulder)
        #expect(engine.isFiring == false)
    }

    @Test func startFiringSameButtonTwiceIsIdempotent() {
        let engine = FireEngine()
        let binding = MacroBinding(button: .rightShoulder)
        engine.startFiring(binding: binding)
        engine.startFiring(binding: binding)
        engine.stopFiring(button: .rightShoulder)
        #expect(engine.isFiring == false)
    }

    @Test func stopFiringOneOfTwoButtonsKeepsIsFiringTrue() {
        let engine = FireEngine()
        engine.startFiring(binding: MacroBinding(button: .rightShoulder))
        engine.startFiring(binding: MacroBinding(button: .leftShoulder))
        engine.stopFiring(button: .rightShoulder)
        #expect(engine.isFiring == true)
        engine.stopAll()
    }

    @Test func stopAllSetsIsFiringFalse() {
        let engine = FireEngine()
        engine.startFiring(binding: MacroBinding(button: .rightShoulder))
        engine.startFiring(binding: MacroBinding(button: .leftShoulder))
        engine.stopAll()
        #expect(engine.isFiring == false)
    }
}

// MARK: - Modifier State

@Suite @MainActor struct ModifierStateTests {
    // Note: modifierDown/Up call KeySimulator.writeCommand which is a no-op when the
    // helper is not running (fd == -1, guard fd >= 0 exits early). Tests are safe.

    @Test func modifierDownAddsToSet() {
        let engine = FireEngine()
        engine.modifierDown(.alt)
        #expect(engine.heldModifiers.contains(.alt))
    }

    @Test func modifierUpRemovesFromSet() {
        let engine = FireEngine()
        engine.modifierDown(.alt)
        engine.modifierUp(.alt)
        #expect(!engine.heldModifiers.contains(.alt))
    }

    @Test func modifierDownTwiceDoesNotDuplicate() {
        let engine = FireEngine()
        engine.modifierDown(.alt)
        engine.modifierDown(.alt)
        #expect(engine.heldModifiers.count == 1)
    }

    @Test func modifierDownNoneIsNoOp() {
        let engine = FireEngine()
        engine.modifierDown(.none)
        #expect(engine.heldModifiers.isEmpty)
    }

    @Test func stopAllClearsModifiers() {
        let engine = FireEngine()
        engine.modifierDown(.alt)
        engine.modifierDown(.shift)
        engine.stopAll()
        #expect(engine.heldModifiers.isEmpty)
    }
}

// MARK: - wowIsActive lock (TEST-08)

@Suite @MainActor struct WoWIsActiveTests {
    @Test func wowIsActiveRoundTrips() {
        let engine = FireEngine()
        engine.wowIsActive = true
        #expect(engine.wowIsActive == true)
        engine.wowIsActive = false
        #expect(engine.wowIsActive == false)
    }

    @Test func requireWoWFocusRoundTrips() {
        let engine = FireEngine()
        engine.requireWoWFocus = false
        #expect(engine.requireWoWFocus == false)
        engine.requireWoWFocus = true
        #expect(engine.requireWoWFocus == true)
    }
}
