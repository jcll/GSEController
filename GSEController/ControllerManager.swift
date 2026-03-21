import Foundation
import GameController
import AppKit
import os
import Combine
import UserNotifications

@MainActor
class ControllerManager: ObservableObject {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.gsecontroller", category: "ControllerManager")

    @Published var controllerName: String?
    @Published var isConnected = false
    @Published var isFiring = false
    @Published var isRunning = false
    @Published var statusMessage = "Ready"
    @Published var hasAccessibility = false
    @Published var hasHelperAccessibility = false
    @Published var batteryLevel: Float? = nil
    @Published var batteryCharging: Bool = false
    @Published var helperReady: Bool = true
    @Published var fifoHealthy: Bool = true
    @Published var wowIsActive: Bool = false {
        didSet { updateStatusIfRunning() }
    }
    @Published var requireWoWFocus: Bool {
        didSet {
            defaults.set(requireWoWFocus, forKey: "requireWoWFocus")
            fireEngine.requireWoWFocus = requireWoWFocus
        }
    }

    private let defaults: UserDefaults
    private let fireEngine = FireEngine()
    private var controller: GCController?
    private var activeGroupName: String?
    private var activeBindings: [MacroBinding]?
    private var firingObserver: AnyCancellable?
    // nonisolated(unsafe) so deinit can invalidate it without a MainActor hop
    nonisolated(unsafe) private var batteryTimer: Timer?
    private let dualSenseBattery = DualSenseBatteryMonitor()
    private var lowBatteryNotified = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.requireWoWFocus = defaults.object(forKey: "requireWoWFocus") as? Bool ?? true
        GCController.shouldMonitorBackgroundEvents = true
        setupNotifications()
        setupAppTracking()
        setupPermissionRecheck()
        KeySimulator.ensureHelper { [weak self] ready in
            self?.helperReady = ready
        }
        KeySimulator.onFIFOFailure = { [weak self] in
            Task { @MainActor [weak self] in self?.fifoHealthy = false }
        }
        KeySimulator.onFIFORecovered = { [weak self] in
            Task { @MainActor [weak self] in self?.fifoHealthy = true }
        }

        // Capture before the Task so we don't race with a connect notification.
        let existing = GCController.controllers().first

        fireEngine.requireWoWFocus = requireWoWFocus
        fireEngine.onAccessibilityRevoked = { [weak self] in
            self?.hasAccessibility = false
            self?.stop()
        }
        firingObserver = fireEngine.$isFiring.sink { [weak self] firing in
            guard let self else { return }
            self.isFiring = firing
            guard self.isRunning else { return }
            if firing {
                self.statusMessage = "FIRING"
            } else if self.requireWoWFocus && !self.wowIsActive {
                self.statusMessage = "Active — waiting for WoW"
            } else if let name = self.activeGroupName {
                self.statusMessage = "Active — \(name)"
            }
        }

