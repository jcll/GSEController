import Foundation
import GameController
import AppKit
import os

class ControllerManager: ObservableObject {
    private static let logger = Logger(subsystem: "com.jcll.gsecontroller", category: "ControllerManager")

    @Published var controllerName: String?
    @Published var isConnected = false
    @Published var isFiring = false
    @Published var isRunning = false
    @Published var statusMessage = "Ready"
    @Published var hasAccessibility = false
    @Published var hasHelperAccessibility = false
    @Published var requireWoWFocus: Bool {
        didSet { UserDefaults.standard.set(requireWoWFocus, forKey: "requireWoWFocus") }
    }

    private var controller: GCController?
    private var activeTimers: [ControllerButton: DispatchSourceTimer] = [:]
    private var heldModifiers: Set<KeyModifier> = []
    private var activeGroup: ProfileGroup?
    private var lastAccessibilityCheck: TimeInterval = 0
    private var activity: NSObjectProtocol?

    // Serial queue owns all CGEvent posting — prevents concurrent HID stream writes.
    private let fireQueue = DispatchQueue(label: "com.jcll.gsecontroller.fire", qos: .userInteractive)

    // Lock-protected so fireQueue reads and main-thread writes don't race.
    private let _wowIsActive = OSAllocatedUnfairLock<Bool>(initialState: false)
    private var wowIsActive: Bool {
        get { _wowIsActive.withLock { $0 } }
        set { _wowIsActive.withLock { $0 = newValue } }
    }

    init() {
        self.requireWoWFocus = UserDefaults.standard.object(forKey: "requireWoWFocus") as? Bool ?? true
        hasAccessibility = KeySimulator.isAccessibilityEnabled
        GCController.shouldMonitorBackgroundEvents = true
        setupNotifications()
        setupAppTracking()
        if let existing = GCController.controllers().first {
            connectController(existing)
        }
    }

