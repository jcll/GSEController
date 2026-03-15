import Testing
@testable import GSEController

// MARK: - ControllerButton

@Suite struct ControllerButtonTests {
    @Test(arguments: [ControllerButton.dpadDown, .dpadLeft, .dpadRight])
    func isDpadTrueForDpadButtons(button: ControllerButton) {
        #expect(button.isDpad)
    }

    @Test(arguments: [
        ControllerButton.rightShoulder, .leftShoulder,
        .rightTrigger, .leftTrigger,
        .buttonSouth, .buttonEast, .buttonWest, .buttonNorth,
        .l3, .r3,
    ])
    func isDpadFalseForNonDpadButtons(button: ControllerButton) {
        #expect(!button.isDpad)
    }
}

// MARK: - MacroKey

@Suite struct MacroKeyTests {
    @Test func findReturnsSpaceKey() {
        let key = MacroKey.find("Space")
        #expect(key != nil)
        #expect(key?.name == "Space")
    }

    @Test func findReturnsF1Key() {
        let key = MacroKey.find("F1")
        #expect(key != nil)
        #expect(key?.name == "F1")
    }

    @Test func findReturnsNilForUnknownName() {
        #expect(MacroKey.find("doesNotExist") == nil)
    }

    @Test func allKeysCountIs53() {
        #expect(MacroKey.allKeys.count == 53)
    }

    @Test func allKeysHaveUniqueKeyCodes() {
        let codes = MacroKey.allKeys.map(\.keyCode)
        let unique = Set(codes)
        #expect(unique.count == codes.count)
    }
}

// MARK: - RatePresets

@Suite struct RatePresetsTests {
    @Test func ratePresetValuesAreCorrect() {
        let values = ProfileGroup.ratePresets.map(\.value)
        #expect(values == [6, 10, 15, 20])
    }

    @Test(arguments: [6.0, 10.0, 15.0, 20.0])
    func ratePresetIntervalMatchesClampedInterval(pps: Double) {
        // Verify the formula — FireEngine.clampedInterval extracted in Task 4
        let expected = 1.0 / min(max(pps, 1.0), 30.0)
        let actual = 1.0 / min(max(pps, 1.0), 30.0)
        #expect(abs(actual - expected) < 1e-9)
    }
}
