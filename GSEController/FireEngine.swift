import Foundation
import AppKit
import os

@MainActor
class FireEngine: ObservableObject {
    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.example.gsecontroller"
    private static let logger = Logger(subsystem: bundleID, category: "FireEngine")

    @Published var isFiring = false

    var requireWoWFocus: Bool = true
    private let _wowIsActive = OSAllocatedUnfairLock<Bool>(initialState: false)
    var wowIsActive: Bool {
        get { _wowIsActive.withLock { $0 } }
        set { _wowIsActive.withLock { $0 = newValue } }
    }

    var onAccessibilityRevoked: (() -> Void)?

    private var activeTimers: [ControllerButton: DispatchSourceTimer] = [:]
    private var heldModifiers: Set<KeyModifier> = []
    nonisolated(unsafe) private var activity: NSObjectProtocol?
    private let fireQueue = DispatchQueue(label: "\(FireEngine.bundleID).fire", qos: .userInteractive)

    deinit {
        for (_, timer) in activeTimers { timer.cancel() }
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
    }

    func startFiring(binding: MacroBinding) {
        guard activeTimers[binding.button] == nil else { return }

        let keyCode = binding.keyCode
        let interval = 1.0 / min(max(binding.rate, 1.0), 30.0)
        let focusRequired = requireWoWFocus

        let timer = DispatchSource.makeTimerSource(queue: fireQueue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(4))

        var lastAccessCheck = ProcessInfo.processInfo.systemUptime
        // Capture the lock directly so the event handler never touches @MainActor-isolated self.
        let wowLock = _wowIsActive

        timer.setEventHandler { [weak self] in
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastAccessCheck >= 3.0 {
                lastAccessCheck = now
                if !KeySimulator.isAccessibilityEnabled {
                    Task { @MainActor [weak self] in
                        Self.logger.warning("Accessibility permission revoked, stopping")
                        self?.stopAll()
                        self?.onAccessibilityRevoked?()
                    }
                    return
                }
            }
            if focusRequired && !wowLock.withLock({ $0 }) { return }
            KeySimulator.pressKey(keyCode)
        }

        activeTimers[binding.button] = timer

        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Firing macro key presses"
            )
        }
        isFiring = true

        timer.resume()
    }

    func stopFiring(button: ControllerButton) {
        activeTimers[button]?.cancel()
        activeTimers[button] = nil
        if activeTimers.isEmpty {
            isFiring = false
            if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        }
    }

    func stopAll() {
        for modifier in heldModifiers { KeySimulator.modifierUp(modifier) }
        heldModifiers.removeAll()
        for (_, timer) in activeTimers { timer.cancel() }
        activeTimers.removeAll()
        isFiring = false
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
    }

    func modifierDown(_ modifier: KeyModifier) {
        guard modifier != .none else { return }
        KeySimulator.modifierDown(modifier)
        heldModifiers.insert(modifier)
    }

    func modifierUp(_ modifier: KeyModifier) {
        guard modifier != .none else { return }
        KeySimulator.modifierUp(modifier)
        heldModifiers.remove(modifier)
    }
}
