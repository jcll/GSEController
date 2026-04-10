import SwiftUI

// MARK: - New Group Sheet

struct NewGroupSheet: View {
    let store: ProfileStore
    @Binding var isPresented: Bool

    private struct ProfileTemplate: Identifiable {
        let id: String
        let name: String
        let icon: String
        let iconColor: Color
        let description: String
        let group: ProfileGroup

        func makeGroup() -> ProfileGroup {
            group.withFreshIDs()
        }
    }

    private static func binding(_ button: ControllerButton, mode: FireMode, modifier: KeyModifier = .none, rate: Double = 250, label: String = "") -> MacroBinding {
        MacroBinding(button: button, keyName: "K", keyCode: 0x28, modifier: modifier, mode: mode, rate: rate, label: label)
    }

    private static let templates: [ProfileTemplate] = {
        [
            ProfileTemplate(
                id: "guardian-druid",
                name: "Guardian Druid",
                icon: "pawprint.fill",
                iconColor: .brown,
                description: "2 rotations + 3 d-pad defensive/utility modifiers",
                group: ProfileGroup(name: "Guardian Druid", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, label: "Bear Form Rotation (ST)"),
                    Self.binding(.rightTrigger,  mode: .hold, label: "Bear Form Rotation (MT)"),
                    Self.binding(.dpadDown,  mode: .modifierHold, modifier: .alt,   label: "Frenzied Regen"),
                    Self.binding(.dpadLeft,  mode: .modifierHold, modifier: .shift, label: "Incapacitating Roar"),
                    Self.binding(.dpadRight, mode: .modifierHold, modifier: .ctrl,  label: "Rebirth"),
                ])
            ),
            ProfileTemplate(
                id: "generic-tank",
                name: "Generic Tank",
                icon: "shield.fill",
                iconColor: .blue,
                description: "2 rotations + 3 d-pad cooldown modifiers",
                group: ProfileGroup(name: "Generic Tank", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, label: "Single Target Rotation"),
                    Self.binding(.rightTrigger,  mode: .hold, label: "AoE Rotation"),
                    Self.binding(.dpadDown,  mode: .modifierHold, modifier: .alt,   label: "Defensive Cooldown"),
                    Self.binding(.dpadLeft,  mode: .modifierHold, modifier: .shift, label: "CC / Utility"),
                    Self.binding(.dpadRight, mode: .modifierHold, modifier: .ctrl,  label: "Taunt / Off-GCD"),
                ])
            ),
            ProfileTemplate(
                id: "melee-dps",
                name: "Melee DPS",
                icon: "figure.martial.arts",
                iconColor: .red,
                description: "2 rotations + defensive and offensive modifiers",
                group: ProfileGroup(name: "Melee DPS", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, label: "Single Target Rotation"),
                    Self.binding(.rightTrigger,  mode: .hold, label: "AoE Rotation"),
                    Self.binding(.dpadDown,  mode: .modifierHold, modifier: .alt,   label: "Defensive / Survival CD"),
                    Self.binding(.dpadLeft,  mode: .modifierHold, modifier: .shift, label: "Interrupt"),
                    Self.binding(.dpadRight, mode: .modifierHold, modifier: .ctrl,  label: "Major DPS Cooldown"),
                ])
            ),
            ProfileTemplate(
                id: "ranged-caster",
                name: "Ranged / Caster",
                icon: "wand.and.stars",
                iconColor: .purple,
                description: "2 rotations + defensive and burst modifiers",
                group: ProfileGroup(name: "Ranged / Caster", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, label: "Main Rotation"),
                    Self.binding(.rightTrigger,  mode: .hold, rate: 100, label: "Burst / Proc Rotation"),
                    Self.binding(.dpadDown,  mode: .modifierHold, modifier: .alt,   label: "Defensive Cooldown"),
                    Self.binding(.dpadLeft,  mode: .modifierHold, modifier: .shift, label: "Interrupt / Kick"),
                    Self.binding(.dpadRight, mode: .modifierHold, modifier: .ctrl,  label: "Major DPS Cooldown"),
                ])
            ),
            ProfileTemplate(
                id: "healer",
                name: "Healer",
                icon: "cross.fill",
                iconColor: .green,
                description: "1 heal rotation + 3 cooldown modifiers",
                group: ProfileGroup(name: "Healer", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, label: "Main Heal Rotation"),
                    Self.binding(.dpadDown,  mode: .modifierHold, modifier: .alt,   label: "Major Cooldown"),
                    Self.binding(.dpadLeft,  mode: .modifierHold, modifier: .shift, label: "Dispel / Utility"),
                    Self.binding(.dpadRight, mode: .modifierHold, modifier: .ctrl,  label: "Raid Cooldown"),
                ])
            ),
            ProfileTemplate(
                id: "simple-r1",
                name: "Simple — R1 Only",
                icon: "hand.point.right.fill",
                iconColor: .secondary,
                description: "Just one button for rapid-fire macro spam",
                group: ProfileGroup(name: "Simple", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, label: "Rotation"),
                ])
            ),
            ProfileTemplate(
                id: "blank",
                name: "Blank",
                icon: "square.dashed",
                iconColor: .secondary,
                description: "Start with one empty binding",
                group: ProfileGroup(name: "New Profile", bindings: [
                    Self.binding(.rightShoulder, mode: .hold, label: ""),
                ])
            ),
        ]
    }()

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
                    ForEach(Self.templates) { template in
                        Button(action: {
                            store.addGroup(template.makeGroup(), activateAfterAdd: true)
                            isPresented = false
                        }) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: template.icon)
                                    .font(.title2)
                                    .foregroundStyle(template.iconColor)
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
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
                            .enhancedGlass(cornerRadius: 10, style: .nested)
                        }
                        .buttonStyle(TemplateCardButtonStyle(accent: template.iconColor))
                        .accessibilityIdentifier("template-\(template.id)")
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

    private struct TemplateCardButtonStyle: ButtonStyle {
        let accent: Color

        func makeBody(configuration: Configuration) -> some View {
            TemplateCardButton(configuration: configuration, accent: accent)
        }
    }

    private struct TemplateCardButton: View {
        let configuration: ButtonStyleConfiguration
        let accent: Color

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovering = false

        private var isHighlighted: Bool { isHovering || configuration.isPressed }

        var body: some View {
            configuration.label
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accent.opacity(configuration.isPressed ? 0.08 : (isHovering ? 0.04 : 0)))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(accent.opacity(configuration.isPressed ? 0.36 : (isHovering ? 0.24 : 0)), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
                .brightness(isHighlighted ? 0.03 : 0)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: configuration.isPressed)
                .onHover { isHovering = $0 }
        }
    }
}
