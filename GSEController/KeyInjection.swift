import Foundation

// Small diagnostics payload copied into the helper sheet and clipboard. It is
// intentionally string-based so it stays easy to inspect in logs and support
// messages.
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
    // Abstraction over key delivery and helper lifecycle. The production
    // implementation talks to KeySimulator, while tests inject in-process fakes
    // to keep timer and controller logic deterministic.
    var isAccessibilityEnabled: Bool { get }
    var isHelperAccessibilityEnabled: Bool { get }
    var diagnostics: KeyHelperDiagnostics { get }
    var onFIFOFailure: (() -> Void)? { get set }
    var onFIFORecovered: (() -> Void)? { get set }

    func ensureHelper(onComplete: (@MainActor (Bool) -> Void)?)
    func pressKey(_ keyCode: UInt16)
    func modifierDown(_ modifier: KeyModifier)
    func modifierUp(_ modifier: KeyModifier)
    func requestAccessibility()
    func requestHelperAccessibility()
    func openAccessibilitySettings()
    func revealHelperInFinder()
    func stopHelper()
}

final class KeySimulatorBridge: KeyInjecting, @unchecked Sendable {
    private let simulator: KeySimulator
    private var cachedDiagnostics: KeyHelperDiagnostics?

    init(simulator: KeySimulator) {
        self.simulator = simulator
    }

    var isAccessibilityEnabled: Bool { simulator.isAccessibilityEnabled }
    var isHelperAccessibilityEnabled: Bool { simulator.isHelperAccessibilityEnabled }
    var diagnostics: KeyHelperDiagnostics {
        if let cached = cachedDiagnostics { return cached }
        let fresh = simulator.diagnostics
        cachedDiagnostics = fresh
        return fresh
    }

    func invalidateDiagnosticsCache() {
        cachedDiagnostics = nil
    }
    var onFIFOFailure: (() -> Void)? {
        get { simulator.onFIFOFailure }
        set { simulator.onFIFOFailure = newValue }
    }
    var onFIFORecovered: (() -> Void)? {
        get { simulator.onFIFORecovered }
        set { simulator.onFIFORecovered = newValue }
    }

    func ensureHelper(onComplete: (@MainActor (Bool) -> Void)?) {
        simulator.ensureHelper(onComplete: onComplete)
    }

    func pressKey(_ keyCode: UInt16) {
        simulator.pressKey(keyCode)
    }

    func modifierDown(_ modifier: KeyModifier) {
        simulator.modifierDown(modifier)
    }

    func modifierUp(_ modifier: KeyModifier) {
        simulator.modifierUp(modifier)
    }

    func requestAccessibility() {
        simulator.requestAccessibility()
    }

    func requestHelperAccessibility() {
        simulator.requestHelperAccessibility()
    }

    func openAccessibilitySettings() {
        simulator.openAccessibilitySettings()
    }

    func revealHelperInFinder() {
        simulator.revealHelperInFinder()
    }

    func stopHelper() {
        simulator.stopHelper()
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
    var onFIFOFailure: (() -> Void)?
    var onFIFORecovered: (() -> Void)?

    func ensureHelper(onComplete: (@MainActor (Bool) -> Void)?) {
        if let onComplete {
            Task { @MainActor in onComplete(true) }
        }
    }

    func pressKey(_ keyCode: UInt16) {}
    func modifierDown(_ modifier: KeyModifier) {}
    func modifierUp(_ modifier: KeyModifier) {}
    func requestAccessibility() {}
    func requestHelperAccessibility() {}
    func openAccessibilitySettings() {}
    func revealHelperInFinder() {}
    func stopHelper() {}
}
