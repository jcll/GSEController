import Foundation
import Testing
@testable import GSEController

private final class DeferredHelperInjector: KeyInjecting, @unchecked Sendable {
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
    var events: [String] = []
    private var pendingCompletions: [(@MainActor (Bool) -> Void)] = []

    func ensureHelper(onComplete: (@MainActor (Bool) -> Void)?) {
        if let onComplete {
            pendingCompletions.append(onComplete)
        }
    }

    func complete(_ ready: Bool) async {
        let completions = pendingCompletions
        pendingCompletions.removeAll()
        for completion in completions {
            await MainActor.run {
                completion(ready)
            }
        }
    }

    func pressKey(_ keyCode: UInt16) { events.append("press:\(keyCode)") }
    func modifierDown(_ modifier: KeyModifier) { events.append("down:\(modifier.rawValue)") }
    func modifierUp(_ modifier: KeyModifier) { events.append("up:\(modifier.rawValue)") }
    func requestAccessibility() {}
    func openAccessibilitySettings() {}
    func revealHelperInFinder() {}
    func stopHelper() {}
}

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

    @Test func startWaitsForHelperBeforeMarkingRunning() async {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let injector = DeferredHelperInjector()
        let manager = ControllerManager(
            defaults: defaults,
            keyInjector: injector,
            testState: .init()
        )
        let group = ProfileGroup(name: "Ready Check", bindings: [MacroBinding(button: .rightShoulder)])
        manager.requireWoWFocus = false

        manager.start(group: group)

        #expect(manager.isStarting)
        #expect(!manager.isRunning)

        await injector.complete(true)

        #expect(!manager.isStarting)
        #expect(manager.isRunning)
        #expect(manager.statusMessage == "Active — Ready Check")
    }

    @Test func stopCancelsPendingStart() async {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let injector = DeferredHelperInjector()
        let manager = ControllerManager(
            defaults: defaults,
            keyInjector: injector,
            testState: .init()
        )

        manager.start(group: ProfileGroup(name: "Later", bindings: [MacroBinding(button: .rightShoulder)]))
        manager.stop()
        await injector.complete(true)

        #expect(!manager.isRunning)
        #expect(!manager.isStarting)
    }

    @Test func duplicateBindingsBlockStart() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let injector = DeferredHelperInjector()
        let manager = ControllerManager(
            defaults: defaults,
            keyInjector: injector,
            testState: .init()
        )
        let group = ProfileGroup(name: "Dupes", bindings: [
            MacroBinding(button: .rightShoulder),
            MacroBinding(button: .rightShoulder, keyName: "1", keyCode: 0x12),
        ])

        manager.start(group: group)

        #expect(!manager.isRunning)
        #expect(!manager.isStarting)
        #expect(manager.statusMessage == "Resolve duplicate button assignments before starting")
    }

    @Test func stopReleasesModifiersThroughInjectedKeyInjector() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let injector = DeferredHelperInjector()
        let manager = ControllerManager(
            defaults: defaults,
            keyInjector: injector,
            testState: .init()
        )

        manager.stop()

        #expect(injector.events == ["up:alt", "up:shift", "up:ctrl"])
    }

    @Test func releaseAllInputStopsAndReportsSafetyStatus() {
        let (defaults, suite) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let injector = DeferredHelperInjector()
        let manager = ControllerManager(
            defaults: defaults,
            keyInjector: injector,
            testState: .init()
        )

        manager.releaseAllInput()

        #expect(!manager.isRunning)
        #expect(manager.statusMessage == "Released all held keys")
        #expect(injector.events == ["up:alt", "up:shift", "up:ctrl"])
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

    @Test func chargingShouldResetNotificationLatch() {
        #expect(ControllerManager.shouldResetLowBatteryNotification(level: 0.10, charging: true))
    }

    @Test func aboveHysteresisThresholdShouldResetNotificationLatch() {
        #expect(ControllerManager.shouldResetLowBatteryNotification(level: 0.26, charging: false))
    }

    @Test func betweenAlertAndHysteresisThresholdShouldNotResetNotificationLatch() {
        #expect(!ControllerManager.shouldResetLowBatteryNotification(level: 0.21, charging: false))
    }

    @Test func exactlyAtHysteresisThresholdShouldNotResetNotificationLatch() {
        #expect(!ControllerManager.shouldResetLowBatteryNotification(level: 0.25, charging: false))
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
