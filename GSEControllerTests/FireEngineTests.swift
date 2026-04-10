import Foundation
import Testing
@testable import GSEController

// FireEngine tests stay in-process by substituting a recording injector for the
// real helper/FIFO path. That keeps timer, focus, and modifier behavior fast
// and deterministic.
private final class MockKeyInjector: KeyInjecting, @unchecked Sendable {
    var isAccessibilityEnabled = true
    var isHelperAccessibilityEnabled = true
    var diagnostics = KeyHelperDiagnostics(
        helperPath: "/tmp/keyhelper",
        launchAgentPath: "/tmp/keyhelper.plist",
        launchAgentLabel: "test.helper",
        fifoPath: "/tmp/keyfifo",
        responseFifoPath: "/tmp/keyfifo-response",
        logPath: "/tmp/helper.log",
        helperExists: true,
        launchAgentExists: true,
        fifoExists: true,
        responseFifoExists: true
    )
    private let lock = NSLock()
    private var recordedEvents: [String] = []
    var events: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedEvents
    }

    func ensureHelper(onComplete: (@MainActor (Bool) -> Void)?) {
        if let onComplete {
            Task { @MainActor in onComplete(true) }
        }
    }

    func pressKey(_ keyCode: UInt16) {
        record("press:\(keyCode)")
    }

    func modifierDown(_ modifier: KeyModifier) {
        record("down:\(modifier.rawValue)")
    }

    func modifierUp(_ modifier: KeyModifier) {
        record("up:\(modifier.rawValue)")
    }

    func requestAccessibility() {}
    func requestHelperAccessibility() {}
    func openAccessibilitySettings() {}
    func revealHelperInFinder() {}
    func stopHelper() {}

    private func record(_ event: String) {
        lock.lock()
        defer { lock.unlock() }
        recordedEvents.append(event)
    }
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
    // startFiring creates a DispatchSourceTimer on fireQueue; use a mock injector
    // so tests stay isolated from the real key-helper FIFO.

    @Test func startFiringSetsIsFiringTrue() {
        let engine = FireEngine(keyInjector: MockKeyInjector())
        engine.requireWoWFocus = false
        engine.startFiring(binding: MacroBinding(button: .rightShoulder))
        #expect(engine.isFiring == true)
        engine.stopAll()
    }

    @Test func stopFiringLastButtonSetsIsFiringFalse() {
        let engine = FireEngine(keyInjector: MockKeyInjector())
        engine.requireWoWFocus = false
        engine.startFiring(binding: MacroBinding(button: .rightShoulder))
        engine.stopFiring(button: .rightShoulder)
        #expect(engine.isFiring == false)
    }

    @Test func startFiringSameButtonTwiceIsIdempotent() {
        let engine = FireEngine(keyInjector: MockKeyInjector())
        engine.requireWoWFocus = false
        let binding = MacroBinding(button: .rightShoulder)
        engine.startFiring(binding: binding)
        engine.startFiring(binding: binding)
        engine.stopFiring(button: .rightShoulder)
        #expect(engine.isFiring == false)
    }

    @Test func stopFiringOneOfTwoButtonsKeepsIsFiringTrue() {
        let engine = FireEngine(keyInjector: MockKeyInjector())
        engine.requireWoWFocus = false
        engine.startFiring(binding: MacroBinding(button: .rightShoulder))
        engine.startFiring(binding: MacroBinding(button: .leftShoulder))
        engine.stopFiring(button: .rightShoulder)
        #expect(engine.isFiring == true)
        engine.stopAll()
    }

    @Test func stopAllSetsIsFiringFalse() {
        let engine = FireEngine(keyInjector: MockKeyInjector())
        engine.requireWoWFocus = false
        engine.startFiring(binding: MacroBinding(button: .rightShoulder))
        engine.startFiring(binding: MacroBinding(button: .leftShoulder))
        engine.stopAll()
        #expect(engine.isFiring == false)
    }
}

// MARK: - Modifier State

@Suite @MainActor struct ModifierStateTests {
    // Use a mock injector so modifier state tests stay isolated from the real helper.

    @Test func modifierDownAddsToSet() {
        let engine = FireEngine(keyInjector: MockKeyInjector())
        engine.requireWoWFocus = false
        engine.modifierDown(.alt)
        #expect(engine.heldModifiers.contains(.alt))
    }

