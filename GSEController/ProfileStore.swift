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

    convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let oldData = defaults.data(forKey: "profiles"),
           let oldProfiles = try? JSONDecoder().decode([_LegacyMacroProfile].self, from: oldData) {
            let migrated = oldProfiles.map { p in
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
            }
        } else {
            groups = [defaultGroup]
            activeGroupId = defaultGroup.id
        }
    }

    @discardableResult
    func addGroup(_ group: ProfileGroup, activateAfterAdd: Bool = true) -> ProfileGroup {
        groups.append(group)
        if activateAfterAdd {
            activeGroupId = group.id
        }
        return group
    }

    func upsertGroup(_ group: ProfileGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index] = group
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
        return addGroup(copy)
    }

    func exportData(groups groupsToExport: [ProfileGroup]? = nil) throws -> Data {
        let payload = groupsToExport ?? groups
        return try JSONEncoder().encode(payload)
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

    private func save() {
        do {
            let data = try JSONEncoder().encode(groups)
            defaults.set(data, forKey: "groups")
            defaults.set(activeGroupId?.uuidString, forKey: "activeGroupId")
        } catch {
            Self.logger.error("Failed to encode groups: \(error.localizedDescription)")
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
