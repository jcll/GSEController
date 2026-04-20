import Foundation
import Testing
@testable import GSEController

private final class ImmediateHelperInjector: KeyInjecting, @unchecked Sendable {
    var isAccessibilityEnabled = true
    var isHelperAccessibilityEnabled = true
    var diagnostics = KeyHelperDiagnostics(
        helperPath: "/tmp/keyhelper",
        launchAgentPath: "/tmp/keyhelper.plist",
        launchAgentLabel: "test.helper",
        fifoPath: "/tmp/keyfifo",
        responseFifoPath: "/tmp/keyfifo-response",
        logPath: "/tmp/helper.log",
        helperExists: true,
        launchAgentExists: true,
        fifoExists: true,
        responseFifoExists: true
    )
    var onFIFOFailure: (() -> Void)?
    var onFIFORecovered: (() -> Void)?

    func ensureHelper(onComplete: (@MainActor (Bool) -> Void)?) {
        guard let onComplete else { return }
        Task { @MainActor in onComplete(true) }
    }

    func pressKey(_ keyCode: UInt16) {}
    func modifierDown(_ modifier: KeyModifier) {}
    func modifierUp(_ modifier: KeyModifier) {}
    func requestAccessibility() {}
    func requestHelperAccessibility() {}
    func openAccessibilitySettings() {}
    func revealHelperInFinder() {}
    func stopHelper() {}
}

@Suite @MainActor struct AppModelMutationSafetyTests {
    private func makeModel() -> (AppModel, ProfileStore, ControllerManager, UserDefaults, String) {
        let suite = "com.test.gsecontroller.appmodel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = ProfileStore(defaults: defaults)
        let controller = ControllerManager(
            defaults: defaults,
            keyInjector: ImmediateHelperInjector(),
            testState: .init()
        )
        let model = AppModel(store: store, controller: controller)
        return (model, store, controller, defaults, suite)
    }

    @Test func addGroupStopsControllerBeforeActivatingNewProfile() {
        let (model, store, controller, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        controller.isRunning = true
        let originalID = store.activeGroupId

        model.addGroup(ProfileGroup(name: "Created", bindings: []))

        #expect(!controller.isRunning)
        #expect(store.activeGroupId != originalID)
        #expect(store.activeGroup?.name == "Created")
    }

    @Test func duplicateGroupStopsControllerBeforeActivatingCopy() throws {
        let (model, store, controller, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        controller.isRunning = true
        let original = try #require(store.activeGroup)

        model.duplicateGroup(original)

        #expect(!controller.isRunning)
        #expect(store.groups.count == 2)
        #expect(store.activeGroupId != original.id)
        #expect(store.activeGroup?.name == "\(original.name) Copy")
    }

    @Test func saveGroupFlushesCommittedChangesImmediately() throws {
        let (model, store, _, defaults, suite) = makeModel()
        defer { defaults.removePersistentDomain(forName: suite) }

        var edited = try #require(store.activeGroup)
        edited.name = "Saved Immediately"

        model.saveGroup(edited)

        let data = try #require(defaults.data(forKey: "groups"))
        let persisted = try JSONDecoder().decode([ProfileGroup].self, from: data)
        #expect(persisted.contains(where: { $0.name == "Saved Immediately" }))
    }
}
