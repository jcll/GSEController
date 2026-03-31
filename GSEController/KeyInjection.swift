import Foundation

protocol KeyInjecting: AnyObject, Sendable {
    var isAccessibilityEnabled: Bool { get }
    var isHelperAccessibilityEnabled: Bool { get }

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
