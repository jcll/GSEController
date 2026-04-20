import Foundation
import Observation
import os

// Persistence and migration layer for profile data. The rest of the app treats
// this as the single source of truth for saved groups and active selection.
enum ProfileStoreError: LocalizedError, Equatable {
    case emptyImport

    var errorDescription: String? {
        switch self {
        case .emptyImport:
            return "The selected JSON file does not contain any profiles to import."
        }
    }
}

enum ProfileImportMode {
    case replace
    case merge

    var actionTitle: String {
        switch self {
        case .replace: return "Replace Profiles"
        case .merge:   return "Merge Profiles"
        }
    }
}

@MainActor
@Observable
final class ProfileStore {
    var groups: [ProfileGroup] {
        didSet { scheduleSave() }
    }
    var activeGroupId: UUID? {
        didSet { scheduleSave() }
    }

    var activeGroup: ProfileGroup? {
        groups.first { $0.id == activeGroupId }
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.gsecontroller", category: "ProfileStore")
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    var onSaveError: ((Error) -> Void)?

    deinit {
        MainActor.assumeIsolated { flushPendingSave() }
    }

    convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let oldData = defaults.data(forKey: "profiles"),
           let oldProfiles = try? JSONDecoder().decode([_LegacyMacroProfile].self, from: oldData) {
            var migrated = oldProfiles.map { p in
                ProfileGroup(
                    id: p.id,
                    name: p.name,
                    bindings: [MacroBinding(
                        button: p.button,
                        keyName: p.keyName,
                        keyCode: p.keyCode,
                        modifier: .none,
                        mode: .hold,
                        rate: (1000.0 / p.rate).rounded()
                    )]
                )
            }
            Self.normalizeBindings(&migrated)
            groups = migrated
            activeGroupId = migrated.first?.id
            defaults.removeObject(forKey: "profiles")
            defaults.removeObject(forKey: "activeProfileId")
            save()
            return
        }

        let defaultGroup = ProfileGroup(
            name: "Guardian Druid",
            bindings: [MacroBinding(
                button: .rightShoulder,
                keyName: "K",
                keyCode: 0x28,
                mode: .hold,
                rate: 250
            )]
        )

        if let data = defaults.data(forKey: "groups") {
            do {
                var decoded = try JSONDecoder().decode([ProfileGroup].self, from: data)
                Self.migrateRatesToMs(&decoded)
                Self.normalizeBindings(&decoded)
                groups = decoded
                if let idStr = defaults.string(forKey: "activeGroupId"),
                   let id = UUID(uuidString: idStr),
                   decoded.contains(where: { $0.id == id }) {
                    activeGroupId = id
                } else {
                    activeGroupId = decoded.first?.id
                }
            } catch {
                Self.logger.error("Failed to decode saved groups: \(error.localizedDescription). Backing up to 'groups_backup'.")
                defaults.set(data, forKey: "groups_backup")
                groups = [defaultGroup]
                activeGroupId = defaultGroup.id
                save()
            }
        } else {
            groups = [defaultGroup]
            activeGroupId = defaultGroup.id
        }
    }

    @discardableResult
    func addGroup(_ group: ProfileGroup, activateAfterAdd: Bool = true, ensureUniqueName: Bool = true) -> ProfileGroup {
        var groupToAdd = group
        if ensureUniqueName {
            groupToAdd.name = uniqueName(for: groupToAdd.name)
        }
        groups.append(groupToAdd)
        if activateAfterAdd {
            activeGroupId = groupToAdd.id
        }
        return groupToAdd
    }

    func upsertGroup(_ group: ProfileGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        var groupToSave = group
        let existingNames = Set(groups.map(\.name)).subtracting([groups[index].name])
        if existingNames.contains(groupToSave.name) {
            groupToSave.name = Self.uniqueName(for: groupToSave.name, existingNames: existingNames)
        }
        groups[index] = groupToSave
    }