    // MARK: - Controller Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerConnected),
            name: .GCControllerDidConnect, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerDisconnected),
            name: .GCControllerDidDisconnect, object: nil
        )
        GCController.startWirelessControllerDiscovery {}
    }

    @objc private func controllerConnected(_ notification: Notification) {
        if let gc = notification.object as? GCController {
            connectController(gc)
        }
    }

    @objc private func controllerDisconnected(_ notification: Notification) {
        Self.logger.info("Controller disconnected")
        DispatchQueue.main.async {
            self.controller = nil
            self.controllerName = nil
            self.isConnected = false
            self.stop()
            self.statusMessage = "Controller disconnected"
        }
    }

    private func connectController(_ gc: GCController) {
        Self.logger.info("Controller connected: \(gc.vendorName ?? "unknown", privacy: .public)")
        DispatchQueue.main.async {
            self.controller = gc
            self.controllerName = gc.vendorName ?? "Controller"
            self.isConnected = true
            self.statusMessage = "Controller connected"
            if self.isRunning, let group = self.activeGroup {
                self.attachHandlers(for: group)
            }
        }
    }

    // MARK: - WoW Focus Tracking

    private func setupAppTracking() {
        refreshWoWFocus()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
    }

    @objc private func activeAppChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        wowIsActive = Self.isWoW(app)
    }

    private func refreshWoWFocus() {
        if let app = NSWorkspace.shared.frontmostApplication {
            wowIsActive = Self.isWoW(app)
        }
    }

    private static let wowBundleIDs: Set<String> = [
        "com.blizzard.worldofwarcraft",
        "com.blizzard.worldofwarcraftclassic",
        "com.blizzard.wow",
    ]

    private static func isWoW(_ app: NSRunningApplication) -> Bool {
        if let bundleID = app.bundleIdentifier?.lowercased(), wowBundleIDs.contains(bundleID) { return true }
        if let name = app.localizedName?.lowercased(), name.contains("warcraft") { return true }
        return false
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for (_, timer) in activeTimers { timer.cancel() }
    }

    // MARK: - Start / Stop

    func start(group: ProfileGroup) {
        guard isConnected else {
            statusMessage = "No controller connected"
            return
        }
        hasAccessibility = KeySimulator.isAccessibilityEnabled
        guard hasAccessibility else {
            KeySimulator.requestAccessibility()
            statusMessage = "Grant Accessibility access, then try again"
            return
        }
        activeGroup = group
        isRunning = true
        KeySimulator.ensureHelper()
        refreshWoWFocus()
        let bindingCount = group.bindings.count
        Self.logger.info("Started group \"\(group.name, privacy: .public)\" with \(bindingCount) binding(s)")
        statusMessage = "Active — \(group.name)"
        attachHandlers(for: group)
    }

    func stop() {
        // Release any held modifiers before stopping to prevent stuck keys.
        for modifier in heldModifiers {
            KeySimulator.modifierUp(modifier)
        }
        heldModifiers.removeAll()

        cancelAllTimers()
        clearButtonHandlers()
        isRunning = false
        activeGroup = nil
        KeySimulator.stopHelper()
        if isConnected {
            statusMessage = "Stopped"
        }
    }

    // MARK: - Button Handlers

    private func buttonInput(for button: ControllerButton, on gamepad: GCExtendedGamepad) -> GCControllerButtonInput? {
        switch button {
        case .rightShoulder: gamepad.rightShoulder
        case .leftShoulder:  gamepad.leftShoulder
        case .rightTrigger:  gamepad.rightTrigger
        case .leftTrigger:   gamepad.leftTrigger
        case .buttonSouth:   gamepad.buttonA
        case .buttonEast:    gamepad.buttonB
        case .buttonWest:    gamepad.buttonX
        case .buttonNorth:   gamepad.buttonY
        case .l3:            gamepad.leftThumbstickButton
        case .r3:            gamepad.rightThumbstickButton
        case .dpadDown:      gamepad.dpad.down
        case .dpadLeft:      gamepad.dpad.left
        case .dpadRight:     gamepad.dpad.right
        }
    }

    private func attachHandlers(for group: ProfileGroup) {
        guard let gamepad = controller?.extendedGamepad else { return }
        clearButtonHandlers()

        for binding in group.bindings {
            // Capture binding by value — the closure doesn't hold a reference to the group.
            buttonInput(for: binding.button, on: gamepad)?.pressedChangedHandler = { [weak self] _, _, pressed in
                DispatchQueue.main.async {
                    self?.handleButton(binding: binding, pressed: pressed)
                }
            }
        }
    }

    private func clearButtonHandlers() {
        guard let gamepad = controller?.extendedGamepad else { return }
        for button in ControllerButton.allCases {
            buttonInput(for: button, on: gamepad)?.pressedChangedHandler = nil
        }
    }

    // MARK: - Per-binding event handling

    private func handleButton(binding: MacroBinding, pressed: Bool) {
        guard isRunning else { return }
        switch binding.mode {
        case .hold:
            if pressed {
                startTimer(for: binding)
            } else {
                cancelTimer(for: binding.button)
            }

        case .tap:
            if pressed {
                KeySimulator.pressKey(binding.keyCode)
            }

        case .modifierHold:
            guard binding.modifier != .none else { return }
            if pressed {
                KeySimulator.modifierDown(binding.modifier)
                heldModifiers.insert(binding.modifier)
            } else {
                KeySimulator.modifierUp(binding.modifier)
                heldModifiers.remove(binding.modifier)
            }
        }
    }

    // MARK: - Timer management

    private func startTimer(for binding: MacroBinding) {
        // Don't double-start if already running for this button.
        guard activeTimers[binding.button] == nil else { return }

        let keyCode = binding.keyCode
        let interval = 1.0 / min(max(binding.rate, 1.0), 30.0)
        let focusRequired = requireWoWFocus

        let timer = DispatchSource.makeTimerSource(queue: fireQueue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(4))

        var lastAccessCheck = ProcessInfo.processInfo.systemUptime

        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastAccessCheck >= 3.0 {
                lastAccessCheck = now
                guard KeySimulator.isAccessibilityEnabled else {
                    Self.logger.warning("Accessibility permission revoked, stopping")
                    DispatchQueue.main.async { self.stop(); self.hasAccessibility = false }
                    return
                }
            }
            if focusRequired && !self.wowIsActive { return }
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
        statusMessage = "FIRING"

        timer.resume()
    }

    private func cancelTimer(for button: ControllerButton) {
        activeTimers[button]?.cancel()
        activeTimers[button] = nil

        if activeTimers.isEmpty {
            isFiring = false
            if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
            if isRunning, let group = activeGroup {
                statusMessage = "Active — \(group.name)"
            }
        }
    }

    private func cancelAllTimers() {
        for (_, timer) in activeTimers { timer.cancel() }
        activeTimers.removeAll()
        isFiring = false
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
    }

    func checkAccessibility() {
        hasAccessibility = KeySimulator.isAccessibilityEnabled
        DispatchQueue.global(qos: .userInitiated).async {
            let helperAx = KeySimulator.isHelperAccessibilityEnabled
            DispatchQueue.main.async { self.hasHelperAccessibility = helperAx }
        }
    }
}
