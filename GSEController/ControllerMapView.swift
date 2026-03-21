import SwiftUI

// MARK: - Controller Map View

struct ControllerMapView: View {
    let bindings: [MacroBinding]

    private let faceRow: [ControllerButton] = [.buttonWest, .buttonNorth, .buttonSouth, .buttonEast, .l3, .r3]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Shoulder/trigger row
            HStack(spacing: 8) {
                chipView(.leftTrigger)
                chipView(.leftShoulder)
                Spacer()
                chipView(.rightShoulder)
                chipView(.rightTrigger)
            }

            // D-pad row
            HStack(spacing: 8) {
                chipView(.dpadLeft)
                chipView(.dpadDown)
                chipView(.dpadRight)
                chipView(.dpadUp)
                Spacer()
            }

            // Face/stick row — only if any are configured
            if faceRow.contains(where: { btn in bindings.contains { $0.button == btn } }) {
                HStack(spacing: 8) {
                    ForEach(faceRow, id: \.self) { chipView($0) }
                }
            }

            // Legend — only shown when there are bindings to reference
            if !bindings.isEmpty {
                HStack(spacing: 12) {
                    legendDot(.green, "Rapid")
                    legendDot(.blue, "Tap")
                    legendDot(.orange, "Modifier")
                }
            }
        }
        .padding(.vertical, 4)
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
        switch b.mode {
        case .hold:         return "R·\(b.keyName)·\(Int(b.rate))/s"
        case .tap:          return "T·\(b.keyName)"
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
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(color)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            } else {
                Text("—")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel({
            guard let b else { return "\(button.displayName): unbound" }
            switch b.mode {
            case .hold:         return "\(button.displayName): \(b.keyName), Rapid, \(Int(b.rate)) per second"
            case .tap:          return "\(button.displayName): \(b.keyName), Tap"
            case .modifierHold: return "\(button.displayName): \(b.modifier.displayName) modifier"
            }
        }())
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
