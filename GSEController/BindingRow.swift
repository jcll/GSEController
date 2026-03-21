import SwiftUI

// MARK: - Binding Row

struct BindingRow: View {
    @Binding var binding: MacroBinding
    let usedButtons: Set<ControllerButton>
    let canDelete: Bool
    let onDelete: () -> Void

    private var modeColor: Color {
        switch binding.mode {
        case .hold:         return .green
        case .tap:          return .blue
        case .modifierHold: return .orange
        }
    }

    private var headlineAction: String {
        switch binding.mode {
        case .hold:         return "\(binding.keyName) · Rapid · \(Int(binding.rate))×/s"
        case .tap:          return "\(binding.keyName) · Tap"
        case .modifierHold: return "Modifier: \(binding.modifier.displayName)"
        }
    }

    private var modeDescription: String {
        switch binding.mode {
        case .hold:         return "Fires rapidly while held — use this for your GSE rotation macro"
        case .tap:          return "Fires once per press — use this for cooldowns you trigger manually"
        case .modifierHold: return "Holds Alt/Shift/Ctrl while pressed — activates the modifier block in your rotation macro"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: button picker + mode picker + delete
            HStack(spacing: 8) {
                Picker("Button", selection: $binding.button) {
                    ForEach(ControllerButton.allCases) { btn in
                        Text(btn.displayName).tag(btn)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .onChange(of: binding.button) { _, newButton in
                    if newButton.isDpad && binding.mode != .modifierHold {
                        binding.mode = .modifierHold
                        if binding.modifier == .none { binding.modifier = .alt }
                    }
                }

                Picker("Mode", selection: $binding.mode) {
                    Text("Rapid").tag(FireMode.hold)
                    Text("Tap").tag(FireMode.tap)
                    Text("Modifier").tag(FireMode.modifierHold)
                }
                .labelsHidden()
                .frame(width: 105)
                .onChange(of: binding.mode) { _, newMode in
                    if newMode == .modifierHold && binding.modifier == .none {
                        binding.modifier = .alt
                    }
                }

                Spacer()

                if canDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Remove binding")
                }
            }

            if usedButtons.contains(binding.button) {
                Label("Already used by another binding", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            // Headline summary
            HStack(spacing: 6) {
                Text(binding.button.mapLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(modeColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(modeColor)
                Image(systemName: "arrow.right")
                    .font(.caption2).foregroundStyle(.secondary)
                Text(headlineAction)
                    .font(.callout.weight(.medium))
                if !binding.label.isEmpty {
                    Text("· \(binding.label)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Mode description
            Text(modeDescription)
                .font(.caption)
                .italic()
                .foregroundStyle(.secondary)

            if binding.mode == .modifierHold {
                HStack(spacing: 8) {
                    Text("Modifier")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Modifier key", selection: $binding.modifier) {
                        Text("Alt").tag(KeyModifier.alt)
                        Text("Shift").tag(KeyModifier.shift)
                        Text("Ctrl").tag(KeyModifier.ctrl)
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
            } else {
                // Key + modifier row
                HStack(spacing: 8) {
                    Text("Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Key", selection: keyPickerBinding) {
                        ForEach(MacroKey.allKeys) { key in
                            Text(key.name).tag(key.name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 70)

                    Text("Mod")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Modifier", selection: $binding.modifier) {
                        ForEach(KeyModifier.allCases) { mod in
                            Text(mod.displayName).tag(mod)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 80)
                }

                if binding.mode == .hold {
                    rateRow
                }
            }

            // Optional label
            TextField("Label (optional)", text: $binding.label)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
        .padding(10)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var rateRow: some View {
        let isCustom = !ProfileGroup.ratePresets.contains { abs($0.value - binding.rate) < 0.1 }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("Rate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
                ratePresetButton("Slow",      value: 6)
                ratePresetButton("Standard",  value: 10)
                ratePresetButton("Fast",      value: 15)
                ratePresetButton("Very Fast", value: 20)
                Spacer()
                Text("\(Int(binding.rate))×/sec")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if isCustom {
                HStack {
                    Slider(value: $binding.rate, in: 1...30, step: 1)
                    Text("\(Int(binding.rate))/s")
                        .monospacedDigit()
                        .font(.caption)
                        .frame(width: 38, alignment: .trailing)
                }
            }
        }
    }

    private func ratePresetButton(_ label: String, value: Double) -> some View {
        let isSelected = abs(binding.rate - value) < 0.1
        return Button(label) { binding.rate = value }
            .buttonStyle(.glass)
            .controlSize(.mini)
            .opacity(isSelected ? 1.0 : 0.5)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var keyPickerBinding: Binding<String> {
        Binding(
            get: { binding.keyName },
            set: { name in
                binding.keyName = name
                if let key = MacroKey.find(name) {
                    binding.keyCode = key.keyCode
                }
            }
        )
    }
}
