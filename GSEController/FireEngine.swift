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
        set { _wowIsActive.withLock { $0 = newValue } }
    }

    var onAccessibilityRevoked: (() -> Void)?

    nonisolated static func clampedInterval(rate: Double) -> TimeInterval {
        1.0 / min(max(rate, 1.0), 30.0)
    }

    private var activeTimers: [ControllerButton: DispatchSourceTimer] = [:]
    private var heldModifiers: Set<KeyModifier> = []
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

    deinit {
        for (_, timer) in activeTimers { timer.cancel() }
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
    }

    func startFiring(binding: MacroBinding) {
        guard activeTimers[binding.button] == nil else { return }

        // Start the @MainActor AX monitor if it isn't already running.
        // This is the only place KeySimulator.isAccessibilityEnabled is called — safely on @MainActor.
        if axMonitorTask == nil {
            axMonitorTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, !Task.isCancelled else { break }
                    let ok = KeySimulator.isAccessibilityEnabled
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
        let interval = FireEngine.clampedInterval(rate: binding.rate)
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
            wowLock: wowLock, axLock: axLock
        )

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

    // nonisolated so the event handler closure is formed outside @MainActor context,
    // preventing Swift 6 from inferring @MainActor isolation on it.
    private nonisolated static func makeTimer(
        queue: DispatchQueue,
        interval: Double,
        keyCode: UInt16,
        focusLock: OSAllocatedUnfairLock<Bool>,
        wowLock: OSAllocatedUnfairLock<Bool>,
        axLock: OSAllocatedUnfairLock<Bool>
    ) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(4))
        timer.setEventHandler {
            if !axLock.withLock({ $0 }) { return }
            if focusLock.withLock({ $0 }) && !wowLock.withLock({ $0 }) { return }
            KeySimulator.pressKey(keyCode)
        }
        return timer
    }

    func stopFiring(button: ControllerButton) {
        activeTimers[button]?.cancel()
        activeTimers[button] = nil
        if activeTimers.isEmpty {
            axMonitorTask?.cancel()
            axMonitorTask = nil
            isFiring = false
            if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        }
    }

    func stopAll() {
        for modifier in heldModifiers { KeySimulator.modifierUp(modifier) }
        heldModifiers.removeAll()
        for (_, timer) in activeTimers { timer.cancel() }
        activeTimers.removeAll()
        axMonitorTask?.cancel()
        axMonitorTask = nil
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
