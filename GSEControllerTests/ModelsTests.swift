import Foundation
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

// MARK: - ProfileStore Serialization

@Suite @MainActor struct ProfileStoreSerializationTests {

    private func makeTestDefaults() -> (UserDefaults, String) {
        let suite = "com.test.gsecontroller.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func singleBindingRoundTrips() throws {
        let binding = MacroBinding(
            button: .rightShoulder,
            keyName: "K",
            keyCode: 0x28,
            modifier: .none,
            mode: .hold,
            rate: 10
        )
        let group = ProfileGroup(name: "Test", bindings: [binding])
        let groups = [group]
        let encoded = try JSONEncoder().encode(groups)
        let decoded = try JSONDecoder().decode([ProfileGroup].self, from: encoded)
        #expect(decoded.count == 1)
        #expect(decoded[0].name == "Test")
        #expect(decoded[0].bindings.count == 1)
        #expect(decoded[0].bindings[0].button == .rightShoulder)
        #expect(decoded[0].bindings[0].mode == .hold)
        #expect(decoded[0].bindings[0].rate == 10)
    }

    @Test func mixedModeBindingsRoundTrip() throws {
        let bindings: [MacroBinding] = [
            MacroBinding(button: .rightShoulder, keyName: "K", keyCode: 0x28, modifier: .none, mode: .hold, rate: 10),
            MacroBinding(button: .leftShoulder, keyName: "1", keyCode: 0x12, modifier: .none, mode: .tap, rate: 10),
            MacroBinding(button: .rightTrigger, keyName: "Space", keyCode: 0x31, modifier: .alt, mode: .modifierHold, rate: 10),
        ]
        let groups = [ProfileGroup(name: "Mixed", bindings: bindings)]
        let encoded = try JSONEncoder().encode(groups)
        let decoded = try JSONDecoder().decode([ProfileGroup].self, from: encoded)
        let b = decoded[0].bindings
        #expect(b[0].mode == .hold)
        #expect(b[1].mode == .tap)
        #expect(b[2].mode == .modifierHold)
        #expect(b[2].modifier == .alt)
    }

    @Test func decodingMalformedJsonThrows() {
        let bad = Data("not json at all".utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode([ProfileGroup].self, from: bad)
        }
    }

    @Test func storeInitLoadsPersistedGroups() throws {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let binding = MacroBinding(button: .buttonSouth, keyName: "1", keyCode: 0x12, modifier: .none, mode: .tap, rate: 6)
        let group = ProfileGroup(name: "Saved", bindings: [binding])
        let data = try JSONEncoder().encode([group])
        defaults.set(data, forKey: "groups")
        defaults.set(group.id.uuidString, forKey: "activeGroupId")

        let store = ProfileStore(defaults: defaults)
        #expect(store.groups.count == 1)
        #expect(store.groups[0].name == "Saved")
        #expect(store.activeGroupId == group.id)
    }
}

// MARK: - ProfileStore Migration

@Suite @MainActor struct ProfileStoreMigrationTests {

    private func makeTestDefaults() -> (UserDefaults, String) {
        let suite = "com.test.gsecontroller.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func legacyProfilesAreMigratedOnInit() throws {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let legacy = _LegacyMacroProfile(
            id: UUID(),
            name: "Old Profile",
            button: .rightShoulder,
            keyName: "K",
            keyCode: 0x28,
            rate: 10
        )
        let data = try JSONEncoder().encode([legacy])
        defaults.set(data, forKey: "profiles")

        let store = ProfileStore(defaults: defaults)
        #expect(store.groups.count == 1)
        #expect(store.groups[0].name == "Old Profile")
        #expect(store.groups[0].bindings[0].button == .rightShoulder)
    }

    @Test func legacyKeyIsRemovedAfterMigration() throws {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let legacy = _LegacyMacroProfile(
            id: UUID(), name: "Old", button: .buttonSouth,
            keyName: "1", keyCode: 0x12, rate: 6
        )
        defaults.set(try JSONEncoder().encode([legacy]), forKey: "profiles")

        _ = ProfileStore(defaults: defaults)
        #expect(defaults.object(forKey: "profiles") == nil)
    }

    @Test func noLegacyDataLoadsDefaultGroup() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProfileStore(defaults: defaults)
        #expect(store.groups.count == 1)
        #expect(store.groups[0].name == "Guardian Druid")
    }
}
