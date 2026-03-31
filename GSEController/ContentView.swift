import SwiftUI
import Observation

struct ContentView: View {
    @State private var model = AppModel()
    @State private var showingCPInfo = false
    @State private var showingNewGroup = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var groupToDelete: ProfileGroup? = nil

    private var store: ProfileStore { model.store }
    private var controller: ControllerManager { model.controller }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List(
                    store.groups,
                    id: \.id,
                    selection: Binding(
                        get: { store.activeGroupId },
                        set: { model.selectGroup($0) }
                    )
                ) { g in
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
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(profileRowIdentifier(for: g.name))
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
                    .accessibilityIdentifier("new-profile-button")

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
                        Button("Export Profiles…") { model.exportProfiles() }
                        Button("Import Profiles…") { model.importProfiles() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Export or import profiles")
                    .accessibilityLabel("Profile actions")
                    .accessibilityIdentifier("profile-actions-button")
                }
                .padding(.horizontal, 4)
                .frame(height: 28)
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

                    if !controller.helperReady && !controller.helperSetupFailed {
                        helperPreparingCard
                    }

                    if controller.helperSetupFailed {
                        helperErrorCard
                    }

                    if !controller.fifoHealthy {
                        fifoUnhealthyCard
                    }

                    if let group = store.activeGroup {
                        GroupEditorCard(group: group, onSave: { saved in
                            model.saveGroup(saved)
                        })
                        .disabled(controller.isRunning || controller.isStarting)
                        .opacity((controller.isRunning || controller.isStarting) ? 0.6 : 1.0)
                        if controller.isRunning || controller.isStarting {
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
                    .accessibilityLabel("Toggle sidebar")
                }
            }
        }
        .frame(minWidth: 640, minHeight: 600)
        .onAppear { model.onAppear() }
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
                if let g = groupToDelete { model.deleteGroup(g) }
                groupToDelete = nil
            }
            Button("Cancel", role: .cancel) { groupToDelete = nil }
        } message: {
            Text("This profile and all its bindings will be permanently deleted.")
        }
        .alert(item: $model.activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
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
        .enhancedGlass(cornerRadius: 12, tint: controller.isConnected ? .green : nil)
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
                granted: controller.hasHelperAccessibility,
                label: "Step 1 — Key Helper binary",
                detail: "Sends keystrokes to WoW. Open Accessibility settings, then drag the helper in.",
                actions: {
                    Button("Open Settings") {
                        controller.openHelperAccessibilitySettings()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .accessibilityLabel("Open Settings for Key Helper")
                }
            )

            permissionRow(
                granted: controller.hasAccessibility,
                label: "Step 2 — GSEController",
                detail: controller.hasHelperAccessibility
                    ? "Allows the app to receive controller input in the background."
                    : "Complete Step 1 first, then grant access here.",
                actions: {
                    Button("Grant Access") {
                        controller.checkAccessibility()
                        controller.requestAccessibilityPermission()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .disabled(!controller.hasHelperAccessibility)
                    .accessibilityLabel("Grant GSEController Accessibility access")
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

    private var helperPreparingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Preparing key helper")
                    .font(.callout.weight(.semibold))
                Text("Compiling and reconnecting the helper before Start becomes available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
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
                Text("Run xcode-select --install in Terminal, then retry helper setup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry") {
                controller.retryHelperSetup()
            }
            .buttonStyle(.glass)
            .controlSize(.small)
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
            Toggle(
                "Only fire when WoW is focused",
                isOn: Binding(
                    get: { controller.requireWoWFocus },
                    set: { controller.requireWoWFocus = $0 }
                )
            )
                .font(.callout)
            Spacer()
            Button(action: { showingCPInfo = true }) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("ConsolePort compatibility")
            .accessibilityLabel("ConsolePort compatibility")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .enhancedGlass(cornerRadius: 12)
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
                // Outer ripple ring — larger scale, longer period, phase-offset by 0.4 s
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                    .scaleEffect(controller.isFiring ? 2.4 : 1.0)
                    .opacity(controller.isFiring ? 0.0 : 0.15)
                    .animation(
                        controller.isFiring
                            ? .easeOut(duration: 1.2).repeatForever(autoreverses: false).delay(0.4)
                            : .easeOut(duration: 0.3),
                        value: controller.isFiring
                    )
                // Inner ripple ring — tighter scale, shorter period
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
                .accessibilityIdentifier("status-message")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        .enhancedGlass(cornerRadius: 10, tint: controller.isFiring ? .red : (controller.isRunning ? .green : nil))
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
            model.startOrStopSelectedGroup()
        }) {
            Label(
                controller.isStarting ? "Starting…" : (controller.isRunning ? "Stop" : "Start"),
                systemImage: controller.isStarting ? "hourglass" : (controller.isRunning ? "stop.fill" : "play.fill")
            )
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.glassProminent)
        .tint(controller.isRunning ? .red : .green)
        .accessibilityLabel(
            controller.isStarting ? "Starting" : (controller.isRunning ? "Stop" : "Start")
        )
        .accessibilityIdentifier("start-stop-button")
        .disabled(
            controller.isStarting ||
            !controller.isConnected ||
            store.activeGroup?.bindings.isEmpty == true ||
            store.activeGroup?.hasDuplicateButtons == true ||
            !controller.helperReady
        )
        .help({
            if controller.isStarting { return "Preparing the helper and session" }
            if !controller.isConnected { return "Connect a controller to start" }
            if store.activeGroup?.bindings.isEmpty == true { return "Add at least one binding to start" }
            if store.activeGroup?.hasDuplicateButtons == true { return "Each controller button can only be assigned once" }
            if !controller.helperReady {
                return controller.helperSetupFailed
                    ? "Key helper failed to compile — see banner above"
                    : "Preparing key helper…"
            }
            return ""
        }())

        if controller.isStarting {
            Text("Preparing the helper and activating your current profile")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !controller.isRunning {
            Group {
                if !controller.isConnected {
                    Text("Connect a controller to start")
                } else if store.activeGroup?.bindings.isEmpty == true {
                    Text("Add at least one binding to start")
                } else if store.activeGroup?.hasDuplicateButtons == true {
                    Text("Each controller button can only be assigned once")
                } else if !controller.helperReady {
                    Text(controller.helperSetupFailed ? "Key helper failed — see banner above" : "Preparing key helper…")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func profileRowIdentifier(for name: String) -> String {
        let pieces = name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        let slug = pieces.isEmpty ? "profile" : pieces.joined(separator: "-")
        return "profile-row-\(slug)"
    }

}
