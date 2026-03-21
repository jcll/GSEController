# GSEController — Parallel Code Review

> Generated 2026-03-20 · 7 specialist agents run in parallel

---

## 1. Dashboard

| Task         | Critical | High | Medium | Low | One-Line Assessment |
|--------------|----------|------|--------|-----|---------------------|
| Bug Hunt     | 1        | 2    | 2      | 2   | IOKit use-after-free is real; concurrency discipline otherwise strong |
| Architecture | 0        | 0    | 4      | 3   | Well-structured for scope; silent data-loss on corrupt profiles is the key gap |
| Features     | 0        | 2    | 5      | 4   | Duplicate-binding conflict and stale-binding-on-restart are user-visible breakage |
| UI/UX        | 0        | 1    | 5      | 3   | Above-average a11y; disabled editor needs an explanation banner |
| Performance  | 0        | 0    | 2      | 2   | Hot path is excellent; activeGroup O(n) scan in render path is worth fixing |
| Tests        | 1        | 4    | 5      | 2   | Core FireEngine lifecycle and DualSenseBatteryMonitor have zero coverage |
| DevOps       | 1        | 0    | 2      | 1   | CI is broken today due to missing LocalConfig.xcconfig generation step |
| **Total**    | **3**    | **9**| **21** |**17**| |

**Grade: C — Significant work needed before confident release**

The score is dragged down by 3 criticals (crash risk, broken CI, missing timer tests) and 9 highs. The underlying code quality is genuinely good — concurrency discipline, the KeyHelper architecture, lock usage, and legacy migration all show sophisticated thinking. But several real user-visible bugs and an entirely broken CI pipeline need attention before this can be called production-ready.

---

## 2. Quick Wins

_Critical (any effort) + High/small effort items._

| ID       | Title                                           | Task     | Effort |
|----------|-------------------------------------------------|----------|--------|
| OPS-01   | CI broken: missing LocalConfig.xcconfig step    | DevOps   | small  |
| TEST-01  | No tests for FireEngine startFiring/stopFiring  | Tests    | small  |
| BUG-02   | Strong self capture / redundant main.async      | Bug Hunt | small  |
| BUG-05   | stop() clears activeBindings before handlers can clear | Bug Hunt | small |
| FEAT-01  | Duplicate button bindings silently conflict     | Features | small  |
| FEAT-02  | Stale bindings used if group changes while stopped | Features | small |
| UI-01    | Disabled editor gives no explanation            | UI/UX    | small  |
| ARCH-03  | ProfileStore silently swallows decode failures  | Arch     | small  |
| BUG-07   | D-pad buttons missing from legacy Codable migration | Bug Hunt | small |
| TEST-04  | No test for ControllerButton unknown raw value  | Tests    | small  |

---

## 3. Critical & High Findings

### Bug Hunt

#### BUG-01 — IOKit callbacks use `passUnretained(self)` and can dangle after `stop()`
- **Severity:** Critical
- **File:** `GSEController/DualSenseBatteryMonitor.swift:83,123`
- **Problem:** Both `IOHIDManagerRegisterDeviceMatchingCallback` and `IOHIDDeviceRegisterInputReportCallback` pass `Unmanaged.passUnretained(self).toOpaque()` as context. This does not retain the object. If a callback fires during or after `stop()` / `deinit`, `Unmanaged.fromOpaque(ctx).takeUnretainedValue()` on freed memory is a use-after-free crash.
- **Fix:** Use `Unmanaged.passRetained(self)` (balance with explicit release in `stop()`), or nil-check a weak reference inside the callback. Alternatively, explicitly deregister the input report callback with a nil handler for each known device inside `stop()` before clearing `knownDevices`.
- **Effort:** medium

#### BUG-02 — `DispatchQueue.main.async { self.onUpdate?(...) }` strong-captures self when already on MainActor
- **Severity:** High
- **File:** `GSEController/DualSenseBatteryMonitor.swift:146,169,187,218`
- **Problem:** `pollDeviceProperty` (already `@MainActor`) uses `DispatchQueue.main.async { self.onUpdate?(...) }`, which strongly captures `self` unnecessarily and extends object lifetime past teardown. The `handle()` callback (line 218) does the same without `[weak self]`. Combined with BUG-01, this can keep a partially-torn-down object alive.
- **Fix:** Lines 146, 169, 187: call `self.onUpdate?(pct, charging)` directly — already on `@MainActor`. Line 218: use `[weak self]` capture.
- **Effort:** small

