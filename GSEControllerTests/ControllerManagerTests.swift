import Foundation
import Testing
@testable import GSEController

// MARK: - isWoW bundle ID matching (TEST-04)

@Suite struct IsWoWTests {
    @Test func exactWoWBundleIDMatches() {
        #expect(ControllerManager.isWoW(bundleID: "com.blizzard.worldofwarcraft", localizedName: nil))
    }

    @Test func classicWoWBundleIDMatches() {
        #expect(ControllerManager.isWoW(bundleID: "com.blizzard.worldofwarcraftclassic", localizedName: nil))
    }

    @Test func shortWoWBundleIDMatches() {
        #expect(ControllerManager.isWoW(bundleID: "com.blizzard.wow", localizedName: nil))
    }

    @Test func bundleIDIsCaseInsensitive() {
        #expect(ControllerManager.isWoW(bundleID: "COM.BLIZZARD.WORLDOFWARCRAFT", localizedName: nil))
    }

    @Test func nonWoWBundleIDDoesNotMatch() {
        #expect(!ControllerManager.isWoW(bundleID: "com.apple.finder", localizedName: nil))
    }

    @Test func nilBundleIDDoesNotMatch() {
        #expect(!ControllerManager.isWoW(bundleID: nil, localizedName: nil))
    }

    @Test func localizedNameContainingWarcraftMatches() {
        #expect(ControllerManager.isWoW(bundleID: nil, localizedName: "World of Warcraft"))
    }

    @Test func localizedNameWarcraftIsCaseInsensitive() {
        #expect(ControllerManager.isWoW(bundleID: nil, localizedName: "WORLD OF WARCRAFT"))
    }

    @Test func localizedNameWithoutWarcraftDoesNotMatch() {
        #expect(!ControllerManager.isWoW(bundleID: nil, localizedName: "Finder"))
    }

    @Test func nilBundleIDAndNilNameDoesNotMatch() {
        #expect(!ControllerManager.isWoW(bundleID: nil, localizedName: nil))
    }
}

// MARK: - Start / Stop state transitions

@Suite @MainActor struct StartStopStateTests {
    private func makeTestDefaults() -> (UserDefaults, String) {
        let suite = "com.test.gsecontroller.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func startWithoutControllerDoesNotSetIsRunning() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = ControllerManager(defaults: defaults)
        manager.start(group: ProfileGroup(name: "Test", bindings: []))
        #expect(manager.isRunning == false)
    }

    @Test func startWithoutControllerSetsStatusMessage() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = ControllerManager(defaults: defaults)
        manager.start(group: ProfileGroup(name: "Test", bindings: []))
        #expect(manager.statusMessage == "No controller connected")
    }

    @Test func stopSetsIsRunningFalse() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = ControllerManager(defaults: defaults)
        manager.stop()
        #expect(manager.isRunning == false)
    }
}

// MARK: - Low Battery Threshold (TEST-09)

@Suite struct LowBatteryThresholdTests {
    @Test func notChargingBelowThresholdNotYetNotifiedShouldNotify() {
        #expect(ControllerManager.shouldNotifyLowBattery(level: 0.15, charging: false, alreadyNotified: false))
    }

    @Test func chargingBelowThresholdShouldNotNotify() {
        #expect(!ControllerManager.shouldNotifyLowBattery(level: 0.10, charging: true, alreadyNotified: false))
    }

    @Test func aboveThresholdShouldNotNotify() {
        #expect(!ControllerManager.shouldNotifyLowBattery(level: 0.50, charging: false, alreadyNotified: false))
    }

    @Test func alreadyNotifiedShouldNotNotifyAgain() {
        #expect(!ControllerManager.shouldNotifyLowBattery(level: 0.10, charging: false, alreadyNotified: true))
    }

    @Test func exactlyAtThresholdShouldNotify() {
        #expect(ControllerManager.shouldNotifyLowBattery(level: 0.20, charging: false, alreadyNotified: false))
    }

    @Test func justAboveThresholdShouldNotNotify() {
        #expect(!ControllerManager.shouldNotifyLowBattery(level: 0.21, charging: false, alreadyNotified: false))
    }
}

// MARK: - requireWoWFocus UserDefaults persistence (TEST-04)

@Suite @MainActor struct RequireWoWFocusPersistenceTests {
    private func makeTestDefaults() -> (UserDefaults, String) {
        let suite = "com.test.gsecontroller.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func requireWoWFocusPersistsFalse() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let manager = ControllerManager(defaults: defaults)
        manager.requireWoWFocus = false
        #expect(defaults.object(forKey: "requireWoWFocus") as? Bool == false)
    }

    @Test func requireWoWFocusPersistsTrue() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let manager = ControllerManager(defaults: defaults)
        manager.requireWoWFocus = false
        manager.requireWoWFocus = true
        #expect(defaults.object(forKey: "requireWoWFocus") as? Bool == true)
    }

    @Test func requireWoWFocusDefaultsToTrue() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let manager = ControllerManager(defaults: defaults)
        #expect(manager.requireWoWFocus == true)
    }

    @Test func requireWoWFocusLoadsFromDefaults() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(false, forKey: "requireWoWFocus")
        let manager = ControllerManager(defaults: defaults)
        #expect(manager.requireWoWFocus == false)
    }
}
