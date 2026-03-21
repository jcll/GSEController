import SwiftUI

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
    private var nameIsBlank: Bool { draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            LabeledContent("Name") {
                VStack(alignment: .trailing, spacing: 2) {
                    TextField("Group name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                    if nameIsBlank {
                        Text("Name required")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }

            Divider()

            ControllerMapView(bindings: draft.bindings)

            Divider()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach($draft.bindings) { $binding in
                        BindingRow(
                            binding: $binding,
                            usedButtons: Set(draft.bindings.filter { $0.id != binding.id }.map(\.button)),
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
                .disabled(!hasChanges || nameIsBlank)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: group) { _, newGroup in draft = newGroup }
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
