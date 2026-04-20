import Foundation
import Testing
@testable import GSEController

// KeySimulator unit tests intentionally stop at pure encoding/no-helper paths.
// Helper compilation, launchd, and TCC behavior are exercised through higher-
// level runtime tests and manual verification.
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
        let simulator = KeySimulator()
        simulator.modifierDown(.alt)
        simulator.modifierDown(.shift)
        simulator.modifierDown(.ctrl)
    }

    @Test func modifierUpIsNoOpBeforeHelperStarts() {
        let simulator = KeySimulator()
        simulator.modifierUp(.alt)
        simulator.modifierUp(.shift)
        simulator.modifierUp(.ctrl)
    }

    @Test func pressKeyIsNoOpBeforeHelperStarts() {
        let simulator = KeySimulator()
        simulator.pressKey(0x28) // K
        simulator.pressKey(0x00) // A
    }
}

// MARK: - Real Helper Smoke

@Suite struct RealHelperSmokeTests {
    @Test func ensureHelperCreatesArtifactsWhenEnabledInEnvironment() async {
        guard ProcessInfo.processInfo.environment["ENABLE_REAL_HELPER_TESTS"] == "1" else { return }
        let simulator = KeySimulator()
        defer { simulator.stopHelper() }

        let ready = await withCheckedContinuation { continuation in
            simulator.ensureHelper { ready in
                continuation.resume(returning: ready)
            }
        }

        #expect(ready)

        let diagnostics = simulator.diagnostics
        #expect(diagnostics.helperExists)
        #expect(diagnostics.launchAgentExists)
        #expect(diagnostics.fifoExists)
        #expect(diagnostics.responseFifoExists)
    }
}
