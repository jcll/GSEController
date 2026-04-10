import SwiftUI

// MARK: - Group Editor Card

// Stateful wrapper around a ProfileGroup draft. The store owns persisted data,
// but the editor keeps local changes isolated until Save so selection changes
// and unsaved-change prompts have a clear source of truth.
struct GroupEditorCard: View {
    let group: ProfileGroup
    let onSave: (ProfileGroup) -> Void
    let onDraftChange: (ProfileGroup, Bool) -> Void

    @State private var draft: ProfileGroup

    init(
        group: ProfileGroup,
        onSave: @escaping (ProfileGroup) -> Void,
        onDraftChange: @escaping (ProfileGroup, Bool) -> Void
    ) {
        self.group = group
        self.onSave = onSave
        self.onDraftChange = onDraftChange
        self._draft = State(initialValue: group)
    }

    private var hasChanges: Bool { draft != group }
    private var nameIsBlank: Bool { draft.name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var duplicateButtons: Set<ControllerButton> { draft.bindings.duplicateButtons }
    private var hasDuplicateButtons: Bool { !duplicateButtons.isEmpty }
    private var usedButtonsByBindingID: [UUID: Set<ControllerButton>] {
        let buttonsByID = Dictionary(uniqueKeysWithValues: draft.bindings.map { ($0.id, $0.button) })
        return Dictionary(uniqueKeysWithValues: draft.bindings.map { binding in
            let used = Set(buttonsByID.compactMap { id, button in
                id == binding.id ? nil : button
            })
            return (binding.id, used)
        })
    }

    var body: some View {
        VStack(spacing: 12) {
            LabeledContent("Name") {
                VStack(alignment: .trailing, spacing: 2) {
                    TextField("Group name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("group-name-field")
                    if nameIsBlank {
                        Text("Name required")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }

            LabeledContent("Notes") {
                TextField("Macro keybind, spec, talents, or setup notes", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .accessibilityIdentifier("group-notes-field")
            }

            Divider()

            ControllerMapView(bindings: draft.bindings)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($draft.bindings) { $binding in
                        BindingRow(
                            binding: $binding,
                            usedButtons: usedButtonsByBindingID[binding.id] ?? [],
                            hasDuplicateAssignment: duplicateButtons.contains(binding.button),
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

                VStack(alignment: .trailing, spacing: 2) {
                    if hasChanges {
                        Text("Unsaved changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if hasDuplicateButtons {
                        Text("Each controller button can only be assigned once")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Button(action: { onSave(draft) }) {
                    Text("Save")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glassProminent)
                .tint(hasChanges ? .blue : nil)
                .controlSize(.small)
                .disabled(!hasChanges || nameIsBlank || hasDuplicateButtons)
                .accessibilityIdentifier("save-group-button")
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .enhancedGlass(cornerRadius: 12, style: .primary)
        .onAppear {
            reportDraft(draft, comparedTo: group)
        }
        .onChange(of: draft) { _, newDraft in
            reportDraft(newDraft, comparedTo: group)
        }
        .onChange(of: group) { _, newGroup in
            draft = newGroup
            reportDraft(newGroup, comparedTo: newGroup)
        }
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
            rate: 250
        ))
    }

    private func reportDraft(_ draft: ProfileGroup, comparedTo source: ProfileGroup) {
        onDraftChange(draft, draft != source)
    }
}
