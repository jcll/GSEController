import Foundation
import GameController
import AppKit
import Observation
import os
import UserNotifications

/// Tracks whether World of Warcraft is the frontmost application and updates
/// the shared RuntimeConfiguration accordingly. ControllerManager observes
/// focus changes via the onFocusChanged callback.
@MainActor
final class FocusTracker {
    private let runtimeConfig: RuntimeConfiguration
    var onFocusChanged: ((Bool) -> Void)?

    init(runtimeConfig: RuntimeConfiguration) {
        self.runtimeConfig = runtimeConfig
        setupAppTracking()
    }

    private func setupAppTracking() {
        refreshWoWFocus()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
    }

    @objc private func activeAppChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        let wow = FocusTracker.isWoW(app)
        runtimeConfig.wowIsActive = wow
        onFocusChanged?(wow)
    }

    func refreshWoWFocus() {
        if let app = NSWorkspace.shared.frontmostApplication {
            let wow = FocusTracker.isWoW(app)
            runtimeConfig.wowIsActive = wow
            onFocusChanged?(wow)
        }
    }

    private nonisolated static let wowBundleIDs: Set<String> = [
        "com.blizzard.worldofwarcraft",
        "com.blizzard.worldofwarcraftclassic",
        "com.blizzard.wow",
    ]

    nonisolated static func isWoW(_ app: NSRunningApplication) -> Bool {
        isWoW(bundleID: app.bundleIdentifier, localizedName: app.localizedName)
    }

    nonisolated static func isWoW(bundleID: String?, localizedName: String?) -> Bool {
        if let id = bundleID?.lowercased(), wowBundleIDs.contains(id) { return true }
        if let name = localizedName?.lowercased(), name.contains("warcraft") { return true }
        return false
    }
}

@MainActor
@Observable
final class ControllerManager {
    // Bridges the GameController framework, key helper lifecycle, permission
    // state, WoW focus tracking, and battery reporting into a single runtime
    // object the UI can observe.
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.gsecontroller", category: "ControllerManager")

    var controllerName: String?
    var isConnected = false
    var isFiring = false
    var isRunning = false
    var isStarting = false
    var statusMessage = "Ready"
    var hasAccessibility = false
    var hasHelperAccessibility = false
    var batteryLevel: Float? = nil
    var batteryCharging = false
    var helperReady = true
    var helperSetupFailed = false
    var fifoHealthy = true
    var lastStartedGroupName: String?

