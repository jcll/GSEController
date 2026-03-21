import Testing
@testable import GSEController

@Suite struct CommandEncodingTests {
    @Test func pressReleaseTypeByteIsZero() {
        let result = KeySimulator.encodeCommand(type: 0, keyCode: 0)
        #expect(result[0] == 0)
    }

    @Test func keyDownTypeByteIsOne() {
        let result = KeySimulator.encodeCommand(type: 1, keyCode: 0)
        #expect(result[0] == 1)
    }

    @Test func keyUpTypeByteIsTwo() {
        let result = KeySimulator.encodeCommand(type: 2, keyCode: 0)
        #expect(result[0] == 2)
    }

    @Test func lowKeyCodeFitsInLoByte() {
        let result = KeySimulator.encodeCommand(type: 0, keyCode: 65)
        #expect(result[1] == 65)
        #expect(result[2] == 0)
    }

    @Test func keyCode256RequiresHiByte() {
        let result = KeySimulator.encodeCommand(type: 0, keyCode: 256)
        #expect(result[1] == 0)
        #expect(result[2] == 1)
    }

    @Test func keyCode300EncodesCorrectly() {
        // 300 = 0x012C: lo = 0x2C = 44, hi = 0x01 = 1
        let result = KeySimulator.encodeCommand(type: 0, keyCode: 300)
        #expect(result[1] == 44)
        #expect(result[2] == 1)
    }

    @Test func resultIsAlwaysFourBytes() {
        #expect(KeySimulator.encodeCommand(type: 0, keyCode: 0).count == 4)
        #expect(KeySimulator.encodeCommand(type: 1, keyCode: 65535).count == 4)
    }
}

// MARK: - Modifier Suppression (TEST-14)

@Suite struct ModifierSuppressionTests {
    // ensureHelper() is never called in the test environment, so _fd == -1.
    // modifierDown/modifierUp must be no-ops (no crash, no hang, no write).
    @Test func modifierDownIsNoOpBeforeHelperStarts() {
        KeySimulator.modifierDown(.alt)
        KeySimulator.modifierDown(.shift)
        KeySimulator.modifierDown(.ctrl)
    }

    @Test func modifierUpIsNoOpBeforeHelperStarts() {
        KeySimulator.modifierUp(.alt)
        KeySimulator.modifierUp(.shift)
        KeySimulator.modifierUp(.ctrl)
    }

    @Test func pressKeyIsNoOpBeforeHelperStarts() {
        KeySimulator.pressKey(0x28) // K
        KeySimulator.pressKey(0x00) // A
    }
}