#### BUG-05 — `stop()` zombie handler leak when controller disconnects during a session
- **Severity:** High
- **File:** `GSEController/ControllerManager.swift:296-310,346-351`
- **Problem:** `clearButtonHandlers()` exits early when `controller?.extendedGamepad` is nil (which happens on disconnect). The stale `pressedChangedHandler` closures from the previous session remain on the gamepad inputs and capture `[weak self]` on `ControllerManager`, preventing deallocation if `ControllerManager` is ever replaced.
- **Fix:** Clear handlers *before* nil-ing the controller in `controllerDisconnected`, or unconditionally clear them in `connectController` before attaching new ones.
- **Effort:** small

---

### Features

#### FEAT-01 — Duplicate button bindings are allowed and silently conflict
- **Severity:** High
- **File:** `GSEController/ContentView.swift:630-641`, `GSEController/ControllerManager.swift:337-343`
- **Problem:** The UI shows a warning when a button is already assigned, but nothing prevents saving a duplicate. In `attachHandlers`, the last binding for a button wins — earlier bindings are silently dropped. The user sees multiple configured bindings but only one fires.
- **Fix:** Enforce uniqueness at save time (disable Save or auto-reject duplicates). The `addBinding()` method already picks the next unused button, so this is a validation gap on manual edits only.
- **Effort:** small

#### FEAT-02 — Active group selection change while stopped leaves stale state on reconnect
- **Severity:** High
- **File:** `GSEController/ControllerManager.swift:272-293`, `GSEController/ContentView.swift:80-86`
- **Problem:** `activeBindings` is a snapshot captured at `start()`. If a controller reconnects while running (`connectController` calls `attachHandlers` with the old snapshot), or if `activeGroupId` changes while stopped and the user restarts, the sidebar highlights a different group than what is actually firing.
- **Fix:** When sidebar selection changes while `isRunning`, call `controller.stop()` automatically, or observe `store.activeGroupId` in `ControllerManager` and re-attach handlers.
- **Effort:** small

---

### UI/UX

#### UI-01 — Disabled editor gives no explanation for why editing is locked
- **Severity:** High
- **File:** `GSEController/ContentView.swift:85-86`
- **Problem:** When `controller.isRunning` is true, the entire `GroupEditorCard` is disabled at 0.6 opacity with no text, tooltip, or VoiceOver hint explaining why. A user who starts firing and tries to edit will see a grayed-out form with no indication of what to do.
- **Fix:** Add a banner inside the card ("Stop firing to edit bindings") when `isRunning`, or add `.help("Stop the controller to enable editing")` and `.accessibilityHint("Stop the controller to enable editing")`.
- **Effort:** small

---

### Tests

#### TEST-01 — No tests for FireEngine timer lifecycle (startFiring / stopFiring / stopAll)
- **Severity:** Critical
- **File:** `GSEControllerTests/FireEngineTests.swift`
- **Problem:** `startFiring()`, `stopFiring()`, and `stopAll()` — the core rapid-fire engine — are completely untested. The existing tests only cover `clampedInterval` (pure function) and modifier state. No test verifies `isFiring` transitions, duplicate `startFiring` guard, or multi-button `stopAll`.
- **Fix:** Add unit tests. The timer event handler calls `KeySimulator.pressKey` which is a safe no-op when the helper fd is -1, so tests can run without side effects:
  ```swift
  @Test @MainActor func startFiringSetsIsFiringTrue() {
      let engine = FireEngine()
      engine.startFiring(binding: MacroBinding(button: .rightShoulder))
      #expect(engine.isFiring == true)
      engine.stopAll()
  }

  @Test @MainActor func stopFiringLastButtonSetsIsFiringFalse() {
      let engine = FireEngine()
      let b = MacroBinding(button: .rightShoulder)
      engine.startFiring(binding: b)
      engine.stopFiring(button: .rightShoulder)
      #expect(engine.isFiring == false)
  }

  @Test @MainActor func startFiringSameButtonTwiceIsIdempotent() {
      let engine = FireEngine()
      let b = MacroBinding(button: .rightShoulder)
      engine.startFiring(binding: b)
      engine.startFiring(binding: b)
      engine.stopFiring(button: .rightShoulder)
      #expect(engine.isFiring == false)
  }

  @Test @MainActor func stopAllClearsAllTimers() {
      let engine = FireEngine()
      engine.startFiring(binding: MacroBinding(button: .rightShoulder))
      engine.startFiring(binding: MacroBinding(button: .leftShoulder, keyName: "1", keyCode: 0x12))
      engine.stopAll()
      #expect(engine.isFiring == false)
  }
  ```