    private let runtimeConfig = RuntimeConfiguration()
    var wowIsActive: Bool { runtimeConfig.wowIsActive }
    var requireWoWFocus: Bool {
        get { runtimeConfig.requireWoWFocus }
        set {
            runtimeConfig.requireWoWFocus = newValue
            defaults.set(newValue, forKey: "requireWoWFocus")
            if newValue && !runtimeConfig.wowIsActive {
                fireEngine.stopAll()
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let keyInjector: KeyInjecting
    @ObservationIgnored private let fireEngine: FireEngine
    @ObservationIgnored private let focusTracker: FocusTracker
    @ObservationIgnored private var controller: GCController?
    @ObservationIgnored private var activeGroupName: String?
    @ObservationIgnored private var activeBindings: [MacroBinding]?
    @ObservationIgnored private var startRequestID = UUID()
    // nonisolated(unsafe) so deinit can invalidate it without a MainActor hop
    @ObservationIgnored nonisolated(unsafe) private var batteryTimer: Timer?
    @ObservationIgnored private var batteryUpdateGeneration = UUID()
    @ObservationIgnored private let dualSenseBattery = DualSenseBatteryMonitor()
    @ObservationIgnored private var lowBatteryNotified = false

    var keyHelperDiagnostics: KeyHelperDiagnostics {
        keyInjector.diagnostics
    }

    struct TestState {
        var controllerName: String = "Test Controller"
        var isConnected: Bool = true
        var hasAccessibility: Bool = true
        var hasHelperAccessibility: Bool = true
        var helperReady: Bool = true
    }

    init(
        defaults: UserDefaults = .standard,
        keyInjector: KeyInjecting = KeySimulatorBridge(simulator: KeySimulator()),
        testState: TestState? = nil
    ) {
        self.defaults = defaults
        self.keyInjector = keyInjector
        self.fireEngine = FireEngine(runtimeConfig: runtimeConfig, keyInjector: keyInjector)
        self.focusTracker = FocusTracker(runtimeConfig: runtimeConfig)
        self.requireWoWFocus = defaults.object(forKey: "requireWoWFocus") as? Bool ?? true

        if testState == nil {
            GCController.shouldMonitorBackgroundEvents = true
            setupNotifications()
            setupPermissionRecheck()
        }

        focusTracker.onFocusChanged = { [weak self] wow in
            guard let self else { return }
            if !wow && self.requireWoWFocus {
                self.fireEngine.stopAll()
            }
            self.updateStatusIfRunning()
        }

        if testState == nil {
            helperReady = false
            helperSetupFailed = false
            keyInjector.ensureHelper { [weak self] ready in
                self?.helperReady = ready
                self?.helperSetupFailed = !ready
            }
            keyInjector.onFIFOFailure = { [weak self] in
                Task { @MainActor [weak self] in self?.fifoHealthy = false }
            }
            keyInjector.onFIFORecovered = { [weak self] in
                Task { @MainActor [weak self] in self?.fifoHealthy = true }
            }
        }

        let existing = testState == nil ? GCController.controllers().first : nil

        fireEngine.onAccessibilityRevoked = { [weak self] in
            self?.hasAccessibility = false
            self?.stop()
        }
        fireEngine.onFiringChanged = { [weak self] firing in
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

        if let testState {
            self.controllerName = testState.controllerName
            self.isConnected = testState.isConnected
            self.hasAccessibility = testState.hasAccessibility
            self.hasHelperAccessibility = testState.hasHelperAccessibility
            self.helperReady = testState.helperReady
            self.helperSetupFailed = !testState.helperReady
            self.statusMessage = testState.isConnected ? "Controller connected" : "No controller connected"
            return
        }

        // Defer observable mutations out of init — ContentView stores ControllerManager
        // inside @State via AppModel, so init still runs during SwiftUI's first render pass.
        // Mutating tracked state here can still trigger update-cycle warnings.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.hasAccessibility = self.keyInjector.isAccessibilityEnabled
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
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
        if GCController.controllers().isEmpty {
            GCController.startWirelessControllerDiscovery {}
        }
    }

    @objc private func controllerConnected(_ notification: Notification) {
        if let gc = notification.object as? GCController {
            connectController(gc)
        }
    }

    @objc private func controllerDisconnected(_ notification: Notification) {
        guard let disconnectedController = notification.object as? GCController else { return }
        guard let trackedController = controller, trackedController === disconnectedController else {
            Self.logger.info("Ignoring disconnect for untracked controller")
            return
        }
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
        if let replacement = GCController.controllers().first(where: { $0 !== disconnectedController }) {
            connectController(replacement)
        }
    }

    private func connectController(_ gc: GCController) {
        guard controller == nil else { return }
        Self.logger.info("Controller connected: \(gc.vendorName ?? "unknown", privacy: .public)")
        controller = gc
        controllerName = gc.vendorName ?? "Controller"
        isConnected = true
        statusMessage = "Controller connected"
        GCController.stopWirelessControllerDiscovery()
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

    @objc func appDidBecomeActive() {
        // Defer to avoid observable mutations during a view update cycle.
        Task { @MainActor [weak self] in self?.checkAccessibility() }
    }

    private func updateStatusIfRunning() {
        guard isRunning, !isFiring else { return }
        if requireWoWFocus && !wowIsActive {
            statusMessage = "Active — waiting for WoW"
        } else if let name = activeGroupName {
            statusMessage = "Active — \(name)"
        }
    }

    // MARK: - Battery Monitoring

    private func startBatteryMonitoring() {
        batteryTimer?.invalidate()
        let generation = UUID()
        batteryUpdateGeneration = generation
        dualSenseBattery.onUpdate = { [weak self] level, charging in
            guard let self, self.batteryUpdateGeneration == generation, self.isConnected else { return }
            self.batteryLevel = level
            self.batteryCharging = charging
            self.checkLowBattery(level: level, charging: charging)
        }
        // Poll immediately and every 30s. For DualSense, GCDeviceBattery always
        // returns 0; DualSenseBatteryMonitor handles it via HID input reports or
        // device property reads and writes batteryLevel directly through onUpdate.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.updateBattery()
            self?.dualSenseBattery.pollDevicePropertyAsync()
        }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBattery()
                self?.dualSenseBattery.pollDevicePropertyAsync()
            }
        }
    }

    /// Pure function so it can be unit-tested without a live ControllerManager.
    nonisolated static func shouldNotifyLowBattery(level: Float, charging: Bool, alreadyNotified: Bool) -> Bool {
        !charging && level <= 0.20 && !alreadyNotified
    }

    nonisolated static func shouldResetLowBatteryNotification(level: Float, charging: Bool) -> Bool {
        charging || level > 0.25
    }

    private func checkLowBattery(level: Float, charging: Bool) {
        if Self.shouldResetLowBatteryNotification(level: level, charging: charging) {
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
        batteryUpdateGeneration = UUID()
        dualSenseBattery.onUpdate = nil
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
        MainActor.assumeIsolated {
            dualSenseBattery.onUpdate = nil
            dualSenseBattery.stop()
        }
        if Thread.isMainThread {
            timer?.invalidate()
        } else {
            DispatchQueue.main.async { timer?.invalidate() }
        }
    }

    // MARK: - Start / Stop

    func start(group: ProfileGroup) {
        guard !isRunning && !isStarting else { return }
        let duplicateButtons = group.duplicateButtons
        guard duplicateButtons.isEmpty else {
            statusMessage = "Resolve duplicate button assignments before starting"
            return
        }
        guard isConnected else {
            statusMessage = "No controller connected"
            return
        }
        hasAccessibility = keyInjector.isAccessibilityEnabled
        guard hasAccessibility else {
            keyInjector.requestAccessibility()
            statusMessage = "Grant Accessibility access, then try again"
            return
        }

        let requestID = UUID()
        startRequestID = requestID
        isStarting = true
        statusMessage = "Starting helper…"
        fireEngine.seedAXState(hasAccessibility)
        focusTracker.refreshWoWFocus()
        keyInjector.ensureHelper { [weak self] ready in
            guard let self, self.startRequestID == requestID else { return }
            self.helperReady = ready
            self.helperSetupFailed = !ready
            self.isStarting = false
            guard ready else {
                self.isRunning = false
                self.activeGroupName = nil
                self.activeBindings = nil
                self.statusMessage = "Key helper failed to compile"
                return
            }

            self.hasHelperAccessibility = self.keyInjector.isHelperAccessibilityEnabled
            guard self.hasHelperAccessibility else {
                self.statusMessage = "Grant Key Helper Accessibility access, then try again"
                self.isRunning = false
                self.activeGroupName = nil
                self.activeBindings = nil
                return
            }

            self.activeGroupName = group.name
            self.lastStartedGroupName = group.name
            self.activeBindings = group.bindings
            self.isRunning = true
            Self.logger.info("Started group \"\(group.name, privacy: .public)\" with \(group.bindings.count) binding(s)")
            self.statusMessage = self.requireWoWFocus && !self.wowIsActive ? "Active — waiting for WoW" : "Active — \(group.name)"
            self.attachHandlers(for: group.bindings)
        }
    }

    func stop() {
        startRequestID = UUID()
        isStarting = false
        lastStartedGroupName = nil
        fireEngine.stopAll()
        clearButtonHandlers()
        // Unconditionally release all modifiers — guards against modifier keys
        // getting stuck in WoW if stop() is called while a button is held.
        for modifier in KeyModifier.allCases where modifier != .none {
            keyInjector.modifierUp(modifier)
        }
        isRunning = false
        activeGroupName = nil
        activeBindings = nil
        if isConnected {
            statusMessage = "Stopped"
        }
    }

    func releaseAllInput() {
        stop()
        statusMessage = "Released all held keys"
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
                self?.handleButton(binding: binding, pressed: pressed)
            }
        }
    }

    private func clearButtonHandlers() {
        guard let gamepad = controller?.extendedGamepad else { return }
        let buttons = activeBindings?.map(\.button) ?? []
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
                fireEngine.tap(binding: binding)
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
        // The app and helper can have different TCC states, so always query
        // them independently instead of inferring one from the other.
        hasAccessibility = keyInjector.isAccessibilityEnabled
        let injector = keyInjector
        Task.detached(priority: .userInitiated) { [weak self] in
            let helperAx = injector.isHelperAccessibilityEnabled
            await MainActor.run { self?.hasHelperAccessibility = helperAx }
        }
    }

    func retryHelperSetup() {
        helperReady = false
        helperSetupFailed = false
        statusMessage = "Preparing key helper…"
        keyInjector.ensureHelper { [weak self] ready in
            self?.helperReady = ready
            self?.helperSetupFailed = !ready
            if !ready {
                self?.statusMessage = "Key helper failed to compile"
            } else if self?.isConnected == true {
                self?.statusMessage = "Controller connected"
            }
        }
    }

    func openHelperAccessibilitySettings() {
        keyInjector.openAccessibilitySettings()
        keyInjector.revealHelperInFinder()
    }

    func requestHelperAccessibilityPermission() {
        // The helper is the process that posts CGEvents, so it needs its own
        // trust prompt and Finder reveal path.
        keyInjector.requestHelperAccessibility()
        keyInjector.openAccessibilitySettings()
        keyInjector.revealHelperInFinder()
    }

    func revealHelperInFinder() {
        keyInjector.revealHelperInFinder()
    }

    func openHelperLogFolder() {
        let logURL = URL(fileURLWithPath: keyInjector.diagnostics.logPath)
        NSWorkspace.shared.selectFile(logURL.path, inFileViewerRootedAtPath: logURL.deletingLastPathComponent().path)
    }

    func requestAccessibilityPermission() {
        keyInjector.requestAccessibility()
    }
}