    func deleteGroup(_ group: ProfileGroup) {
        groups.removeAll { $0.id == group.id }
        if activeGroupId == group.id {
            activeGroupId = groups.first?.id
        }
    }

    @discardableResult
    func duplicateGroup(_ group: ProfileGroup) -> ProfileGroup {
        let copy = group.withFreshIDs(name: uniqueName(for: "\(group.name) Copy"))
        return addGroup(copy, ensureUniqueName: false)
    }

    func exportData(groups groupsToExport: [ProfileGroup]? = nil) throws -> Data {
        let payload = groupsToExport ?? groups
        let envelope = ["version": 1, "profiles": payload] as [String: Any]
        return try JSONSerialization.data(withJSONObject: envelope, options: .prettyPrinted)
    }

    func importData(_ data: Data, mode: ProfileImportMode = .replace) throws {
        let imported = try Self.decodeImportData(data)

        switch mode {
        case .replace:
            let previousId = activeGroupId
            groups = imported
            if let previousId, imported.contains(where: { $0.id == previousId }) {
                activeGroupId = previousId
            } else {
                activeGroupId = imported.first?.id
            }
        case .merge:
            var existingNames = Set(groups.map(\.name))
            let merged = imported.map { group in
                let name = Self.uniqueName(for: group.name, existingNames: existingNames)
                existingNames.insert(name)
                return group.withFreshIDs(name: name)
            }
            groups.append(contentsOf: merged)
            if let firstImported = merged.first {
                activeGroupId = firstImported.id
            }
        }
    }

    static func decodeImportData(_ data: Data) throws -> [ProfileGroup] {
        var imported = try JSONDecoder().decode([ProfileGroup].self, from: data)
        guard !imported.isEmpty else {
            throw ProfileStoreError.emptyImport
        }
        migrateRatesToMs(&imported)
        normalizeBindings(&imported)
        for group in imported {
            guard !group.bindings.isEmpty else {
                throw ProfileStoreError.emptyImport
            }
            guard group.duplicateButtons.isEmpty else {
                throw ProfileStoreError.emptyImport
            }
            for binding in group.bindings {
                guard binding.rate >= 33 && binding.rate <= 1000 else {
                    throw ProfileStoreError.emptyImport
                }
            }
        }
        return imported
    }

    private static func migrateRatesToMs(_ groups: inout [ProfileGroup]) {
        for i in groups.indices {
            for j in groups[i].bindings.indices {
                let rate = groups[i].bindings[j].rate
                if rate > 0 && rate <= 30 {
                    groups[i].bindings[j].rate = (1000.0 / rate).rounded()
                }
            }
        }
    }

    private static func normalizeBindings(_ groups: inout [ProfileGroup]) {
        for i in groups.indices {
            for j in groups[i].bindings.indices {
                groups[i].bindings[j].normalizeForPersistence()
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                self?.save()
            } catch is CancellationError {
            } catch {
                Self.logger.error("scheduleSave failed: \(error.localizedDescription)")
            }
        }
    }

    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(groups)
            defaults.set(data, forKey: "groups")
            defaults.set(activeGroupId?.uuidString, forKey: "activeGroupId")
        } catch {
            Self.logger.error("Failed to encode groups: \(error.localizedDescription)")
            onSaveError?(error)
        }
    }

    private func uniqueName(for baseName: String) -> String {
        Self.uniqueName(for: baseName, existingNames: Set(groups.map(\.name)))
    }

    private static func uniqueName(for baseName: String, existingNames: Set<String>) -> String {
        guard existingNames.contains(baseName) else { return baseName }
        var counter = 2
        while existingNames.contains("\(baseName) \(counter)") {
            counter += 1
        }
        return "\(baseName) \(counter)"
    }
}

struct _LegacyMacroProfile: Codable {
    var id: UUID
    var name: String
    var button: ControllerButton
    var keyName: String
    var keyCode: UInt16
    var rate: Double
}