- **Effort:** small

#### TEST-02 — No tests for ControllerManager start/stop state transitions
- **Severity:** High
- **File:** `GSEControllerTests/ControllerManagerTests.swift`
- **Problem:** `start(group:)` has three early-exit branches (no controller, no AX, happy path) and `stop()` releases all modifiers. None of these paths are tested. The existing tests only cover `isWoW` matching and `requireWoWFocus` persistence.
- **Fix:** Add unit tests for the no-controller and stop paths (skeleton):
  ```swift
  @Test @MainActor func startWithoutControllerSetsStatusMessage() {
      let manager = ControllerManager(defaults: makeTestDefaults())
      manager.start(group: ProfileGroup(name: "Test", bindings: []))
      #expect(manager.isRunning == false)
      // statusMessage should indicate no controller
  }
  @Test @MainActor func stopSetsIsRunningFalse() {
      let manager = ControllerManager(defaults: makeTestDefaults())
      manager.stop()
      #expect(manager.isRunning == false)
  }
  ```
- **Effort:** small

#### TEST-03 — DualSenseBatteryMonitor has zero test coverage
- **Severity:** High
- **File:** `GSEController/DualSenseBatteryMonitor.swift:162-171,179-190,207-213`
- **Problem:** The battery byte parsing logic (nibble extraction, percentage formula, charging boolean) is copy-pasted in three places and has no tests. An off-by-one in the nibble extraction would silently display wrong battery levels and wrong low-battery notifications.
- **Fix:** Extract `parseBatteryByte(_ byte: UInt8) -> (level: Float, charging: Bool)?` and add unit tests for boundary values (level=0, level=1, level=10, charging nibbles 1 and 2).
- **Effort:** medium (small refactor required)

#### TEST-04 — No test for ControllerButton unknown raw value error path
- **Severity:** High
- **File:** `GSEControllerTests/ModelsTests.swift`
- **Problem:** The `default:` case in `ControllerButton.init(from:)` throws `DecodingError.dataCorruptedError`. This is untested — if someone accidentally removes the throw, corrupt data would load silently.
- **Fix:**
  ```swift
  @Test func unknownRawValueThrowsDecodingError() {
      let data = try! JSONEncoder().encode("TotallyBogus")
      #expect(throws: DecodingError.self) {
          try JSONDecoder().decode(ControllerButton.self, from: data)
      }
  }
  ```
- **Effort:** small

#### TEST-05 — No test verifying D-pad buttons use the modern decode path
- **Severity:** High
- **File:** `GSEControllerTests/ModelsTests.swift`
- **Problem:** The legacy decoder switch has no D-pad entries. If someone accidentally adds an incorrect D-pad legacy mapping, the existing tests would not catch it. The test also does not confirm that the new camelCase values (`"dpadDown"` etc.) pass through the modern `ControllerButton(rawValue:)` path.
- **Fix:** The existing `camelCaseRawValuesRoundTrip` test covers the happy path. Add:
  ```swift
  @Test func legacyDpadDisplayNamesAreNotDecoded() {
      for raw in ["D-Pad ↓", "D-Pad ←", "D-Pad →", "D-Pad ↑"] {
          let data = try! JSONEncoder().encode(raw)
          #expect(throws: DecodingError.self) {
              try JSONDecoder().decode(ControllerButton.self, from: data)
          }
      }
  }
  ```
- **Effort:** small

---

### DevOps

#### OPS-01 — CI build is broken: LocalConfig.xcconfig not generated in workflow
- **Severity:** Critical
- **File:** `.github/workflows/build.yml:17-28`
- **Problem:** `project.pbxproj` references `LocalConfig.xcconfig` (which defines `BUNDLE_ID_PREFIX` and `PRODUCT_BUNDLE_IDENTIFIER`) as the base configuration for both Debug and Release. This file is in `.gitignore` and does not exist on the CI runner. The build either errors out or produces a malformed bundle identifier like `.GSEController`. CI currently provides zero signal.
- **Fix:** Add a step before the build:
  ```yaml
  - name: Create LocalConfig.xcconfig
    run: |
      cat > LocalConfig.xcconfig << 'EOF'
      BUNDLE_ID_PREFIX = com.example
      PRODUCT_BUNDLE_IDENTIFIER = $(BUNDLE_ID_PREFIX).GSEController
      EOF
  ```
