import SwiftUI

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
        MacroBinding(button: button, keyName: "K", keyCode: 0x28, modifier: modifier, mode: mode, rate: rate, label: label)
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
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(24)
            .frame(width: 460)
        }
    }
}
