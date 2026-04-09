import Foundation
import AppKit
import os

@MainActor
class FireEngine: ObservableObject {
    private static let bundleID = Bundle.main.bundleIdentifier ?? "com.example.gsecontroller"
    private static let logger = Logger(subsystem: bundleID, category: "FireEngine")

    @Published var isFiring = false

    private let _requireWoWFocus = OSAllocatedUnfairLock<Bool>(initialState: true)
    var requireWoWFocus: Bool {
        get { _requireWoWFocus.withLock { $0 } }
        set { _requireWoWFocus.withLock { $0 = newValue } }
    }
    private let _wowIsActive = OSAllocatedUnfairLock<Bool>(initialState: false)
    var wowIsActive: Bool {
        get { _wowIsActive.withLock { $0 } }
        set {
            _wowIsActive.withLock { $0 = newValue }
            if requireWoWFocus && !newValue {
                stopAll()
            }
        }
    }

    var onAccessibilityRevoked: (() -> Void)?
    private let keyInjector: KeyInjecting

    /// Converts a rate in milliseconds to a clamped TimeInterval (seconds).
    /// Clamps to [33ms, 1000ms] (equivalent to 1–30 pps range).
    nonisolated static func clampedInterval(rateMs: Double) -> TimeInterval {
        min(max(rateMs, 33.0), 1000.0) / 1000.0
    }

    private var activeTimers: [ControllerButton: DispatchSourceTimer] = [:]
    private var activeBindings: [ControllerButton: MacroBinding] = [:]
    var heldModifiers: Set<KeyModifier> = []
    private var heldModifierCounts: [KeyModifier: Int] = [:]
    nonisolated(unsafe) private var activity: NSObjectProtocol?
    private let fireQueue = DispatchQueue(label: "\(FireEngine.bundleID).fire", qos: .userInteractive)

    // Cached accessibility state for fireQueue reads.
    // Written by axMonitorTask (@MainActor, every ~3s); read by timer handlers on fireQueue.
    // In macOS 26, AXIsProcessTrusted() is @MainActor — calling it directly from fireQueue
    // triggers _swift_task_checkIsolatedSwift/_dispatch_assert_queue_fail via the
    // @preconcurrency import ApplicationServices runtime isolation check.
    private let _axEnabled = OSAllocatedUnfairLock<Bool>(initialState: true)

    // Runs on @MainActor while any timers are active; polls AX state into _axEnabled.
    private var axMonitorTask: Task<Void, Never>?

    init(keyInjector: KeyInjecting = KeySimulatorBridge()) {
        self.keyInjector = keyInjector
    }

    deinit {
        for (_, timer) in activeTimers { timer.cancel() }
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
    }