- **Effort:** small

---

## 4. Medium Findings

### Bug Hunt

#### BUG-03 — `pollDeviceProperty` always reports `charging: false` via BatteryLevel path
- **Severity:** Medium
- **File:** `GSEController/DualSenseBatteryMonitor.swift:146`
- **Problem:** When the `BatteryLevel` IOKit property is available, `onUpdate` is called with `charging: false` hardcoded. The UI will show "not charging" even when plugged in via this path, and will flip to "charging" only when the BT report path wins on a later poll — causing flickering.
- **Fix:** Read `"BatteryIsCharging"` from `IOHIDDeviceGetProperty`, or remove the early return so execution always falls through to the report-based path which correctly parses charging state.
- **Effort:** small

#### BUG-07 — D-pad buttons missing from ControllerButton legacy Codable migration
- **Severity:** Medium
- **File:** `GSEController/Models.swift:79-95`
- **Problem:** The `init(from:)` decoder handles 10 legacy display strings but not D-pad buttons (`"D-Pad ↓"`, `"D-Pad ←"`, `"D-Pad →"`, `"D-Pad ↑"`). If any pre-migration user had D-pad bindings, the entire profile group would fail to decode, silently reverting to the default profile and losing all user data. _(Also flagged by Features and UI/UX reviewers.)_
- **Fix:** Add four cases to the migration switch:
  ```swift
  case "D-Pad ↓": self = .dpadDown
  case "D-Pad ←": self = .dpadLeft
  case "D-Pad →": self = .dpadRight
  case "D-Pad ↑": self = .dpadUp
  ```
- **Effort:** small

---

### Architecture

#### ARCH-01 — ContentView is a 1020-line monolith with 6 distinct view types
- **Severity:** Medium
- **File:** `GSEController/ContentView.swift:1-1021`
- **Problem:** `ContentView`, `ControllerMapView`, `GroupEditorCard`, `BindingRow`, `NewGroupSheet`, and helpers coexist in one file. Each is a self-contained view with its own state. As features are added, this file becomes difficult to navigate and modify safely.
- **Fix:** Extract each struct into its own file (`ControllerMapView.swift`, `GroupEditorCard.swift`, `BindingRow.swift`, `NewGroupSheet.swift`). Mechanical move, no API changes.
- **Effort:** small

#### ARCH-02 — ControllerManager handles too many concerns (11 `@Published` properties)
- **Severity:** Medium
- **File:** `GSEController/ControllerManager.swift:9-387`
- **Problem:** Single class owns controller IO, WoW focus tracking, battery polling, notification delivery, and permission management. The WoW focus block (lines 153-200) and battery monitoring (lines 204-257) are independent concerns.
- **Fix:** Extract a `WoWFocusTracker` class for WoW focus. Move `checkLowBattery` into `DualSenseBatteryMonitor`. `ControllerManager` observes both via Combine or `onChange`.
- **Effort:** medium

#### ARCH-03 — ProfileStore silently swallows decode failures, losing all user profiles
- **Severity:** Medium
- **File:** `GSEController/Models.swift:262-263`
- **Problem:** `try? JSONDecoder().decode(...)` silently returns nil on corrupted `UserDefaults` data and falls through to the default profile, erasing all user data with no log entry or recovery path.
- **Fix:** Replace `try?` with a `do/catch` that logs the error and copies the raw data to a backup key before falling through.
- **Effort:** small

#### ARCH-04 — Battery-byte parsing logic copy-pasted in three places
- **Severity:** Medium
- **File:** `GSEController/DualSenseBatteryMonitor.swift:161-171,179-190,206-213`
- **Problem:** The 6-line nibble extraction and percentage calculation is duplicated across `pollDeviceProperty` (BT path), `pollDeviceProperty` (USB path), and `handle(reportID:data:length:)`. A bug or format change must be fixed in all three.
- **Fix:** Extract `parseBatteryByte(_ byte: UInt8) -> (level: Float, charging: Bool)?`.
- **Effort:** small

