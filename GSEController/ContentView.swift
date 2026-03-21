import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var store = ProfileStore()
    @StateObject private var controller = ControllerManager()
    @State private var showingCPInfo = false
    @State private var showingNewGroup = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var groupToDelete: ProfileGroup? = nil
    @State private var importErrorMessage: String? = nil

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
                                groupToDelete = g
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
                    .accessibilityLabel("New profile")

                    if store.groups.count > 1,
                       let id = store.activeGroupId,
                       let group = store.groups.first(where: { $0.id == id }) {
                        Divider().frame(height: 16)
                        Button {
                            groupToDelete = group
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 28, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Delete profile")
                        .accessibilityLabel("Delete profile")
                    }

                    Spacer()

                    Menu {
                        Button("Export Profiles…") { exportProfiles() }
                        Button("Import Profiles…") { importProfiles() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Export or import profiles")
                }
                .padding(.horizontal, 4)
                .frame(height: 28)
                .alert("Import Failed", isPresented: Binding(
                    get: { importErrorMessage != nil },
                    set: { if !$0 { importErrorMessage = nil } }
                )) {
                    Button("OK", role: .cancel) { importErrorMessage = nil }
                } message: {
                    Text(importErrorMessage ?? "")
                }
            }
            .navigationTitle("")
            .toolbar(removing: .sidebarToggle)
        } detail: {
            GlassEffectContainer {
                VStack(spacing: 20) {
                    controllerCard

                    if !controller.hasAccessibility || !controller.hasHelperAccessibility {
                        permissionSetupCard
                    }

                    if !controller.helperReady {
                        helperErrorCard
                    }

                    if !controller.fifoHealthy {
                        fifoUnhealthyCard
                    }

                    if let group = store.activeGroup {
                        GroupEditorCard(group: group, onSave: { saved in
                            if let idx = store.groups.firstIndex(where: { $0.id == saved.id }) {
                                store.groups[idx] = saved
                            }
                        })
                        .disabled(controller.isRunning)
                        .opacity(controller.isRunning ? 0.6 : 1.0)
                        if controller.isRunning {
                            Text("Stop the controller to edit bindings")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.square.dashed")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Create a profile to get started")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Button("New Profile") { showingNewGroup = true }
                                .buttonStyle(.glass)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                    }

                    optionsRow
                    statusRow
                    startStopButton
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        withAnimation {
                            columnVisibility = columnVisibility == .all ? .detailOnly : .all
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .help("Toggle Sidebar")
                }
            }
        }
        .frame(minWidth: 640, minHeight: 600)
        .onChange(of: store.activeGroupId) { _, _ in
            if controller.isRunning { controller.stop() }
        }
        .onAppear { Task { @MainActor in controller.checkAccessibility() } }
        .sheet(isPresented: $showingCPInfo) { consolePortSheet }
        .sheet(isPresented: $showingNewGroup) {
            NewGroupSheet(store: store, isPresented: $showingNewGroup)
        }
        .confirmationDialog(
            "Delete \"\(groupToDelete?.name ?? "")\"?",
            isPresented: Binding(get: { groupToDelete != nil }, set: { if !$0 { groupToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let g = groupToDelete { store.deleteGroup(g) }
                groupToDelete = nil
            }
            Button("Cancel", role: .cancel) { groupToDelete = nil }
        } message: {
            Text("This profile and all its bindings will be permanently deleted.")
        }
    }

    // MARK: - Export / Import

    private func exportProfiles() {
        guard let data = try? store.exportData() else { return }
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["json"]
        panel.nameFieldStringValue = "gsecontroller-profiles.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    private func importProfiles() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json"]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                try store.importData(data)
            } catch {
                importErrorMessage = error.localizedDescription
            }
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
                .accessibilityHidden(true)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(charging
            ? "Battery \(Int(level * 100)) percent, charging"
            : "Battery \(Int(level * 100)) percent")
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
                    .accessibilityLabel("Grant GSEController Accessibility access")
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
                    .accessibilityLabel("Open Settings for Key Helper")
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

    // MARK: - Helper Error Card

    private var helperErrorCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.circle.fill")
                .foregroundStyle(.red)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Key helper failed to compile")
                    .font(.callout.weight(.semibold))
                Text("Run xcode-select --install in Terminal, then press Start to retry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.red.opacity(0.3), lineWidth: 0.5))
    }

    private var fifoUnhealthyCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Key pipe reconnecting")
                    .font(.callout.weight(.semibold))
                Text("Key presses may be dropped until the helper reconnects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.yellow.opacity(0.3), lineWidth: 0.5))
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
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack(spacing: 8) {
            ZStack {
                // Ripple ring — expands from 1x to 1.8x and fades out while firing
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .scaleEffect(controller.isFiring ? 1.8 : 1.0)
                    .opacity(controller.isFiring ? 0.0 : 0.3)
                    .animation(
                        controller.isFiring
                            ? .easeOut(duration: 0.9).repeatForever(autoreverses: false)
                            : .easeOut(duration: 0.3),
                        value: controller.isFiring
                    )
                // Solid dot — always visible
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
            }
            .accessibilityHidden(true)
            Text(controller.statusMessage)
                .font(.callout)
                .fontWeight(controller.isFiring ? .semibold : .regular)
                .foregroundStyle(controller.isFiring ? .primary : .secondary)
                .animation(.easeInOut(duration: 0.2), value: controller.isFiring)
                .accessibilityAddTraits(.updatesFrequently)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
    }

    private var statusColor: Color {
        if controller.isFiring { return .red }
        if controller.isRunning {
            if controller.requireWoWFocus && !controller.wowIsActive { return .orange }
            return .green
        }
        return .secondary
    }

    // MARK: - Start / Stop

    @ViewBuilder private var startStopButton: some View {
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
        .disabled(!controller.isConnected || store.activeGroup?.bindings.isEmpty == true || !controller.helperReady)
        .help({
            if !controller.isConnected { return "Connect a controller to start" }
            if store.activeGroup?.bindings.isEmpty == true { return "Add at least one binding to start" }
            if !controller.helperReady { return "Key helper failed to compile — see banner above" }
            return ""
        }())

        if !controller.isRunning {
            Group {
                if !controller.isConnected {
                    Text("Connect a controller to start")
                } else if store.activeGroup?.bindings.isEmpty == true {
                    Text("Add at least one binding to start")
                } else if !controller.helperReady {
                    Text("Key helper failed — see banner above")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

}
