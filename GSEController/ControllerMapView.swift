import SwiftUI

// MARK: - Controller Map View

// Compact visual summary of the current bindings. This is intentionally read-
// only and lossless enough to answer "what does each button do?" at a glance
// while editing a profile.
struct ControllerMapView: View {
    let bindings: [MacroBinding]

    private static let faceButtons: [ControllerButton] = [.buttonNorth, .buttonWest, .buttonEast, .buttonSouth, .l3, .r3]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !bindings.isEmpty {
                HStack(spacing: 12) {
                    legendDot(.green, "Rapid")
                    legendDot(.blue, "Tap")
                    legendDot(.orange, "Modifier")
                }
            }

            HStack(spacing: 8) {
                chipView(.leftTrigger)
                chipView(.leftShoulder)
                Spacer()
                chipView(.rightShoulder)
                chipView(.rightTrigger)
            }

            HStack(alignment: .top, spacing: 18) {
                dpadCluster
                Spacer()

                if Self.faceButtons.contains(where: { btn in bindings.contains { $0.button == btn } }) {
                    faceCluster
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var dpadCluster: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                chipSpacer
                chipView(.dpadUp)
                chipSpacer
            }
            HStack(spacing: 4) {
                chipView(.dpadLeft)
                chipSpacer
                chipView(.dpadRight)
            }
            HStack(spacing: 4) {
                chipSpacer
                chipView(.dpadDown)
                chipSpacer
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var faceCluster: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                chipSpacer
                chipView(.buttonNorth)
                chipSpacer
            }
            HStack(spacing: 4) {
                chipView(.buttonWest)
                chipSpacer
                chipView(.buttonEast)
            }
            HStack(spacing: 4) {
                chipSpacer
                chipView(.buttonSouth)
                chipSpacer
            }
            HStack(spacing: 8) {
                chipView(.l3)
                chipView(.r3)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var chipSpacer: some View {
        Color.clear
            .frame(width: 44, height: 34)
            .accessibilityHidden(true)
    }

    private func binding(for button: ControllerButton) -> MacroBinding? {
        bindings.first { $0.button == button }
    }

    private func modeColor(_ mode: FireMode) -> Color {
        switch mode {
        case .hold:         return .green
        case .tap:          return .blue
        case .modifierHold: return .orange
        }
    }

    private func actionBadgeText(_ b: MacroBinding) -> String {
        let keyText = b.modifier == .none ? b.keyName : "\(modifierBadgeName(b.modifier))+\(b.keyName)"
        switch b.mode {
        case .hold:         return "R·\(keyText)·\(Int(b.rate))ms"
        case .tap:          return "T·\(keyText)"
        case .modifierHold: return "M·\(b.modifier.displayName)"
        }
    }

    @ViewBuilder
    private func chipView(_ button: ControllerButton) -> some View {
        let b = binding(for: button)
        VStack(spacing: 2) {
            Text(button.mapLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let b {
                let color = modeColor(b.mode)
                Text(actionBadgeText(b))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(color)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            } else {
                Text("—")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(minWidth: 44, minHeight: 34)
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            guard let b else { return "\(button.displayName): unbound" }
            let keyText = b.modifier == .none ? b.keyName : "\(b.modifier.displayName) plus \(b.keyName)"
            switch b.mode {
            case .hold:         return "\(button.displayName): \(keyText), Rapid, \(Int(b.rate)) milliseconds"
            case .tap:          return "\(button.displayName): \(keyText), Tap"
            case .modifierHold: return "\(button.displayName): \(b.modifier.displayName) modifier"
            }
        }())
    }

    private func modifierBadgeName(_ modifier: KeyModifier) -> String {
        switch modifier {
        case .none:  return ""
        case .alt:   return "Alt"
        case .shift: return "Sft"
        case .ctrl:  return "Ctl"
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
