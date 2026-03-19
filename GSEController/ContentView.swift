import SwiftUI

struct ContentView: View {
    @StateObject private var store = ProfileStore()
    @StateObject private var controller = ControllerManager()
    @State private var showingCPInfo = false
    @State private var showingNewGroup = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List(store.groups, id: \.id, selection: $store.activeGroupId) { g in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.name)
                            .lineLimit(1)
                        Text("\(g.bindings.count) binding\(g.bindings.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        if store.groups.count > 1 {
                            Button(role: .destructive) {
                                store.deleteGroup(g)
                            } label: {
                                Label("Delete \"\(g.name)\"", systemImage: "trash")
                            }
                        }
                    }
                }

                Divider()

                HStack(spacing: 0) {
                    Button {
                        showingNewGroup = true
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("New profile")

                    if store.groups.count > 1,
                       let id = store.activeGroupId,
                       let group = store.groups.first(where: { $0.id == id }) {
                        Divider().frame(height: 16)
                        Button {
                            store.deleteGroup(group)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Delete profile")
                    }

                    Spacer()
                }
                .padding(.horizontal, 4)
                .frame(height: 28)
            }
            .navigationTitle("Profiles")
        } detail: {
            GlassEffectContainer {
                VStack(spacing: 20) {
                    controllerCard

                    if !controller.hasAccessibility || !controller.hasHelperAccessibility {
                        permissionSetupCard
                    }

                    if let group = store.activeGroup {
                        GroupEditorCard(group: group, onSave: { saved in
                            if let idx = store.groups.firstIndex(where: { $0.id == saved.id }) {
                                store.groups[idx] = saved
                            }
                        })
                        .disabled(controller.isRunning)
                        .opacity(controller.isRunning ? 0.6 : 1.0)
                    }

                    optionsRow
                    statusRow
                    startStopButton
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, minHeight: 500)
        .onAppear { Task { @MainActor in controller.checkAccessibility() } }
        .sheet(isPresented: $showingCPInfo) { consolePortSheet }
        .sheet(isPresented: $showingNewGroup) {
            NewGroupSheet(store: store, isPresented: $showingNewGroup)
        }
    }

    // MARK: - Controller Card

    private var controllerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: controller.isConnected ? "gamecontroller.fill" : "gamecontroller")
                .font(.title)
                .foregroundStyle(controller.isConnected ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.controllerName ?? "No Controller")
                    .font(.headline)
                Text(controller.isConnected ? "Connected" : "Searching\u{2026}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let level = controller.batteryLevel {
                batteryIndicator(level: level, charging: controller.batteryCharging)
            }

            Circle()
                .fill(controller.isConnected ? .green : .red)
                .frame(width: 10, height: 10)
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    private func batteryIndicator(level: Float, charging: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIconName(level: level, charging: charging))
                .foregroundStyle(batteryColor(level: level, charging: charging))
            Text("\(Int(level * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func batteryIconName(level: Float, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case 0.75...: return "battery.100percent"
        case 0.50...: return "battery.75percent"
        case 0.25...: return "battery.50percent"
        case 0.10...: return "battery.25percent"
        default:      return "battery.0percent"
        }
    }

    private func batteryColor(level: Float, charging: Bool) -> Color {
        if charging { return .green }
        if level <= 0.15 { return .red }
        if level <= 0.30 { return .orange }
        return .secondary
    }

    // MARK: - Unified Permission Setup Card

    private var permissionSetupCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Accessibility Setup Required")
                    .font(.callout.weight(.semibold))
                Spacer()
            }

            Divider()

            permissionRow(
                granted: controller.hasAccessibility,
                label: "GSEController",
                detail: "Allows the app to receive controller input in the background.",
                actions: {
                    Button("Grant Access") {
                        KeySimulator.requestAccessibility()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            )

            permissionRow(
                granted: controller.hasHelperAccessibility,
                label: "Key Helper binary",
                detail: "Sends keystrokes to WoW. Open Accessibility settings, then drag the helper in.",
                actions: {
                    Button("Open Settings") {
                        KeySimulator.openAccessibilitySettings()
                        KeySimulator.revealHelperInFinder()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                }
            )

            Divider()

            HStack {
                Text("Rechecks automatically when you return to this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Check Now") {
                    controller.checkAccessibility()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.3), lineWidth: 0.5))
    }

    private func permissionRow<Actions: View>(
        granted: Bool,
        label: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.body)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout)
                if !granted {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !granted {
                actions()
            }
        }
    }

    // MARK: - Options

    private var optionsRow: some View {
        HStack {
            Toggle("Only fire when WoW is focused", isOn: $controller.requireWoWFocus)
                .font(.callout)
            Spacer()
            Button(action: { showingCPInfo = true }) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("ConsolePort compatibility")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - ConsolePort Info Sheet

    private var consolePortSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("ConsolePort Compatibility", systemImage: "gamecontroller.fill")
                .font(.title3.weight(.semibold))

            Text("ConsolePort uses WoW\u{2019}s built-in gamepad API. When you press a controller button, both ConsolePort and this app will see it independently.")

            VStack(alignment: .leading, spacing: 8) {
                Label("Unbind the trigger button in ConsolePort so it doesn\u{2019}t fire a WoW action alongside the rapid-fire key.", systemImage: "1.circle.fill")
                Label("Or use L3/R3 as your trigger \u{2014} ConsolePort rarely binds these by default.", systemImage: "2.circle.fill")
                Label("Bind your GSE macro to the keyboard key set in your binding (e.g. K).", systemImage: "3.circle.fill")
                Label("D-pad directions used for modifier hold will also fire as native WoW gamepad inputs. Unbind those d-pad directions in ConsolePort, or accept the double-fire.", systemImage: "4.circle.fill")
            }
            .font(.callout)

            Text("The \u{201C}Only fire when WoW is focused\u{201D} toggle prevents accidental key spam in other apps.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") { showingCPInfo = false }
                    .buttonStyle(.glass)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .scaleEffect(controller.isFiring ? 1.4 : 1.0)
                .animation(
                    controller.isFiring
                        ? .easeInOut(duration: 0.3).repeatForever(autoreverses: true)
                        : .default,
                    value: controller.isFiring
                )
            Text(controller.statusMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var statusColor: Color {
        if controller.isFiring { return .red }
        if controller.isRunning { return .green }
        return .secondary
    }

    // MARK: - Start / Stop

    private var startStopButton: some View {
        Button(action: {
            if controller.isRunning {
                controller.stop()
            } else if let group = store.activeGroup {
                controller.start(group: group)
            }
        }) {
            Label(
                controller.isRunning ? "Stop" : "Start",
                systemImage: controller.isRunning ? "stop.fill" : "play.fill"
            )
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.glassProminent)
        .tint(controller.isRunning ? .red : .green)
        .disabled(!controller.isConnected)
    }

}

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
                Spacer()
                VStack(spacing: 2) {
                    Text("D↑").font(.caption2).foregroundStyle(.quaternary)
                    Text("WoW").font(.system(size: 9)).foregroundStyle(.quaternary)
                }
            }

            // Face/stick row — only if any are configured
            if faceRow.contains(where: { btn in bindings.contains { $0.button == btn } }) {
                HStack(spacing: 8) {
                    ForEach(faceRow, id: \.self) { chipView($0) }
                }
            }

            // Legend
            HStack(spacing: 12) {
                legendDot(.green, "Rapid")
                legendDot(.blue, "Tap")
                legendDot(.orange, "Modifier")
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
        case .hold:         return "\(b.keyName)·\(Int(b.rate))/s"
        case .tap:          return "→\(b.keyName)"
        case .modifierHold: return b.modifier.displayName
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
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Group Editor Card

struct GroupEditorCard: View {
    let group: ProfileGroup
    let onSave: (ProfileGroup) -> Void

    @State private var draft: ProfileGroup

    init(group: ProfileGroup, onSave: @escaping (ProfileGroup) -> Void) {
        self.group = group
        self.onSave = onSave
        self._draft = State(initialValue: group)
    }

    private var hasChanges: Bool { draft != group }

    var body: some View {
        VStack(spacing: 12) {
            LabeledContent("Name") {
                TextField("Group name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            ControllerMapView(bindings: draft.bindings)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($draft.bindings) { $binding in
                        BindingRow(
                            binding: $binding,
                            canDelete: draft.bindings.count > 1,
                            onDelete: { draft.bindings.removeAll { $0.id == binding.id } }
                        )
                    }
                }
            }
            .frame(maxHeight: 500)

            HStack {
                Button(action: addBinding) {
                    Label("Add Binding", systemImage: "plus")
                }
                .buttonStyle(.glass)
                .controlSize(.small)

                Spacer()

                if hasChanges {
                    Text("Unsaved changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(action: { onSave(draft) }) {
                    Text("Save")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glassProminent)
                .tint(hasChanges ? .blue : nil)
                .controlSize(.small)
                .disabled(!hasChanges)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: group.id) { _, _ in draft = group }
    }

    private func addBinding() {
        let usedButtons = Set(draft.bindings.map(\.button))
        let nextButton = ControllerButton.allCases.first { !usedButtons.contains($0) } ?? .rightShoulder
        let mode: FireMode = nextButton.isDpad ? .modifierHold : .hold
        let modifier: KeyModifier = nextButton.isDpad ? .alt : .none
        draft.bindings.append(MacroBinding(
            button: nextButton,
            keyName: "K",
            keyCode: 0x28,
            modifier: modifier,
            mode: mode,
            rate: 10
        ))
    }
}

// MARK: - Binding Row

struct BindingRow: View {
    @Binding var binding: MacroBinding
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
                Picker("", selection: $binding.button) {
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

                Picker("", selection: $binding.mode) {
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
                    Picker("", selection: $binding.modifier) {
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
                    Picker("", selection: keyPickerBinding) {
                        ForEach(MacroKey.allKeys) { key in
                            Text(key.name).tag(key.name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 70)

                    Text("Mod")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $binding.modifier) {
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
        Button(label) { binding.rate = value }
            .buttonStyle(.glass)
            .controlSize(.mini)
            .opacity(abs(binding.rate - value) < 0.1 ? 1.0 : 0.5)
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

// MARK: - New Group Sheet

struct NewGroupSheet: View {
    let store: ProfileStore
    @Binding var isPresented: Bool

    private struct ProfileTemplate: Identifiable {
        let id: String
        let name: String
        let icon: String
        let description: String
        let group: ProfileGroup
    }

    private static func binding(_ button: ControllerButton, mode: FireMode, modifier: KeyModifier = .none, rate: Double = 10, label: String = "") -> MacroBinding {
        MacroBinding(button: button, keyName: "Q", keyCode: 0x0C, modifier: modifier, mode: mode, rate: rate, label: label)
    }

    private var templates: [ProfileTemplate] {
        [
            ProfileTemplate(
                id: "guardian-druid",
                name: "Guardian Druid",
                icon: "pawprint.fill",
                description: "2 rotations + 3 d-pad defensive/utility modifiers",
                group: ProfileGroup(name: "Guardian Druid", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, rate: 10, label: "Bear Form Rotation (ST)"),
                    Self.binding(.rightTrigger,  mode: .hold, rate: 10, label: "Bear Form Rotation (MT)"),
                    Self.binding(.dpadDown,  mode: .modifierHold, modifier: .alt,   label: "Frenzied Regen"),
                    Self.binding(.dpadLeft,  mode: .modifierHold, modifier: .shift, label: "Incapacitating Roar"),
                    Self.binding(.dpadRight, mode: .modifierHold, modifier: .ctrl,  label: "Rebirth"),
                ])
            ),
            ProfileTemplate(
                id: "generic-tank",
                name: "Generic Tank",
                icon: "shield.fill",
                description: "2 rotations + 3 d-pad cooldown modifiers",
                group: ProfileGroup(name: "Generic Tank", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, rate: 10, label: "Single Target Rotation"),
                    Self.binding(.rightTrigger,  mode: .hold, rate: 10, label: "AoE Rotation"),
                    Self.binding(.dpadDown,  mode: .modifierHold, modifier: .alt,   label: "Defensive Cooldown"),
                    Self.binding(.dpadLeft,  mode: .modifierHold, modifier: .shift, label: "CC / Utility"),
                    Self.binding(.dpadRight, mode: .modifierHold, modifier: .ctrl,  label: "Taunt / Off-GCD"),
                ])
            ),
            ProfileTemplate(
                id: "melee-dps",
                name: "Melee DPS",
                icon: "figure.martial.arts",
                description: "2 rotations + defensive and offensive modifiers",
                group: ProfileGroup(name: "Melee DPS", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, rate: 10, label: "Single Target Rotation"),
                    Self.binding(.rightTrigger,  mode: .hold, rate: 10, label: "AoE Rotation"),
                    Self.binding(.dpadDown,  mode: .modifierHold, modifier: .alt,   label: "Defensive / Survival CD"),
                    Self.binding(.dpadLeft,  mode: .modifierHold, modifier: .shift, label: "Interrupt"),
                    Self.binding(.dpadRight, mode: .modifierHold, modifier: .ctrl,  label: "Major DPS Cooldown"),
                ])
            ),
            ProfileTemplate(
                id: "ranged-caster",
                name: "Ranged / Caster",
                icon: "wand.and.stars",
                description: "2 rotations + defensive and burst modifiers",
                group: ProfileGroup(name: "Ranged / Caster", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, rate: 10, label: "Main Rotation"),
                    Self.binding(.rightTrigger,  mode: .hold, rate: 12, label: "Burst / Proc Rotation"),
                    Self.binding(.dpadDown,  mode: .modifierHold, modifier: .alt,   label: "Defensive Cooldown"),
                    Self.binding(.dpadLeft,  mode: .modifierHold, modifier: .shift, label: "Interrupt / Kick"),
                    Self.binding(.dpadRight, mode: .modifierHold, modifier: .ctrl,  label: "Major DPS Cooldown"),
                ])
            ),
            ProfileTemplate(
                id: "healer",
                name: "Healer",
                icon: "cross.fill",
                description: "1 heal rotation + 3 cooldown modifiers",
                group: ProfileGroup(name: "Healer", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, rate: 10, label: "Main Heal Rotation"),
                    Self.binding(.dpadDown,  mode: .modifierHold, modifier: .alt,   label: "Major Cooldown"),
                    Self.binding(.dpadLeft,  mode: .modifierHold, modifier: .shift, label: "Dispel / Utility"),
                    Self.binding(.dpadRight, mode: .modifierHold, modifier: .ctrl,  label: "Raid Cooldown"),
                ])
            ),
            ProfileTemplate(
                id: "simple-r1",
                name: "Simple — R1 Only",
                icon: "hand.point.right.fill",
                description: "Just one button for rapid-fire macro spam",
                group: ProfileGroup(name: "Simple", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, rate: 10, label: "Rotation"),
                ])
            ),
            ProfileTemplate(
                id: "blank",
                name: "Blank",
                icon: "square.dashed",
                description: "Start with one empty binding",
                group: ProfileGroup(name: "New Profile", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, rate: 10, label: ""),
                ])
            ),
        ]
    }

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Profile — Choose a Starting Setup")
                    .font(.title3.weight(.semibold))

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(templates) { template in
                        Button(action: {
                            store.addGroup(template.group)
                            isPresented = false
                        }) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: template.icon)
                                    .font(.title2)
                                    .foregroundStyle(.blue)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.name)
                                        .font(.callout.weight(.semibold))
                                        .multilineTextAlignment(.leading)
                                    Text(template.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Set the key to match your macro keybind after selecting a template.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(.glass)
                }
            }
            .padding(24)
            .frame(width: 460)
        }
    }
}
