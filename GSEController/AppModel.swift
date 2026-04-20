import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

// Lightweight alert payload used by ContentView so AppModel can surface
// user-facing failures without depending on view presentation details.
struct AppAlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

// Captures the file chosen for import plus a preview of what will change.
// ContentView uses this to gate destructive replace/merge imports behind a
// second confirmation step instead of mutating the store immediately.
struct ProfileImportPreview: Identifiable {
    let id = UUID()
    let mode: ProfileImportMode
    let groups: [ProfileGroup]
    let data: Data

    var title: String {
        switch mode {
        case .replace: return "Replace Profiles?"
        case .merge:   return "Merge Profiles?"
        }
    }

    var message: String {
        let names = groups.prefix(6).map(\.name).joined(separator: ", ")
        let suffix = groups.count > 6 ? ", and \(groups.count - 6) more" : ""
        return "\(groups.count) profile\(groups.count == 1 ? "" : "s"): \(names)\(suffix)"
    }
}

@MainActor
@Observable
final class AppModel {
    // AppModel is the application-level coordinator. It owns the persistent
    // profile store and the live controller runtime, and keeps AppKit panels,
    // import/export flows, and stop-before-mutate rules out of the view layer.
    private(set) var store: ProfileStore
    private(set) var controller: ControllerManager
    var activeAlert: AppAlertContext?
    var pendingImport: ProfileImportPreview?
    @ObservationIgnored private nonisolated(unsafe) var terminationObserver: NSObjectProtocol?

    init(
        store: ProfileStore? = nil,
        controller: ControllerManager? = nil
    ) {
        if let controller {
            self.controller = controller
            self.store = store ?? ProfileStore()
        } else if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let defaults = Self.uiTestDefaults()
            self.store = store ?? ProfileStore(defaults: defaults)
            self.controller = ControllerManager(
                defaults: defaults,
                keyInjector: UITestKeyInjector(),
                testState: .init()
            )
        } else {
            let simulator = KeySimulator()
            self.store = store ?? ProfileStore()
            self.controller = ControllerManager(
                keyInjector: KeySimulatorBridge(simulator: simulator)
            )
        }
        self.store.onSaveError = { [weak self] error in
            self?.activeAlert = AppAlertContext(
                title: "Save Failed",
                message: "Your profile changes could not be saved: \(error.localizedDescription)"
            )
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.store.flushPendingSave()
            }
        }
    }

    deinit {
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        MainActor.assumeIsolated { store.flushPendingSave() }
    }

    func onAppear() {
        controller.checkAccessibility()
    }

    private static func uiTestDefaults() -> UserDefaults {
        let suiteName = ProcessInfo.processInfo.environment["UITEST_DEFAULTS_SUITE"]
            ?? "com.test.gsecontroller.ui"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(false, forKey: "requireWoWFocus")
        return defaults
    }

    func selectGroup(_ id: UUID?) {
        if controller.isRunning || controller.isStarting {
            controller.stop()
        }
        store.activeGroupId = id
    }

    func saveGroup(_ group: ProfileGroup) {
        store.upsertGroup(group)
        store.flushPendingSave()
    }

    func addGroup(_ group: ProfileGroup) {
        if controller.isRunning || controller.isStarting {
            controller.stop()
        }
        _ = store.addGroup(group, activateAfterAdd: true)
        store.flushPendingSave()
    }

    func duplicateGroup(_ group: ProfileGroup) {
        if controller.isRunning || controller.isStarting {
            controller.stop()
        }
        _ = store.duplicateGroup(group)
        store.flushPendingSave()
    }

    func deleteGroup(_ group: ProfileGroup) {
        if controller.isRunning || controller.isStarting {
            controller.stop()
        }
        if controller.lastStartedGroupName == group.name {
            controller.lastStartedGroupName = nil
        }
        store.deleteGroup(group)
        store.flushPendingSave()
    }

    func startOrStopSelectedGroup() {
        if controller.isRunning {
            controller.stop()
            return
        }
        guard let group = store.activeGroup else { return }
        controller.start(group: group)
    }

    func releaseAllInput() {
        controller.releaseAllInput()
    }

    func exportProfiles(group: ProfileGroup? = nil) {
        do {
            let groups = group.map { [$0] }
            let data = try store.exportData(groups: groups)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = group.map { "\(Self.fileSlug(for: $0.name))-profile.json" }
                ?? "gsecontroller-profiles.json"
            panel.begin { [weak self] response in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try data.write(to: url, options: .atomic)
                } catch {
                    Task { @MainActor [weak self] in
                        self?.activeAlert = AppAlertContext(title: "Export Failed", message: error.localizedDescription)
                    }
                }
            }
        } catch {
            activeAlert = AppAlertContext(title: "Export Failed", message: error.localizedDescription)
        }
    }

    func importProfiles(mode: ProfileImportMode = .replace) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    let data = try Data(contentsOf: url)
                    await MainActor.run {
                        do {
                            let groups = try ProfileStore.decodeImportData(data)
                            self?.pendingImport = ProfileImportPreview(mode: mode, groups: groups, data: data)
                        } catch {
                            self?.activeAlert = AppAlertContext(title: "Import Failed", message: error.localizedDescription)
                        }
                    }
                } catch {
                    await MainActor.run {
                        self?.activeAlert = AppAlertContext(title: "Import Failed", message: error.localizedDescription)
                    }
                }
            }
        }
    }

    func confirmPendingImport() {
        guard let pendingImport else { return }
        do {
            controller.stop()
            try store.importData(pendingImport.data, mode: pendingImport.mode)
            store.flushPendingSave()
            self.pendingImport = nil
        } catch {
            activeAlert = AppAlertContext(title: "Import Failed", message: error.localizedDescription)
        }
    }

    func cancelPendingImport() {
        pendingImport = nil
    }

    private static func fileSlug(for name: String) -> String {
        let pieces = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return pieces.isEmpty ? "gsecontroller" : pieces.joined(separator: "-")
    }
}
