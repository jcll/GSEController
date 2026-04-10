import Foundation
import Testing
@testable import GSEController

// Model tests document the persistence contract: stable raw values, legacy
// migrations, preset constants, and the profile-store behaviors other layers
// assume are already correct.
// MARK: - ControllerButton

@Suite struct ControllerButtonTests {
    @Test(arguments: [ControllerButton.dpadDown, .dpadLeft, .dpadRight, .dpadUp])
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

    @Test func legacyDisplayStringRawValuesDecodeCorrectly() throws {
        // Verify migration handles all 10 pre-ARCH-04 display-string raw values.
        let pairs: [(String, ControllerButton)] = [
            ("R1", .rightShoulder), ("L1", .leftShoulder),
            ("R2", .rightTrigger),  ("L2", .leftTrigger),
            ("A / Cross", .buttonSouth), ("B / Circle", .buttonEast),
            ("X / Square", .buttonWest), ("Y / Triangle", .buttonNorth),
            ("L3", .l3), ("R3", .r3),
            // BUG-07: D-pad legacy display strings added in migration fix
            ("D-Pad ↓", .dpadDown), ("D-Pad ←", .dpadLeft),
            ("D-Pad →", .dpadRight), ("D-Pad ↑", .dpadUp),
        ]
        for (raw, expected) in pairs {
            let data = try JSONEncoder().encode(raw)
            let decoded = try JSONDecoder().decode(ControllerButton.self, from: data)
            #expect(decoded == expected, "Legacy raw value '\(raw)' should decode to \(expected)")
        }
    }

    @Test func unknownRawValueThrowsDecodingError() {
        let data = try! JSONEncoder().encode("TotallyBogus")
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(ControllerButton.self, from: data)
        }
    }

    @Test func camelCaseRawValuesRoundTrip() throws {
        for button in ControllerButton.allCases {
            let data = try JSONEncoder().encode(button)
            let decoded = try JSONDecoder().decode(ControllerButton.self, from: data)
            #expect(decoded == button)
        }
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

    // TEST-09: byName must not silently shadow duplicate-named keys
    @Test func byNameCountMatchesAllKeysCount() {
        #expect(MacroKey.byName.count == MacroKey.allKeys.count,
                "Duplicate key names detected — byName.count != allKeys.count")
    }
}

// MARK: - KeyModifier

