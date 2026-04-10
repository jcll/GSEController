import SwiftUI

@main
struct GSEControllerApp: App {
    // Entry point for the macOS app and command menu wiring. The SIGTERM hook
    // is kept here so graceful termination can release held modifiers even
    // when the quit request comes from launchd or Activity Monitor.
    init() {
        // Intercept SIGTERM so a graceful shutdown (launchd, Activity Monitor "Quit")
        // releases any held modifier keys via the FIFO before the process exits.
        // SIGKILL cannot be caught; this covers the common graceful-termination case.
        signal(SIGTERM, SIG_IGN) // prevent default termination before handler fires
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler {
            // Best-effort modifier release before exit.
            // The FIFO write may fail if the helper is already gone — that's acceptable.
            for modifier: KeyModifier in [.alt, .shift, .ctrl] {
                KeySimulator.modifierUp(modifier)
            }
            KeySimulator.stopHelper()
            exit(0)
        }
        src.resume()
        // Retain the source for the lifetime of the app.
        _ = Unmanaged.passRetained(src as AnyObject)
    }

    var body: some Scene {
        Window("GSE Controller", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            GSEControllerCommands()
        }
    }
}

private struct GSEControllerCommands: Commands {
    @FocusedValue(\.gseNewProfileAction) private var newProfileAction
    @FocusedValue(\.gseSaveProfileAction) private var saveProfileAction
    @FocusedValue(\.gseDuplicateProfileAction) private var duplicateProfileAction
    @FocusedValue(\.gseExportSelectedProfileAction) private var exportSelectedProfileAction
    @FocusedValue(\.gseExportAllProfilesAction) private var exportAllProfilesAction
    @FocusedValue(\.gseImportReplaceProfilesAction) private var importReplaceProfilesAction
    @FocusedValue(\.gseImportMergeProfilesAction) private var importMergeProfilesAction
    @FocusedValue(\.gseStartStopAction) private var startStopAction
    @FocusedValue(\.gseReleaseKeysAction) private var releaseKeysAction
    @FocusedValue(\.gseHelperDiagnosticsAction) private var helperDiagnosticsAction
    @FocusedValue(\.gseCanSaveProfile) private var canSaveProfile
    @FocusedValue(\.gseHasActiveProfile) private var hasActiveProfile
    @FocusedValue(\.gseCanStartStop) private var canStartStop

    var body: some Commands {
        CommandMenu("Profiles") {
            Button("New Profile", action: newProfileAction ?? {})
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newProfileAction == nil)

            Button("Save Profile", action: saveProfileAction ?? {})
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!(canSaveProfile ?? false))

            Button("Duplicate Profile", action: duplicateProfileAction ?? {})
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!(hasActiveProfile ?? false))

            Divider()

            Button("Export Selected Profile...", action: exportSelectedProfileAction ?? {})
                .disabled(!(hasActiveProfile ?? false))

            Button("Export All Profiles...", action: exportAllProfilesAction ?? {})
                .disabled(exportAllProfilesAction == nil)

            Divider()

            Button("Import and Replace Profiles...", action: importReplaceProfilesAction ?? {})
                .disabled(importReplaceProfilesAction == nil)

            Button("Import and Merge Profiles...", action: importMergeProfilesAction ?? {})
                .disabled(importMergeProfilesAction == nil)
        }

        CommandMenu("Controller") {
            Button("Start / Stop", action: startStopAction ?? {})
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!(canStartStop ?? false))

            Button("Release Keys", action: releaseKeysAction ?? {})
                .keyboardShortcut(".", modifiers: [.command, .option])
                .disabled(releaseKeysAction == nil)

            Divider()

            Button("Helper Diagnostics...", action: helperDiagnosticsAction ?? {})
                .disabled(helperDiagnosticsAction == nil)
        }
    }
}

private struct GSENewProfileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GSESaveProfileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GSEDuplicateProfileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GSEExportSelectedProfileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GSEExportAllProfilesActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GSEImportReplaceProfilesActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GSEImportMergeProfilesActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GSEStartStopActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GSEReleaseKeysActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GSEHelperDiagnosticsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct GSECanSaveProfileKey: FocusedValueKey {
    typealias Value = Bool
}

private struct GSEHasActiveProfileKey: FocusedValueKey {
    typealias Value = Bool
}

private struct GSECanStartStopKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var gseNewProfileAction: (() -> Void)? {
        get { self[GSENewProfileActionKey.self] }
        set { self[GSENewProfileActionKey.self] = newValue }
    }

    var gseSaveProfileAction: (() -> Void)? {
        get { self[GSESaveProfileActionKey.self] }
        set { self[GSESaveProfileActionKey.self] = newValue }
    }

    var gseDuplicateProfileAction: (() -> Void)? {
        get { self[GSEDuplicateProfileActionKey.self] }
        set { self[GSEDuplicateProfileActionKey.self] = newValue }
    }

    var gseExportSelectedProfileAction: (() -> Void)? {
        get { self[GSEExportSelectedProfileActionKey.self] }
        set { self[GSEExportSelectedProfileActionKey.self] = newValue }
    }

    var gseExportAllProfilesAction: (() -> Void)? {
        get { self[GSEExportAllProfilesActionKey.self] }
        set { self[GSEExportAllProfilesActionKey.self] = newValue }
    }

    var gseImportReplaceProfilesAction: (() -> Void)? {
        get { self[GSEImportReplaceProfilesActionKey.self] }
        set { self[GSEImportReplaceProfilesActionKey.self] = newValue }
    }

    var gseImportMergeProfilesAction: (() -> Void)? {
        get { self[GSEImportMergeProfilesActionKey.self] }
        set { self[GSEImportMergeProfilesActionKey.self] = newValue }
    }

    var gseStartStopAction: (() -> Void)? {
        get { self[GSEStartStopActionKey.self] }
        set { self[GSEStartStopActionKey.self] = newValue }
    }

    var gseReleaseKeysAction: (() -> Void)? {
        get { self[GSEReleaseKeysActionKey.self] }
        set { self[GSEReleaseKeysActionKey.self] = newValue }
    }

    var gseHelperDiagnosticsAction: (() -> Void)? {
        get { self[GSEHelperDiagnosticsActionKey.self] }
        set { self[GSEHelperDiagnosticsActionKey.self] = newValue }
    }

    var gseCanSaveProfile: Bool? {
        get { self[GSECanSaveProfileKey.self] }
        set { self[GSECanSaveProfileKey.self] = newValue }
    }

    var gseHasActiveProfile: Bool? {
        get { self[GSEHasActiveProfileKey.self] }
        set { self[GSEHasActiveProfileKey.self] = newValue }
    }

    var gseCanStartStop: Bool? {
        get { self[GSECanStartStopKey.self] }
        set { self[GSECanStartStopKey.self] = newValue }
    }
}