    @Test func modifierUpRemovesFromSet() {
        let engine = FireEngine(keyInjector: MockKeyInjector())
        engine.requireWoWFocus = false
        engine.modifierDown(.alt)
        engine.modifierUp(.alt)
        #expect(!engine.heldModifiers.contains(.alt))
    }

    @Test func modifierDownTwiceDoesNotDuplicate() {
        let engine = FireEngine(keyInjector: MockKeyInjector())
        engine.requireWoWFocus = false
        engine.modifierDown(.alt)
        engine.modifierDown(.alt)
        #expect(engine.heldModifiers.count == 1)
    }

    @Test func modifierDownNoneIsNoOp() {
        let engine = FireEngine(keyInjector: MockKeyInjector())
        engine.modifierDown(.none)
        #expect(engine.heldModifiers.isEmpty)
    }

    @Test func stopAllClearsModifiers() {
        let engine = FireEngine(keyInjector: MockKeyInjector())
        engine.requireWoWFocus = false
        engine.modifierDown(.alt)
        engine.modifierDown(.shift)
        engine.stopAll()
        #expect(engine.heldModifiers.isEmpty)
    }

    @Test func rapidBindingModifierHeldUntilStop() {
        let injector = MockKeyInjector()
        let engine = FireEngine(keyInjector: injector)
        engine.requireWoWFocus = false
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
        engine.requireWoWFocus = false
        engine.tap(binding: MacroBinding(button: .rightShoulder, keyCode: 0x28, modifier: .shift, mode: .tap))

        #expect(injector.events == ["down:shift", "press:40", "up:shift"])
    }
}

// MARK: - Focus Guard

@Suite @MainActor struct FocusGuardTests {
    @Test func tapBindingDoesNotFireWhenWoWFocusIsRequiredAndInactive() {
        let injector = MockKeyInjector()
        let engine = FireEngine(keyInjector: injector)
        engine.requireWoWFocus = true
        engine.wowIsActive = false

        engine.tap(binding: MacroBinding(button: .rightShoulder, keyCode: 0x28, modifier: .shift, mode: .tap))

        #expect(injector.events.isEmpty)
        #expect(engine.heldModifiers.isEmpty)
    }

    @Test func tapBindingFiresWhenWoWFocusIsRequiredAndActive() {
        let injector = MockKeyInjector()
        let engine = FireEngine(keyInjector: injector)
        engine.requireWoWFocus = true
        engine.wowIsActive = true

        engine.tap(binding: MacroBinding(button: .rightShoulder, keyCode: 0x28, modifier: .shift, mode: .tap))

        #expect(injector.events == ["down:shift", "press:40", "up:shift"])
    }

    @Test func modifierHoldDoesNotPressWhenWoWFocusIsRequiredAndInactive() {
        let injector = MockKeyInjector()
        let engine = FireEngine(keyInjector: injector)
        engine.requireWoWFocus = true
        engine.wowIsActive = false

        engine.modifierDown(.alt)

        #expect(injector.events.isEmpty)
        #expect(engine.heldModifiers.isEmpty)
    }

    @Test func rapidBindingDoesNotStartWhenWoWFocusIsRequiredAndInactive() {
        let injector = MockKeyInjector()
        let engine = FireEngine(keyInjector: injector)
        engine.requireWoWFocus = true
        engine.wowIsActive = false

        engine.startFiring(binding: MacroBinding(button: .rightShoulder, keyCode: 0x28, modifier: .shift, mode: .hold))

        #expect(!engine.isFiring)
        #expect(injector.events.isEmpty)
        #expect(engine.heldModifiers.isEmpty)
    }

    @Test func focusLossReleasesHeldModifiers() {
        let injector = MockKeyInjector()
        let engine = FireEngine(keyInjector: injector)
        engine.requireWoWFocus = false
        engine.modifierDown(.alt)

        engine.requireWoWFocus = true
        engine.wowIsActive = false

        #expect(injector.events == ["down:alt", "up:alt"])
        #expect(engine.heldModifiers.isEmpty)
    }

    @Test func accessibilityRevocationBlocksImmediateTap() {
        let injector = MockKeyInjector()
        injector.isAccessibilityEnabled = false
        let engine = FireEngine(keyInjector: injector)
        var revoked = false
        engine.onAccessibilityRevoked = { revoked = true }

        engine.tap(binding: MacroBinding(button: .rightShoulder, keyCode: 0x28, mode: .tap))

        #expect(injector.events.isEmpty)
        #expect(revoked)
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