---

### Features

#### FEAT-03 — `requireWoWFocus` toggle while running doesn't affect in-flight timers
- **Severity:** Medium
- **File:** `GSEController/ControllerManager.swift:26-29`, `GSEController/FireEngine.swift:69`
- **Problem:** Timer closures capture `requireWoWFocus` as `let` at `startFiring` time. Toggling the setting while holding a button will not take effect until the button is released and re-pressed.
- **Fix:** Back `requireWoWFocus` with an `OSAllocatedUnfairLock<Bool>` (same pattern as `_wowIsActive`) and read it inside the timer closure.
- **Effort:** small

#### FEAT-04 — Battery level of 0% is treated as "no data" and silently discarded
- **Severity:** Medium
- **File:** `GSEController/DualSenseBatteryMonitor.swift:165,183`, `GSEController/ControllerManager.swift:253`
- **Problem:** The DualSense encodes 0% battery as `level = 0`. The code uses `guard level > 0` as the validity check, so a truly empty controller appears as "no battery indicator" rather than "critically low".
- **Fix:** Track session validity separately (e.g., a `hasReceivedData` flag) rather than using `level == 0` as sentinel.
- **Effort:** medium

#### FEAT-05 — No profile export / import — data lives only in UserDefaults
- **Severity:** Medium
- **File:** `GSEController/Models.swift:298-306`
- **Problem:** All profiles are stored in `UserDefaults` with no backup or migration path. Users who move to a new Mac or hit corruption lose everything. `ProfileGroup` is already fully `Codable`.
- **Fix:** Add File menu items: "Export Profiles" (JSON save panel) and "Import Profiles" (JSON open panel).
- **Effort:** medium

#### FEAT-06 — No UI feedback when FIFO write fails and key events are silently dropped
- **Severity:** Medium
- **File:** `GSEController/KeySimulator.swift:145-160`
- **Problem:** When `writeCommand` fails, a background reconnect is attempted. During the retry window, all key presses are silently dropped — the status bar still shows "FIRING" but nothing reaches WoW.
- **Fix:** Expose a `@Published var fifoHealthy: Bool` on `ControllerManager` and show a warning banner (same pattern as the existing helper-error card).
- **Effort:** medium

#### FEAT-07 — Modifier key stays stuck if app is killed while modifier is held
- **Severity:** Medium
- **File:** `GSEController/ControllerManager.swift:296-310`, `GSEController/FireEngine.swift:128-137`
- **Problem:** `stop()` and `stopAll()` correctly release modifiers on graceful shutdown, but a crash or SIGKILL skips this. The KeyHelper process remains running via launchd, and the modifier key stays "held" system-wide.
- **Fix:** Register a `SIGTERM` handler to release modifiers, or add a heartbeat in KeyHelper: if no command arrives within N seconds, auto-release any held modifier keys.
- **Effort:** medium

---

### UI/UX

#### UI-02 — Start button disabled state has no inline explanation
- **Severity:** Medium
- **File:** `GSEController/ContentView.swift:430-436`
- **Problem:** When the Start button is disabled (no controller, no bindings, or helper not ready), the only feedback is system dimming. Tooltips are invisible to keyboard and VoiceOver users.
- **Fix:** Show a small inline caption below the button stating the specific reason (e.g., "Connect a controller to start"), mirroring the existing helper-error card pattern.
- **Effort:** small

#### UI-03 — Delete confirmation has no message body explaining permanence
- **Severity:** Medium
- **File:** `GSEController/ContentView.swift:127-137`
- **Problem:** The confirmation dialog has a title and a destructive button but no `message:` parameter. Users don't know the action is permanent and all bindings will be lost.
- **Fix:** Add `message: { Text("This profile and all its bindings will be permanently deleted.") }`.
- **Effort:** small

#### UI-04 — Sidebar "+" and "−" buttons lack VoiceOver accessibility labels
- **Severity:** Medium
- **File:** `GSEController/ContentView.swift:36-57`
- **Problem:** VoiceOver announces these as "plus, button" and "minus, button". `.help()` tooltips are not read by VoiceOver.
- **Fix:** Add `.accessibilityLabel("New profile")` and `.accessibilityLabel("Delete profile")`.
- **Effort:** small

