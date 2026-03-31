import Testing
@testable import GSEController

private final class MockKeyInjector: KeyInjecting, @unchecked Sendable {
    var isAccessibilityEnabled = true
    var isHelperAccessibilityEnabled = true
    var events: [String] = []

    func ensureHelper(onComplete: (@MainActor (Bool) -> Void)?) {
        if let onComplete {
            Task { @MainActor in onComplete(true) }
        }
    }

    func pressKey(_ keyCode: UInt16) {
        events.append("press:\(keyCode)")
    }

    func modifierDown(_ modifier: KeyModifier) {
        events.append("down:\(modifier.rawValue)")
    }

    func modifierUp(_ modifier: KeyModifier) {
        events.append("up:\(modifier.rawValue)")
    }

    func requestAccessibility() {}
    func openAccessibilitySettings() {}
    func revealHelperInFinder() {}
    func stopHelper() {}
}

// MARK: - Rate Clamping

@Suite struct RateClampingTests {
    // Preset tests — rate is now in milliseconds
    @Test func clampedIntervalAtSlow()      { #expect(abs(FireEngine.clampedInterval(rateMs: 340) - 0.34)  < 1e-9) }
    @Test func clampedIntervalAtModerate()  { #expect(abs(FireEngine.clampedInterval(rateMs: 300) - 0.3)   < 1e-9) }
    @Test func clampedIntervalAtStandard()  { #expect(abs(FireEngine.clampedInterval(rateMs: 250) - 0.25)  < 1e-9) }
    @Test func clampedIntervalAtFast()      { #expect(abs(FireEngine.clampedInterval(rateMs: 200) - 0.2)   < 1e-9) }
    @Test func clampedIntervalAtVeryFast()  { #expect(abs(FireEngine.clampedInterval(rateMs: 150) - 0.15)  < 1e-9) }
    @Test func clampedIntervalAtUltraFast() { #expect(abs(FireEngine.clampedInterval(rateMs: 100) - 0.1)   < 1e-9) }

    @Test(arguments: [
        (0.0,    0.033),   // below min clamps to 33ms
        (-5.0,   0.033),   // negative clamps to 33ms
        (33.0,   0.033),   // exact min boundary
        (1001.0, 1.0),     // above max clamps to 1000ms
        (2000.0, 1.0),     // well above max
    ] as [(Double, Double)])
    func clampedIntervalBoundaryBehavior(rateMs: Double, expected: Double) {
        let result = FireEngine.clampedInterval(rateMs: rateMs)
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

    @Test func rapidBindingModifierHeldUntilStop() {
        let injector = MockKeyInjector()
        let engine = FireEngine(keyInjector: injector)
        engine.startFiring(binding: MacroBinding(button: .rightShoulder, modifier: .alt, mode: .hold))

        #expect(engine.heldModifiers.contains(.alt))
        #expect(injector.events.contains("down:alt"))

        engine.stopFiring(button: .rightShoulder)
        #expect(!engine.heldModifiers.contains(.alt))
        #expect(injector.events.contains("up:alt"))
    }

    @Test func tapBindingAppliesModifierAroundPress() {
        let injector = MockKeyInjector()
        let engine = FireEngine(keyInjector: injector)
        engine.tap(binding: MacroBinding(button: .rightShoulder, keyCode: 0x28, modifier: .shift, mode: .tap))

        #expect(injector.events == ["down:shift", "press:40", "up:shift"])
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
