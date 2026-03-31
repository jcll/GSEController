import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct AppAlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class AppModel {
    private(set) var store: ProfileStore
    private(set) var controller: ControllerManager
    var activeAlert: AppAlertContext?

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
            self.controller = ControllerManager(defaults: defaults, testState: .init())
        } else {
            self.store = store ?? ProfileStore()
            self.controller = ControllerManager()
        }
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
    }

    func deleteGroup(_ group: ProfileGroup) {
        if controller.isRunning || controller.isStarting {
            controller.stop()
        }
        store.deleteGroup(group)
    }

    func startOrStopSelectedGroup() {
        if controller.isRunning {
            controller.stop()
            return
        }
        guard let group = store.activeGroup else { return }
        controller.start(group: group)
    }

    func exportProfiles() {
        do {
            let data = try store.exportData()
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "gsecontroller-profiles.json"
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

    func importProfiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        self.controller.stop()
                        try self.store.importData(data)
                    } catch {
                        self.activeAlert = AppAlertContext(title: "Import Failed", message: error.localizedDescription)
                    }
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.activeAlert = AppAlertContext(title: "Import Failed", message: error.localizedDescription)
                }
            }
        }
    }
}
