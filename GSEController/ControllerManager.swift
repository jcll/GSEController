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
        didSet {
            UserDefaults.standard.set(requireWoWFocus, forKey: "requireWoWFocus")
            fireEngine.requireWoWFocus = requireWoWFocus
        }
    }

    let fireEngine = FireEngine()
    private var controller: GCController?
    private var activeGroup: ProfileGroup?

    init() {
        self.requireWoWFocus = UserDefaults.standard.object(forKey: "requireWoWFocus") as? Bool ?? true
        hasAccessibility = KeySimulator.isAccessibilityEnabled
        GCController.shouldMonitorBackgroundEvents = true
        setupNotifications()
        setupAppTracking()
        if let existing = GCController.controllers().first {
            connectController(existing)
        }
        KeySimulator.ensureHelper()

        fireEngine.requireWoWFocus = requireWoWFocus
        fireEngine.onAccessibilityRevoked = { [weak self] in
            self?.hasAccessibility = false
            self?.stop()
        }
        fireEngine.$isFiring.assign(to: &$isFiring)
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
        fireEngine.wowIsActive = Self.isWoW(app)
    }

    private func refreshWoWFocus() {
        if let app = NSWorkspace.shared.frontmostApplication {
            fireEngine.wowIsActive = Self.isWoW(app)
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
        fireEngine.requireWoWFocus = requireWoWFocus
        refreshWoWFocus()
        let bindingCount = group.bindings.count
        Self.logger.info("Started group \"\(group.name, privacy: .public)\" with \(bindingCount) binding(s)")
        statusMessage = "Active — \(group.name)"
        attachHandlers(for: group)
    }

    func stop() {
        fireEngine.stopAll()
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
                fireEngine.startFiring(binding: binding)
            } else {
                fireEngine.stopFiring(button: binding.button)
            }

        case .tap:
            if pressed {
                KeySimulator.pressKey(binding.keyCode)
            }

        case .modifierHold:
            if pressed {
                fireEngine.modifierDown(binding.modifier)
            } else {
                fireEngine.modifierUp(binding.modifier)
            }
        }
    }

    func checkAccessibility() {
        hasAccessibility = KeySimulator.isAccessibilityEnabled
        DispatchQueue.global(qos: .userInitiated).async {
            let helperAx = KeySimulator.isHelperAccessibilityEnabled
            DispatchQueue.main.async { self.hasHelperAccessibility = helperAx }
        }
    }
}
