import Foundation

struct KeyHelperDiagnostics: Sendable {
    let helperPath: String
    let launchAgentPath: String
    let launchAgentLabel: String
    let fifoPath: String
    let responseFifoPath: String
    let logPath: String
    let helperExists: Bool
    let launchAgentExists: Bool
    let fifoExists: Bool
    let responseFifoExists: Bool
}

protocol KeyInjecting: AnyObject, Sendable {
    var isAccessibilityEnabled: Bool { get }
    var isHelperAccessibilityEnabled: Bool { get }
    var diagnostics: KeyHelperDiagnostics { get }

    func ensureHelper(onComplete: (@MainActor (Bool) -> Void)?)
    func pressKey(_ keyCode: UInt16)
    func modifierDown(_ modifier: KeyModifier)
    func modifierUp(_ modifier: KeyModifier)
    func requestAccessibility()
    func openAccessibilitySettings()
    func revealHelperInFinder()
    func stopHelper()
}

final class KeySimulatorBridge: KeyInjecting, @unchecked Sendable {
    var isAccessibilityEnabled: Bool { KeySimulator.isAccessibilityEnabled }
    var isHelperAccessibilityEnabled: Bool { KeySimulator.isHelperAccessibilityEnabled }
    var diagnostics: KeyHelperDiagnostics { KeySimulator.diagnostics }

    func ensureHelper(onComplete: (@MainActor (Bool) -> Void)?) {
        KeySimulator.ensureHelper(onComplete: onComplete)
    }

    func pressKey(_ keyCode: UInt16) {
        KeySimulator.pressKey(keyCode)
    }

    func modifierDown(_ modifier: KeyModifier) {
        KeySimulator.modifierDown(modifier)
    }

    func modifierUp(_ modifier: KeyModifier) {
        KeySimulator.modifierUp(modifier)
    }

    func requestAccessibility() {
        KeySimulator.requestAccessibility()
    }

    func openAccessibilitySettings() {
        KeySimulator.openAccessibilitySettings()
    }

    func revealHelperInFinder() {
        KeySimulator.revealHelperInFinder()
    }

    func stopHelper() {
        KeySimulator.stopHelper()
    }
}

final class UITestKeyInjector: KeyInjecting, @unchecked Sendable {
    var isAccessibilityEnabled: Bool { true }
    var isHelperAccessibilityEnabled: Bool { true }
    var diagnostics = KeyHelperDiagnostics(
        helperPath: "/tmp/gsecontroller-ui-test/keyhelper",
        launchAgentPath: "/tmp/gsecontroller-ui-test/keyhelper.plist",
        launchAgentLabel: "ui.test.helper",
        fifoPath: "/tmp/gsecontroller-ui-test.keys",
        responseFifoPath: "/tmp/gsecontroller-ui-test.ax-response",
        logPath: "/tmp/gsecontroller-ui-test/helper.log",
        helperExists: true,
        launchAgentExists: true,
        fifoExists: true,
        responseFifoExists: true
    )

    func ensureHelper(onComplete: (@MainActor (Bool) -> Void)?) {
        if let onComplete {
            Task { @MainActor in onComplete(true) }
        }
    }

    func pressKey(_ keyCode: UInt16) {}
    func modifierDown(_ modifier: KeyModifier) {}
    func modifierUp(_ modifier: KeyModifier) {}
    func requestAccessibility() {}
    func openAccessibilitySettings() {}
    func revealHelperInFinder() {}
    func stopHelper() {}
}