// TEST-11: Virtual key code constants — a transposition would break modifier mode silently.
@Suite struct KeyModifierTests {
    @Test func altKeyCode() { #expect(KeyModifier.alt.keyCode == 0x3A) }
    @Test func shiftKeyCode() { #expect(KeyModifier.shift.keyCode == 0x38) }
    @Test func ctrlKeyCode() { #expect(KeyModifier.ctrl.keyCode == 0x3B) }
    @Test func noneKeyCodeIsZero() { #expect(KeyModifier.none.keyCode == 0) }
}

// MARK: - RatePresets

@Suite struct RatePresetsTests {
    // TEST-10: Assert each preset label and value against hardcoded expected constants.
    @Test func ratePresetValuesAreCorrect() {
        let values = ProfileGroup.ratePresets.map(\.value)
        #expect(values == [340, 300, 250, 200, 150, 100])
    }

    @Test func ratePresetLabelsAreCorrect() {
        let labels = ProfileGroup.ratePresets.map(\.label)
        #expect(labels == ["Slow", "Moderate", "Standard", "Fast", "Very Fast", "Ultra Fast"])
    }

    @Test func slowPresetIsCorrect() {
        let preset = ProfileGroup.ratePresets.first { $0.label == "Slow" }
        #expect(preset?.value == 340)
    }

    @Test func moderatePresetIsCorrect() {
        let preset = ProfileGroup.ratePresets.first { $0.label == "Moderate" }
        #expect(preset?.value == 300)
    }

    @Test func standardPresetIsCorrect() {
        let preset = ProfileGroup.ratePresets.first { $0.label == "Standard" }
        #expect(preset?.value == 250)
    }

    @Test func fastPresetIsCorrect() {
        let preset = ProfileGroup.ratePresets.first { $0.label == "Fast" }
        #expect(preset?.value == 200)
    }

    @Test func veryFastPresetIsCorrect() {
        let preset = ProfileGroup.ratePresets.first { $0.label == "Very Fast" }
        #expect(preset?.value == 150)
    }

    @Test func ultraFastPresetIsCorrect() {
        let preset = ProfileGroup.ratePresets.first { $0.label == "Ultra Fast" }
        #expect(preset?.value == 100)
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
            rate: 250
        )
        let group = ProfileGroup(name: "Test", bindings: [binding], notes: "Use K on bar 1")
        let groups = [group]
        let encoded = try JSONEncoder().encode(groups)
        let decoded = try JSONDecoder().decode([ProfileGroup].self, from: encoded)
        #expect(decoded.count == 1)
        #expect(decoded[0].name == "Test")
        #expect(decoded[0].notes == "Use K on bar 1")
        #expect(decoded[0].bindings.count == 1)
        #expect(decoded[0].bindings[0].button == .rightShoulder)
        #expect(decoded[0].bindings[0].mode == .hold)
        #expect(decoded[0].bindings[0].rate == 250)
    }

    @Test func decodingLegacyGroupWithoutNotesDefaultsToEmptyString() throws {
        let json = """
        [{
          "id": "00000000-0000-0000-0000-000000000111",
          "name": "Legacy",
          "bindings": []
        }]
        """

        let decoded = try JSONDecoder().decode([ProfileGroup].self, from: Data(json.utf8))

        #expect(decoded[0].notes == "")
    }

    @Test func mixedModeBindingsRoundTrip() throws {
        let bindings: [MacroBinding] = [
            MacroBinding(button: .rightShoulder, keyName: "K", keyCode: 0x28, modifier: .none, mode: .hold, rate: 250),
            MacroBinding(button: .leftShoulder, keyName: "1", keyCode: 0x12, modifier: .none, mode: .tap, rate: 250),
            MacroBinding(button: .rightTrigger, keyName: "Space", keyCode: 0x31, modifier: .alt, mode: .modifierHold, rate: 250),
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
        // rate: 6 (pps) migrates to round(1000/6) = 167ms
        #expect(store.groups[0].bindings[0].rate == 167)
    }

    // TEST-08: Stale activeGroupId references a deleted group — must fall back to groups.first.
    @Test func staleActiveGroupIdFallsBackToFirst() throws {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let group = ProfileGroup(name: "Real", bindings: [])
        let data = try JSONEncoder().encode([group])
        defaults.set(data, forKey: "groups")
        defaults.set(UUID().uuidString, forKey: "activeGroupId") // non-existent ID

        let store = ProfileStore(defaults: defaults)
        #expect(store.activeGroupId == group.id)
    }
}

// MARK: - ProfileStore Mutation (TEST-07)

@Suite @MainActor struct ProfileStoreMutationTests {

    private func makeTestDefaults() -> (UserDefaults, String) {
        let suite = "com.test.gsecontroller.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func deleteActiveGroupFallsBackToFirst() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProfileStore(defaults: defaults)
        let first = store.groups[0]
        let second = ProfileGroup(name: "Second", bindings: [])
        store.addGroup(second)
        store.activeGroupId = second.id

        store.deleteGroup(second)
        #expect(store.activeGroupId == first.id)
    }

    @Test func deleteLastGroupSetsActiveToNil() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProfileStore(defaults: defaults)
        // Replace groups with a single group, then delete it
        let solo = ProfileGroup(name: "Solo", bindings: [])
        store.groups = [solo]
        store.activeGroupId = solo.id

        store.deleteGroup(solo)
        #expect(store.activeGroupId == nil)
    }

    @Test func deleteNonActiveGroupDoesNotChangeActiveId() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProfileStore(defaults: defaults)
        let first = store.groups[0]
        let second = ProfileGroup(name: "Second", bindings: [])
        store.addGroup(second)
        store.activeGroupId = first.id

        store.deleteGroup(second)
        #expect(store.activeGroupId == first.id)
    }

    @Test func duplicateGroupCreatesFreshIDsAndUniqueCopyName() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProfileStore(defaults: defaults)
        let original = store.groups[0]

        let firstCopy = store.duplicateGroup(original)
        let secondCopy = store.duplicateGroup(original)

        #expect(firstCopy.id != original.id)
        #expect(firstCopy.bindings.map(\.id) != original.bindings.map(\.id))
        #expect(firstCopy.name == "\(original.name) Copy")
        #expect(secondCopy.name == "\(original.name) Copy 2")
        #expect(store.activeGroupId == secondCopy.id)
    }
}

// MARK: - ProfileStore Import Recovery

@Suite @MainActor struct ProfileStoreImportRecoveryTests {
    private func makeTestDefaults() -> (UserDefaults, String) {
        let suite = "com.test.gsecontroller.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func emptyImportThrowsHelpfulError() throws {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProfileStore(defaults: defaults)
        let emptyData = try JSONEncoder().encode([ProfileGroup]())

        #expect(throws: ProfileStoreError.emptyImport) {
            try store.importData(emptyData)
        }
    }

    @Test func corruptStoredGroupsAreBackedUp() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let corrupt = Data("nope".utf8)
        defaults.set(corrupt, forKey: "groups")

