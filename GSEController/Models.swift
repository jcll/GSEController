import Foundation
import os

enum ControllerButton: String, CaseIterable, Codable, Identifiable {
    case rightShoulder = "R1"
    case leftShoulder = "L1"
    case rightTrigger = "R2"
    case leftTrigger = "L2"
    case buttonSouth = "A / Cross"
    case buttonEast = "B / Circle"
    case buttonWest = "X / Square"
    case buttonNorth = "Y / Triangle"
    case l3 = "L3"
    case r3 = "R3"
    case dpadDown = "dpadDown"
    case dpadLeft = "dpadLeft"
    case dpadRight = "dpadRight"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightShoulder: return "R1"
        case .leftShoulder:  return "L1"
        case .rightTrigger:  return "R2"
        case .leftTrigger:   return "L2"
        case .buttonSouth:   return "A / Cross"
        case .buttonEast:    return "B / Circle"
        case .buttonWest:    return "X / Square"
        case .buttonNorth:   return "Y / Triangle"
        case .l3:            return "L3"
        case .r3:            return "R3"
        case .dpadDown:      return "D-Pad ↓"
        case .dpadLeft:      return "D-Pad ←"
        case .dpadRight:     return "D-Pad →"
        }
    }

    var mapLabel: String {
        switch self {
        case .rightShoulder: return "R1"
        case .leftShoulder:  return "L1"
        case .rightTrigger:  return "R2"
        case .leftTrigger:   return "L2"
        case .buttonSouth:   return "A"
        case .buttonEast:    return "B"
        case .buttonWest:    return "X"
        case .buttonNorth:   return "Y"
        case .l3:            return "L3"
        case .r3:            return "R3"
        case .dpadDown:      return "D↓"
        case .dpadLeft:      return "D←"
        case .dpadRight:     return "D→"
        }
    }

    var isDpad: Bool {
        self == .dpadDown || self == .dpadLeft || self == .dpadRight
    }
}

enum KeyModifier: String, Codable, CaseIterable, Identifiable {
    case none, alt, shift, ctrl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:  return "None"
        case .alt:   return "Alt"
        case .shift: return "Shift"
        case .ctrl:  return "Ctrl"
        }
    }

    // macOS virtual key code for the modifier key itself
    var keyCode: UInt16 {
        switch self {
        case .none:  return 0
        case .alt:   return 0x3A  // left Option
        case .shift: return 0x38  // left Shift
        case .ctrl:  return 0x3B  // left Ctrl
        }
    }
}

enum FireMode: String, Codable {
    case hold         // continuous spam while button held
    case tap          // fires key once per press
    case modifierHold // holds a modifier key down while button held
}

struct MacroBinding: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var button: ControllerButton
    var keyName: String
    var keyCode: UInt16
    var modifier: KeyModifier
    var mode: FireMode
    var rate: Double
    var label: String

    init(
        id: UUID = UUID(),
        button: ControllerButton,
        keyName: String = "K",
        keyCode: UInt16 = 0x28,
        modifier: KeyModifier = .none,
        mode: FireMode = .hold,
        rate: Double = 10.0,
        label: String = ""
    ) {
        self.id = id
        self.button = button
        self.keyName = keyName
        self.keyCode = keyCode
        self.modifier = modifier
        self.mode = mode
        self.rate = rate
        self.label = label
    }
}

struct ProfileGroup: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var bindings: [MacroBinding] = []

    static let ratePresets: [(label: String, value: Double)] = [
        ("Slow", 6), ("Standard", 10), ("Fast", 15), ("Very Fast", 20)
    ]
}

// MARK: - MacroKey

struct MacroKey: Identifiable, Hashable, Codable {
    let name: String
    let keyCode: UInt16
    var id: String { name }

