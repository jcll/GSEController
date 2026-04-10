import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

struct AppAlertContext: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

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
    private(set) var store: ProfileStore
    private(set) var controller: ControllerManager
    var activeAlert: AppAlertContext?
    var pendingImport: ProfileImportPreview?

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

    func duplicateGroup(_ group: ProfileGroup) {
        _ = store.duplicateGroup(group)
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
            do {
                let data = try Data(contentsOf: url)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        let groups = try ProfileStore.decodeImportData(data)
                        self.pendingImport = ProfileImportPreview(mode: mode, groups: groups, data: data)
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

    func confirmPendingImport() {
        guard let pendingImport else { return }
        do {
            controller.stop()
            try store.importData(pendingImport.data, mode: pendingImport.mode)
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
