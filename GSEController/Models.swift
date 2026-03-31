import Foundation

// rawValues are stable internal keys (case name). Legacy display-string values
// (e.g. "R1", "A / Cross") are handled by the custom init(from:) below.
enum ControllerButton: String, CaseIterable, Identifiable {
    case rightShoulder
    case leftShoulder
    case rightTrigger
    case leftTrigger
    case buttonSouth
    case buttonEast
    case buttonWest
    case buttonNorth
    case l3
    case r3
    case dpadDown
    case dpadLeft
    case dpadRight
    case dpadUp

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
        case .dpadUp:        return "D-Pad ↑"
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
        case .dpadUp:        return "D↑"
        }
    }

    var isDpad: Bool {
        switch self {
        case .dpadDown, .dpadLeft, .dpadRight, .dpadUp: return true
        default: return false
        }
    }
}

extension ControllerButton: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let value = ControllerButton(rawValue: raw) {
            self = value
            return
        }
        // Migrate legacy display-string rawValues written by pre-ARCH-04 builds.
        switch raw {
        case "R1":           self = .rightShoulder
        case "L1":           self = .leftShoulder
        case "R2":           self = .rightTrigger
        case "L2":           self = .leftTrigger
        case "A / Cross":    self = .buttonSouth
        case "B / Circle":   self = .buttonEast
        case "X / Square":   self = .buttonWest
        case "Y / Triangle": self = .buttonNorth
        case "L3":           self = .l3
        case "R3":           self = .r3
        case "D-Pad ↓":     self = .dpadDown
        case "D-Pad ←":     self = .dpadLeft
        case "D-Pad →":     self = .dpadRight
        case "D-Pad ↑":     self = .dpadUp
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown ControllerButton raw value: \(raw)"
            )
        }
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
    /// Interval between key presses in milliseconds. Lower = faster.
    var rate: Double
    var label: String

    static func == (lhs: MacroBinding, rhs: MacroBinding) -> Bool {
        lhs.button == rhs.button &&
        lhs.keyName == rhs.keyName &&
        lhs.keyCode == rhs.keyCode &&
        lhs.modifier == rhs.modifier &&
        lhs.mode == rhs.mode &&
        lhs.rate == rhs.rate &&
        lhs.label == rhs.label
    }

    init(
        id: UUID = UUID(),
        button: ControllerButton,
        keyName: String = "K",
        keyCode: UInt16 = 0x28,
        modifier: KeyModifier = .none,
        mode: FireMode = .hold,
        rate: Double = 250.0,
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
        ("Slow", 340), ("Moderate", 300), ("Standard", 250),
        ("Fast", 200), ("Very Fast", 150), ("Ultra Fast", 100)
    ]

    var duplicateButtons: Set<ControllerButton> {
        bindings.duplicateButtons
    }

    var hasDuplicateButtons: Bool {
        !duplicateButtons.isEmpty
    }

    func withFreshIDs(name: String? = nil) -> ProfileGroup {
        ProfileGroup(
            id: UUID(),
            name: name ?? self.name,
            bindings: bindings.map { binding in
                var copy = binding
                copy.id = UUID()
                return copy
            }
        )
    }
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

    static let byName: [String: MacroKey] = Dictionary(uniqueKeysWithValues: allKeys.map { ($0.name, $0) })

    static func find(_ name: String) -> MacroKey? {
        byName[name]
    }
}

extension Array where Element == MacroBinding {
    var duplicateButtons: Set<ControllerButton> {
        var seen = Set<ControllerButton>()
        var duplicates = Set<ControllerButton>()
        for binding in self {
            if !seen.insert(binding.button).inserted {
                duplicates.insert(binding.button)
            }
        }
        return duplicates
    }
}
