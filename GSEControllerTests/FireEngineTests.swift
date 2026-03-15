import Testing
@testable import GSEController

// MARK: - Rate Clamping

@Suite struct RateClampingTests {
    @Test(arguments: [
        (0.0,   1.0),
        (-5.0,  1.0),
        (1.0,   1.0),
        (6.0,   1.0/6),
        (10.0,  1.0/10),
        (30.0,  1.0/30),
        (31.0,  1.0/30),
        (100.0, 1.0/30),
    ] as [(Double, Double)])
    func clampedIntervalBounds(rate: Double, expected: Double) {
        let result = FireEngine.clampedInterval(rate: rate)
        #expect(abs(result - expected) < 1e-9)
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