        _ = ProfileStore(defaults: defaults)
        #expect(defaults.data(forKey: "groups_backup") == corrupt)
    }

    @Test func importPreservesActiveGroupWhenSameIDExists() throws {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let sharedID = UUID()
        let original = ProfileGroup(id: sharedID, name: "Original", bindings: [])
        let store = ProfileStore(defaults: defaults)
        store.groups = [original]
        store.activeGroupId = sharedID

        let replacement = ProfileGroup(id: sharedID, name: "Imported", bindings: [MacroBinding(button: .leftShoulder)])
        try store.importData(JSONEncoder().encode([replacement]))

        #expect(store.activeGroupId == sharedID)
        #expect(store.activeGroup?.name == "Imported")
    }

    @Test func mergeImportAppendsFreshCopiesWithoutReplacingExistingGroups() throws {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProfileStore(defaults: defaults)
        let original = store.groups[0]
        let imported = ProfileGroup(id: original.id, name: original.name, bindings: [
            MacroBinding(button: .leftShoulder),
        ])

        try store.importData(JSONEncoder().encode([imported]), mode: .merge)

        #expect(store.groups.count == 2)
        #expect(store.groups[0].id == original.id)
        #expect(store.groups[1].id != original.id)
        #expect(store.groups[1].name == "\(original.name) 2")
        #expect(store.activeGroupId == store.groups[1].id)
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
        // rate: 10 (pps) migrates to round(1000/10) = 100ms
        #expect(store.groups[0].bindings[0].rate == 100)
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

// MARK: - activeGroup (TEST-06)

@Suite @MainActor struct ActiveGroupTests {
    private func makeTestDefaults() -> (UserDefaults, String) {
        let suite = "com.test.gsecontroller.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func activeGroupReturnsMatchingGroup() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProfileStore(defaults: defaults)
        let group = store.groups[0]
        store.activeGroupId = group.id
        #expect(store.activeGroup?.id == group.id)
    }

    @Test func activeGroupReturnsNilWhenActiveGroupIdIsNil() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProfileStore(defaults: defaults)
        store.activeGroupId = nil
        #expect(store.activeGroup == nil)
    }

    @Test func activeGroupReturnsNilForNonExistentId() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProfileStore(defaults: defaults)
        store.activeGroupId = UUID()
        #expect(store.activeGroup == nil)
    }
}

// MARK: - MacroBinding Equatable (TEST-07)

@Suite struct MacroBindingEquatableTests {
    @Test func copyIsEqualToOriginal() {
        let a = MacroBinding(button: .rightShoulder, mode: .hold)
        let b = a
        #expect(a == b)
    }

    @Test func modifiedCopyIsNotEqual() {
        var a = MacroBinding(button: .rightShoulder, mode: .hold)
        var b = a
        b.mode = .tap
        #expect(a != b)
    }

    @Test func differentButtonIsNotEqual() {
        var a = MacroBinding(button: .rightShoulder, mode: .hold)
        var b = a
        b.button = .leftShoulder
        #expect(a != b)
    }

    @Test func differentLabelIsNotEqual() {
        var a = MacroBinding(button: .rightShoulder, mode: .hold, label: "Rotation")
        var b = a
        b.label = "Other"
        #expect(a != b)
    }
}

// MARK: - ProfileGroup Helpers

@Suite struct ProfileGroupHelperTests {
    @Test func duplicateButtonsDetectsConflicts() {
        let group = ProfileGroup(name: "Dupes", bindings: [
            MacroBinding(button: .rightShoulder),
            MacroBinding(button: .leftShoulder),
            MacroBinding(button: .rightShoulder),
        ])

        #expect(group.duplicateButtons == [.rightShoulder])
        #expect(group.hasDuplicateButtons)
    }

    @Test func withFreshIDsRegeneratesGroupAndBindingIdentifiers() {
        let original = ProfileGroup(name: "Template", bindings: [
            MacroBinding(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, button: .rightShoulder),
            MacroBinding(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, button: .leftShoulder),
        ])

        let cloned = original.withFreshIDs()

        #expect(cloned.id != original.id)
        #expect(cloned.bindings.map(\.id) != original.bindings.map(\.id))
        #expect(cloned.bindings.map(\.button) == original.bindings.map(\.button))
    }
}

// MARK: - scheduleSave debounce (TEST-10)

@Suite @MainActor struct ScheduleSaveDebounceTests {
    private func makeTestDefaults() -> (UserDefaults, String) {
        let suite = "com.test.gsecontroller.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func mutationPersistsAfterDebounce() async throws {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = ProfileStore(defaults: defaults)
        store.addGroup(ProfileGroup(name: "Persisted", bindings: []))

        let data = try await waitForPersistedGroups(in: defaults)
        let decoded = try JSONDecoder().decode([ProfileGroup].self, from: data)
        #expect(decoded.contains(where: { $0.name == "Persisted" }))
    }

    private func waitForPersistedGroups(in defaults: UserDefaults) async throws -> Data {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if let data = defaults.data(forKey: "groups") {
                return data
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        Issue.record("Timed out waiting for debounced save to persist")
        throw CancellationError()
    }
}