        // Defer @Published mutations out of init — ControllerManager is a @StateObject so
        // init runs during SwiftUI's first render pass. Any objectWillChange.send() here
        // triggers "Publishing changes from within view updates" warnings.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.hasAccessibility = KeySimulator.isAccessibilityEnabled
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
            self.dualSenseBattery.onUpdate = { [weak self] level, charging in
                guard let self else { return }
                self.batteryLevel = level
                self.batteryCharging = charging
                self.checkLowBattery(level: level, charging: charging)
            }
            self.dualSenseBattery.start()
            if let gc = existing { self.connectController(gc) }
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
        // stop() must precede controller = nil so clearButtonHandlers() can access the
        // gamepad and nil out pressedChangedHandler closures — otherwise they leak as
        // zombie handlers that silently capture the old bindings indefinitely.
        stop()
        controller = nil
        controllerName = nil
        isConnected = false
        lowBatteryNotified = false
        stopBatteryMonitoring()
        statusMessage = "Controller disconnected"
    }

    private func connectController(_ gc: GCController) {
        Self.logger.info("Controller connected: \(gc.vendorName ?? "unknown", privacy: .public)")
        controller = gc
        controllerName = gc.vendorName ?? "Controller"
        isConnected = true
        statusMessage = "Controller connected"
        startBatteryMonitoring()
        if isRunning, let bindings = activeBindings {
            attachHandlers(for: bindings)
        }
    }

    // MARK: - Permission Recheck

    private func setupPermissionRecheck() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        guard !hasAccessibility || !hasHelperAccessibility else { return }
        // Defer to avoid publishing @Published changes during a view update cycle.
        Task { @MainActor [weak self] in self?.checkAccessibility() }
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
        let wow = Self.isWoW(app)
        fireEngine.wowIsActive = wow
        wowIsActive = wow
    }

    private func refreshWoWFocus() {
        if let app = NSWorkspace.shared.frontmostApplication {
            let wow = Self.isWoW(app)
            fireEngine.wowIsActive = wow
            wowIsActive = wow
        }
    }

    private func updateStatusIfRunning() {
        guard isRunning, !isFiring else { return }
        if requireWoWFocus && !wowIsActive {
            statusMessage = "Active — waiting for WoW"
        } else if let name = activeGroupName {
            statusMessage = "Active — \(name)"
        }
    }

    private nonisolated(unsafe) static let wowBundleIDs: Set<String> = [
        "com.blizzard.worldofwarcraft",
        "com.blizzard.worldofwarcraftclassic",
        "com.blizzard.wow",
    ]

    // internal so tests can exercise directly; NSRunningApplication overload delegates here
    nonisolated static func isWoW(_ app: NSRunningApplication) -> Bool {
        isWoW(bundleID: app.bundleIdentifier, localizedName: app.localizedName)
    }

    nonisolated static func isWoW(bundleID: String?, localizedName: String?) -> Bool {
        if let id = bundleID?.lowercased(), wowBundleIDs.contains(id) { return true }
        if let name = localizedName?.lowercased(), name.contains("warcraft") { return true }
        return false
    }

    // MARK: - Battery Monitoring

    private func startBatteryMonitoring() {
        batteryTimer?.invalidate()
        // Poll immediately and every 30s. For DualSense, GCDeviceBattery always
        // returns 0; DualSenseBatteryMonitor handles it via HID input reports or
        // device property reads and writes batteryLevel directly through onUpdate.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.updateBattery()
            self?.dualSenseBattery.pollDeviceProperty()
        }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBattery()
                self?.dualSenseBattery.pollDeviceProperty()
            }
        }
    }

    /// Pure function so it can be unit-tested without a live ControllerManager.
    nonisolated static func shouldNotifyLowBattery(level: Float, charging: Bool, alreadyNotified: Bool) -> Bool {
        !charging && level <= 0.20 && !alreadyNotified
    }

    private func checkLowBattery(level: Float, charging: Bool) {
        if charging || level > 0.20 {
            lowBatteryNotified = false
            return
        }
        guard Self.shouldNotifyLowBattery(level: level, charging: charging, alreadyNotified: lowBatteryNotified) else { return }
        lowBatteryNotified = true
        let content = UNMutableNotificationContent()
        content.title = "Controller Battery Low"
        content.body = "DualSense is at \(Int(level * 100))% — plug in to keep playing."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "com.gsecontroller.lowbattery", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
        Self.logger.info("Low battery notification sent (\(Int(level * 100))%)")
    }

    private func stopBatteryMonitoring() {
        batteryTimer?.invalidate()
        batteryTimer = nil
        batteryLevel = nil
        batteryCharging = false
    }

    private func updateBattery() {
        guard let battery = controller?.battery else {
            batteryLevel = nil
            batteryCharging = false
            return
        }
        // Only overwrite if GCDeviceBattery has real data.
        // DualSense always returns 0 here; DualSenseBatteryMonitor handles it separately.
        if battery.batteryLevel > 0 {
            batteryLevel = battery.batteryLevel
            batteryCharging = battery.batteryState == .charging
        }
    }

    deinit {
        let timer = batteryTimer
        if Thread.isMainThread {
            timer?.invalidate()
        } else {
            DispatchQueue.main.async { timer?.invalidate() }
        }
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
        activeGroupName = group.name
        activeBindings = group.bindings
        isRunning = true
        KeySimulator.ensureHelper { [weak self] ready in
            self?.helperReady = ready
        }
        fireEngine.requireWoWFocus = requireWoWFocus
        refreshWoWFocus()
        Self.logger.info("Started group \"\(group.name, privacy: .public)\" with \(group.bindings.count) binding(s)")
        statusMessage = requireWoWFocus && !wowIsActive ? "Active — waiting for WoW" : "Active — \(group.name)"
        attachHandlers(for: group.bindings)
    }

    func stop() {
        fireEngine.stopAll()
        clearButtonHandlers()
        // Unconditionally release all modifiers — guards against modifier keys
        // getting stuck in WoW if stop() is called while a button is held.
        for modifier in KeyModifier.allCases where modifier != .none {
            KeySimulator.modifierUp(modifier)
        }
        isRunning = false
        activeGroupName = nil
        activeBindings = nil
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
        case .dpadUp:        gamepad.dpad.up
        }
    }

    private func attachHandlers(for bindings: [MacroBinding]) {
        guard let gamepad = controller?.extendedGamepad else { return }
        clearButtonHandlers()

        var seen = Set<ControllerButton>()
        for binding in bindings where seen.insert(binding.button).inserted {
            buttonInput(for: binding.button, on: gamepad)?.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor [weak self] in
                    self?.handleButton(binding: binding, pressed: pressed)
                }
            }
        }
    }

    private func clearButtonHandlers() {
        guard let gamepad = controller?.extendedGamepad else { return }
        let buttons = activeBindings?.map(\.button) ?? ControllerButton.allCases
        for button in buttons {
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
        Task.detached(priority: .userInitiated) { [weak self] in
            let helperAx = KeySimulator.isHelperAccessibilityEnabled
            await MainActor.run { self?.hasHelperAccessibility = helperAx }
        }
    }
}