#### UI-05 — Permission action buttons lack contextual accessibility labels
- **Severity:** Medium
- **File:** `GSEController/ContentView.swift:223-242`
- **Problem:** "Grant Access" and "Open Settings" are generic labels. A VoiceOver user tabbing through the form hears identical button names for different rows without knowing which permission they act on.
- **Fix:** Use descriptive labels: "Grant GSEController Accessibility Access" / "Open Settings for Key Helper", or add `.accessibilityLabel()` with row context.
- **Effort:** small

#### UI-06 — ConsolePort info sheet not dismissible via Escape key
- **Severity:** Medium
- **File:** `GSEController/ContentView.swift:355-359`
- **Problem:** The "Done" button lacks `.keyboardShortcut(.cancelAction)`. The `NewGroupSheet` Cancel button correctly has it; this sheet does not, breaking the standard macOS Escape-to-dismiss convention.
- **Fix:** Add `.keyboardShortcut(.cancelAction)` to the "Done" button.
- **Effort:** small

---

### Performance

#### PERF-01 — Two `OSAllocatedUnfairLock` acquisitions with closure allocation on every timer tick
- **Severity:** Medium
- **File:** `GSEController/FireEngine.swift:109-112`
- **Problem:** Every timer event acquires two locks sequentially. At 20 pps with multiple active bindings, this is 40–80 closure-allocating lock calls per second on a `userInteractive` QoS queue.
- **Fix:** Replace `OSAllocatedUnfairLock<Bool>` with `Atomic<Bool>` (Synchronization framework, available on macOS 26+) for lock-free reads with zero closure overhead.
- **Effort:** small

#### PERF-02 — `activeGroup` O(n) linear scan called on every SwiftUI re-render
- **Severity:** Medium
- **File:** `GSEController/Models.swift:226-228`
- **Problem:** `groups.first { $0.id == activeGroupId }` runs on every `ContentView` body evaluation. With `isFiring` publishing at up to 20 Hz, downstream re-renders could trigger this scan frequently.
- **Fix:** Cache the active group in a `@Published` property updated in `didSet` of both `groups` and `activeGroupId`, or use a `Dictionary<UUID, ProfileGroup>` for O(1) lookup.
- **Effort:** small

---

### Tests

#### TEST-06 — No test for `activeGroup` computed property
- **Severity:** Medium
- **File:** `GSEControllerTests/ModelsTests.swift`
- **Problem:** `activeGroup` is used by `ContentView` to determine what to display and what to pass to `start()`. No test verifies it returns the correct group, nil when `activeGroupId` is nil, or nil when the ID doesn't match.
- **Fix:** Add unit tests covering the nil and matching cases.
- **Effort:** small

#### TEST-07 — No test for `MacroBinding` Equatable conformance
- **Severity:** Medium
- **File:** `GSEControllerTests/ModelsTests.swift`
- **Problem:** SwiftUI diffing in the binding editor relies on `Equatable`. A field added with a non-Equatable type would compile-fail; but a custom `==` accidentally excluding a field would not be caught.
- **Fix:** Add a smoke test asserting two bindings differing only by `label` are not equal.
- **Effort:** small

#### TEST-08 — No test for `wowIsActive` thread-safe lock round-trip
- **Severity:** Medium
- **File:** `GSEControllerTests/FireEngineTests.swift`
- **Problem:** `wowIsActive` uses `OSAllocatedUnfairLock` for cross-isolation safety. A refactor removing the lock wrapper would break correctness silently.
- **Fix:** Add a simple get/set round-trip test.
- **Effort:** small

#### TEST-09 — No test for `checkLowBattery` notification threshold logic
- **Severity:** Medium
- **File:** `GSEController/ControllerManager.swift:222-236`
- **Problem:** The `lowBatteryNotified` flag state machine (notify once at ≤20%, reset when charging or above 20%) is entirely untested. Notification spam or missed warnings would be user-visible.
- **Fix:** Extract `shouldNotifyLowBattery(level:charging:alreadyNotified:) -> Bool` as a static pure function and add unit tests for the three branches.
- **Effort:** medium

#### TEST-10 — No integration test for `scheduleSave` debounce round-trip
- **Severity:** Medium
- **File:** `GSEController/Models.swift:288-296`
- **Problem:** No test verifies that mutations to `groups` actually persist to `UserDefaults` after the 300ms debounce. The existing tests pre-seed defaults and read back, but never exercise the `didSet` → `scheduleSave` → `save` chain.
- **Fix:** Add an async test that mutates, `Task.sleep(for: .milliseconds(500))`, then reads back from `UserDefaults`.
- **Effort:** small