    func startFiring(binding: MacroBinding) {
        guard activeTimers[binding.button] == nil else { return }
        guard canSendImmediateInput() else { return }
        let injector = keyInjector

        // Start the @MainActor AX monitor if it isn't already running.
        // This is the only place KeySimulator.isAccessibilityEnabled is called — safely on @MainActor.
        // Seed from current state immediately so there is no blind window at startup where
        // _axEnabled=true but AX is actually revoked — without this, spurious key events can
        // fire in the 0–3s window before the monitor task's first sleep completes.
        _axEnabled.withLock { $0 = injector.isAccessibilityEnabled }
        if axMonitorTask == nil {
            axMonitorTask = Task { [weak self, injector] in
                while !Task.isCancelled {
                    guard let self, !Task.isCancelled else { break }
                    let ok = injector.isAccessibilityEnabled
                    self._axEnabled.withLock { $0 = ok }
                    if !ok {
                        Self.logger.warning("Accessibility permission revoked, stopping")
                        self.stopAll()
                        self.onAccessibilityRevoked?()
                        break
                    }
                    try? await Task.sleep(for: .seconds(3))
                }
            }
        }

        let keyCode = binding.keyCode
        let interval = FireEngine.clampedInterval(rateMs: binding.rate)
        let focusLock = _requireWoWFocus
        let wowLock = _wowIsActive
        let axLock = _axEnabled
        // Build the timer from a nonisolated helper so the event handler closure is
        // formed outside any actor context. In Swift 6 on macOS 26, non-@Sendable closure
        // parameters inherit the caller's actor isolation; if setEventHandler's handler
        // lost @Sendable in the macOS 26 Dispatch overlay the closure would be inferred
        // @MainActor (inheriting startFiring's isolation) and crash on fireQueue.
        let timer = FireEngine.makeTimer(
            queue: fireQueue, interval: interval,
            keyCode: keyCode, focusLock: focusLock,
            wowLock: wowLock, axLock: axLock,
            keyInjector: injector
        )

        activeTimers[binding.button] = timer
        activeBindings[binding.button] = binding
        holdModifierIfNeeded(binding.modifier)

        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Firing macro key presses"
            )
        }
        isFiring = true

        timer.resume()
    }

    // nonisolated so the event handler closure is formed outside @MainActor context,
    // preventing Swift 6 from inferring @MainActor isolation on it.
    private nonisolated static func makeTimer(
        queue: DispatchQueue,
        interval: Double,
        keyCode: UInt16,
        focusLock: OSAllocatedUnfairLock<Bool>,
        wowLock: OSAllocatedUnfairLock<Bool>,
        axLock: OSAllocatedUnfairLock<Bool>,
        keyInjector: KeyInjecting
    ) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(4))
        timer.setEventHandler {
            if !axLock.withLock({ $0 }) { return }
            if focusLock.withLock({ $0 }) && !wowLock.withLock({ $0 }) { return }
            keyInjector.pressKey(keyCode)
        }
        return timer
    }

    func stopFiring(button: ControllerButton) {
        activeTimers[button]?.cancel()
        activeTimers[button] = nil
        if let binding = activeBindings.removeValue(forKey: button) {
            releaseModifierIfNeeded(binding.modifier)
        }
        if activeTimers.isEmpty {
            axMonitorTask?.cancel()
            axMonitorTask = nil
            isFiring = false
            if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        }
    }

    func stopAll() {
        for modifier in heldModifiers { keyInjector.modifierUp(modifier) }
        heldModifiers.removeAll()
        heldModifierCounts.removeAll()
        for (_, timer) in activeTimers { timer.cancel() }
        activeTimers.removeAll()
        activeBindings.removeAll()
        axMonitorTask?.cancel()
        axMonitorTask = nil
        isFiring = false
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
    }

    func modifierDown(_ modifier: KeyModifier) {
        guard modifier != .none else { return }
        guard canSendImmediateInput() else { return }
        holdModifierIfNeeded(modifier)
    }

    func modifierUp(_ modifier: KeyModifier) {
        guard modifier != .none else { return }
        releaseModifierIfNeeded(modifier)
    }

    func tap(binding: MacroBinding) {
        guard canSendImmediateInput() else { return }
        holdModifierIfNeeded(binding.modifier)
        keyInjector.pressKey(binding.keyCode)
        releaseModifierIfNeeded(binding.modifier)
    }

    private func canSendImmediateInput() -> Bool {
        let axEnabled = keyInjector.isAccessibilityEnabled
        _axEnabled.withLock { $0 = axEnabled }
        guard axEnabled else {
            stopAll()
            onAccessibilityRevoked?()
            return false
        }
        return !requireWoWFocus || wowIsActive
    }

    private func holdModifierIfNeeded(_ modifier: KeyModifier) {
        guard modifier != .none else { return }
        let currentCount = heldModifierCounts[modifier, default: 0]
        if currentCount == 0 {
            keyInjector.modifierDown(modifier)
        }
        heldModifierCounts[modifier] = currentCount + 1
        heldModifiers.insert(modifier)
    }

    private func releaseModifierIfNeeded(_ modifier: KeyModifier) {
        guard modifier != .none else { return }
        let currentCount = heldModifierCounts[modifier, default: 0]
        guard currentCount > 0 else { return }
        if currentCount == 1 {
            keyInjector.modifierUp(modifier)
            heldModifierCounts.removeValue(forKey: modifier)
            heldModifiers.remove(modifier)
        } else {
            heldModifierCounts[modifier] = currentCount - 1
        }
    }
}
