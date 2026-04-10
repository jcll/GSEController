import SwiftUI
import AppKit

// MARK: - Binding Row

struct BindingRow: View {
    @Binding var binding: MacroBinding
    let usedButtons: Set<ControllerButton>
    let hasDuplicateAssignment: Bool
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
        let keyText = binding.modifier == .none ? binding.keyName : "\(binding.modifier.displayName)+\(binding.keyName)"
        switch binding.mode {
        case .hold:         return "\(keyText) · Rapid · \(Int(binding.rate))ms"
        case .tap:          return "\(keyText) · Tap"
        case .modifierHold: return "Hold \(binding.modifier.displayName)"
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
                Picker("Button", selection: buttonPickerBinding) {
                    ForEach(ControllerButton.allCases) { btn in
                        let isUsed = usedButtons.contains(btn) && btn != binding.button
                        Text(isUsed ? "\(btn.displayName) (used)" : btn.displayName)
                            .foregroundStyle(isUsed ? .secondary : .primary)
                            .tag(btn)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .onChange(of: binding.button) { _, newButton in
                    normalizeForButton(newButton)
                }

                Picker("Mode", selection: modePickerBinding) {
                    Text("Rapid").tag(FireMode.hold)
                    Text("Tap").tag(FireMode.tap)
                    Text("Modifier").tag(FireMode.modifierHold)
                }
                .labelsHidden()
                .frame(width: 105)
                .onChange(of: binding.mode) { _, _ in normalizeForCurrentMode() }

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

            if hasDuplicateAssignment {
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
                    .accessibilityIdentifier("binding-headline")
                    .accessibilityLabel(headlineAction)
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
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var rateRow: some View {
        let isCustom = !ProfileGroup.ratePresets.contains { abs($0.value - binding.rate) < 0.1 }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("Rate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
                ForEach(ProfileGroup.ratePresets, id: \.value) { preset in
                    ratePresetButton(preset.label, value: preset.value)
                }
                Spacer()
                RateInputField(rate: $binding.rate)
                Text("ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isCustom {
                HStack {
                    Text("Fast").font(.caption2).foregroundStyle(.tertiary)
                    Slider(value: rateSliderBinding, in: 50...500, step: 10)
                    Text("Slow").font(.caption2).foregroundStyle(.tertiary)
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

    private var buttonPickerBinding: Binding<ControllerButton> {
        Binding(
            get: { binding.button },
            set: { newButton in
                guard newButton == binding.button || !usedButtons.contains(newButton) else { return }
                binding.button = newButton
                normalizeForButton(newButton)
            }
        )
    }

    private var modePickerBinding: Binding<FireMode> {
        Binding(
            get: { binding.mode },
            set: { newMode in
                binding.mode = binding.button.isDpad ? .modifierHold : newMode
                normalizeForCurrentMode()
            }
        )
    }

    private var rateSliderBinding: Binding<Double> {
        Binding(
            get: { min(max(binding.rate, 50), 500) },
            set: { binding.rate = $0 }
        )
    }

    private func normalizeForButton(_ button: ControllerButton) {
        if button.isDpad && binding.mode != .modifierHold {
            binding.mode = .modifierHold
        }
        normalizeForCurrentMode()
    }

    private func normalizeForCurrentMode() {
        if binding.button.isDpad && binding.mode != .modifierHold {
            binding.mode = .modifierHold
        }
        if binding.mode == .modifierHold && binding.modifier == .none {
            binding.modifier = .alt
        }
    }
}

private struct RateInputField: View {
    @Binding var rate: Double

    var body: some View {
        RateTextField(rate: $rate)
            .frame(width: 54)
            .accessibilityIdentifier("binding-rate-field")
    }
}

private struct RateTextField: NSViewRepresentable {
    @Binding var rate: Double

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.alignment = .right
        field.controlSize = .small
        field.bezelStyle = .roundedBezel
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.setAccessibilityIdentifier("binding-rate-field")
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.isEditing else { return }
        field.stringValue = "\(Int(rate))"
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RateTextField
        var isEditing = false

        init(parent: RateTextField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            isEditing = true
            guard let field = notification.object as? NSTextField else { return }
            DispatchQueue.main.async {
                field.currentEditor()?.selectAll(nil)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            updateRate(from: field.stringValue)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            isEditing = false
            guard let field = notification.object as? NSTextField else { return }
            commit(field)
        }

        private func updateRate(from string: String) {
            guard let value = Double(string), (33...1000).contains(value) else { return }
            parent.rate = value.rounded()
        }

        private func commit(_ field: NSTextField) {
            guard let value = Double(field.stringValue) else {
                field.stringValue = "\(Int(parent.rate))"
                return
            }
            parent.rate = min(max(value.rounded(), 33), 1000)
            field.stringValue = "\(Int(parent.rate))"
        }
    }
}