---

### DevOps

#### OPS-02 — `install.sh` writes to predictable world-readable temp path
- **Severity:** Medium
- **File:** `install.sh:44`
- **Problem:** Build log is written to `/tmp/gse_build.log` — a predictable path that could be symlink-attacked on a multi-user system.
- **Fix:** Use `BUILD_LOG=$(mktemp /tmp/gse_build.XXXXXX)` and clean up at script exit.
- **Effort:** small

#### OPS-03 — `install.sh` doesn't guard against missing `make_icon.swift`
- **Severity:** Medium
- **File:** `install.sh:8`
- **Problem:** `swift make_icon.swift "$ICON_DIR"` has no existence check. A missing file produces a cryptic Swift compiler error. The script has good guards elsewhere (lines 34, 56).
- **Fix:** Add `if [ ! -f make_icon.swift ]; then echo "❌  make_icon.swift not found"; exit 1; fi` before line 8.
- **Effort:** small

---

## 5. Low Findings

| ID       | Title                                                       | Task     | Effort |
|----------|-------------------------------------------------------------|----------|--------|
| BUG-04   | Redundant outer `[weak self]` in batteryTimer closure       | Bug Hunt | small  |
| BUG-06   | `removeObserver(self)` in `deinit` is no-op and racy on macOS 10.11+ | Bug Hunt | small |
| ARCH-05  | No protocol abstraction between ControllerManager and FireEngine | Arch | medium |
| ARCH-06  | Ad hoc error handling (mix of `try?`, empty `catch {}`, logged) | Arch | small |
| ARCH-07  | Template data baked into view code rather than model layer  | Arch     | small  |
| FEAT-09  | No keyboard shortcut for Start/Stop                         | Features | small  |
| FEAT-10  | `scheduleSave()` empty `catch {}` swallows real errors      | Features | small  |
| FEAT-11  | `batteryTimer` wraps main-thread call in unnecessary `Task { @MainActor }` | Features | small |
| UI-07    | Custom rate slider only discoverable by knowing to type a non-preset value | UI/UX | medium |
| UI-08    | Duplicate rate display (`x/sec` and `/s`) when custom rate is active | UI/UX | small |
| UI-09    | `.windowResizability(.contentSize)` prevents user growing window | UI/UX | small |
| PERF-03  | Intentional `DispatchQueue.main.async` deferral in battery callbacks (by design) | Perf | — |
| PERF-04  | `templates` array recomputed on every `NewGroupSheet` body evaluation | Perf | small |
| TEST-11  | Four individual preset tests are strict subsets of the array tests | Tests | small |
| TEST-12  | `encodeCommand` test passes max UInt16 but doesn't assert encoded bytes | Tests | small |
| OPS-04   | `.gitignore` includes irrelevant Node/Python/Rust/Go ecosystem entries | DevOps | small |

---

## 6. Recommendations

### Priority order

1. **Fix BUG-01 + BUG-02 together** (IOKit use-after-free + strong self) — both are in `DualSenseBatteryMonitor.swift` and share a root cause. Fix BUG-01 first (adopt `passRetained`), then BUG-02 follows naturally (direct `onUpdate` calls on `@MainActor`). This is the only crash-risk finding.

2. **Fix OPS-01** (CI LocalConfig.xcconfig) — one-line workflow addition, unblocks CI from providing any signal. Do this before the next push.

3. **Fix FEAT-01 + FEAT-02** (duplicate bindings, stale bindings) — both are small and directly impact user-visible behavior in the core use case.

4. **Add TEST-01 + TEST-03** (FireEngine lifecycle, DualSenseBatteryMonitor battery parsing) — TEST-03 requires the ARCH-04 refactor to extract `parseBatteryByte`, so do ARCH-04 first. Together these two test additions cover the two most uncharted critical paths.

5. **Fix ARCH-03** (ProfileStore silent data loss on corrupt defaults) — small change, prevents a class of invisible data loss. Do this before adding export/import (FEAT-05) so the import path also gets the safety net.

> **Dependency note:** Fix ARCH-04 (extract `parseBatteryByte`) before TEST-03 (it requires the extracted function). Fix ARCH-03 before FEAT-05 (export/import should not import into a silently-failing store).