    static let allKeys: [MacroKey] = [
        .init(name: "1", keyCode: 0x12), .init(name: "2", keyCode: 0x13),
        .init(name: "3", keyCode: 0x14), .init(name: "4", keyCode: 0x15),
        .init(name: "5", keyCode: 0x17), .init(name: "6", keyCode: 0x16),
        .init(name: "7", keyCode: 0x1A), .init(name: "8", keyCode: 0x1C),
        .init(name: "9", keyCode: 0x19), .init(name: "0", keyCode: 0x1D),
        .init(name: "A", keyCode: 0x00), .init(name: "B", keyCode: 0x0B),
        .init(name: "C", keyCode: 0x08), .init(name: "D", keyCode: 0x02),
        .init(name: "E", keyCode: 0x0E), .init(name: "F", keyCode: 0x03),
        .init(name: "G", keyCode: 0x05), .init(name: "H", keyCode: 0x04),
        .init(name: "I", keyCode: 0x22), .init(name: "J", keyCode: 0x26),
        .init(name: "K", keyCode: 0x28), .init(name: "L", keyCode: 0x25),
        .init(name: "M", keyCode: 0x2E), .init(name: "N", keyCode: 0x2D),
        .init(name: "O", keyCode: 0x1F), .init(name: "P", keyCode: 0x23),
        .init(name: "Q", keyCode: 0x0C), .init(name: "R", keyCode: 0x0F),
        .init(name: "S", keyCode: 0x01), .init(name: "T", keyCode: 0x11),
        .init(name: "U", keyCode: 0x20), .init(name: "V", keyCode: 0x09),
        .init(name: "W", keyCode: 0x0D), .init(name: "X", keyCode: 0x07),
        .init(name: "Y", keyCode: 0x10), .init(name: "Z", keyCode: 0x06),
        .init(name: "F1", keyCode: 0x7A), .init(name: "F2", keyCode: 0x78),
        .init(name: "F3", keyCode: 0x63), .init(name: "F4", keyCode: 0x76),
        .init(name: "F5", keyCode: 0x60), .init(name: "F6", keyCode: 0x61),
        .init(name: "F7", keyCode: 0x62), .init(name: "F8", keyCode: 0x64),
        .init(name: "F9", keyCode: 0x65), .init(name: "F10", keyCode: 0x6D),
        .init(name: "F11", keyCode: 0x67), .init(name: "F12", keyCode: 0x6F),
        .init(name: "Space", keyCode: 0x31), .init(name: "Tab", keyCode: 0x30),
        .init(name: "-", keyCode: 0x1B), .init(name: "=", keyCode: 0x18),
        .init(name: "`", keyCode: 0x32),
    ]

    static func find(_ name: String) -> MacroKey? {
        allKeys.first { $0.name == name }
    }
}

// MARK: - ProfileStore

class ProfileStore: ObservableObject {
    @Published var groups: [ProfileGroup] {
        didSet { save() }
    }
    @Published var activeGroupId: UUID? {
        didSet { save() }
    }

    var activeGroup: ProfileGroup? {
        groups.first { $0.id == activeGroupId }
    }

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.gsecontroller", category: "ProfileStore")

    init() {
        // Migration from pre-1.x "profiles" UserDefaults key
        if let oldData = UserDefaults.standard.data(forKey: "profiles"),
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
                        rate: p.rate
                    )]
                )
            }
            groups = migrated
            activeGroupId = migrated.first?.id
            UserDefaults.standard.removeObject(forKey: "profiles")
            UserDefaults.standard.removeObject(forKey: "activeProfileId")
            save()
        } else if let data = UserDefaults.standard.data(forKey: "groups"),
                  let decoded = try? JSONDecoder().decode([ProfileGroup].self, from: data) {
            groups = decoded
            if let idStr = UserDefaults.standard.string(forKey: "activeGroupId"),
               let id = UUID(uuidString: idStr),
               decoded.contains(where: { $0.id == id }) {
                activeGroupId = id
            } else {
                activeGroupId = decoded.first?.id
            }
        } else {
            let defaultGroup = ProfileGroup(
                name: "Guardian Druid",
                bindings: [MacroBinding(
                    button: .rightShoulder,
                    keyName: "K",
                    keyCode: 0x28,
                    mode: .hold,
                    rate: 10
                )]
            )
            groups = [defaultGroup]
            activeGroupId = defaultGroup.id
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(groups)
            UserDefaults.standard.set(data, forKey: "groups")
            UserDefaults.standard.set(activeGroupId?.uuidString, forKey: "activeGroupId")
        } catch {
            Self.logger.error("Failed to encode groups: \(error.localizedDescription)")
        }
    }

    func addGroup(_ group: ProfileGroup) {
        groups.append(group)
        activeGroupId = group.id
    }

    func deleteGroup(_ group: ProfileGroup) {
        groups.removeAll { $0.id == group.id }
        if activeGroupId == group.id {
            activeGroupId = groups.first?.id
        }
    }
}

// Used only to decode legacy UserDefaults data written by pre-1.x versions.
private struct _LegacyMacroProfile: Decodable {
    var id: UUID
    var name: String
    var button: ControllerButton
    var keyName: String
    var keyCode: UInt16
    var rate: Double
}
