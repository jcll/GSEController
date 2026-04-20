# Changelog

All notable user-facing changes to GSEController are documented here.

---

## v1.1.3 — 2026-04-20

### Added
- Unsaved-changes guard in the profile editor — closing the editor or switching profiles prompts to save or discard when bindings have been modified.
- Import preview — importing a profile now shows a confirmation dialog with the profile name before overwriting existing data.
- Helper diagnostics card in the UI — exposes helper binary path, FIFO status, and compilation state for troubleshooting.
- Dedicated `GSEControllerUISmoke` scheme for UI automation, separate from the default test lane.

### Fixed
- Helper Accessibility trust check now validates the helper binary directly instead of relying on FIFO health, eliminating false positives when the helper lacks Accessibility permission.
- Start button now stays disabled until the helper is both compiled and Accessibility-trusted.
- `install.sh` now stages the new app bundle before replacing the existing one, and verifies the replacement succeeded before deleting the old copy.
- `install.sh` version check now handles missing or empty `LocalConfig.xcconfig` gracefully.
- CI workflows now use `RUNNER_TEMP` at step scope instead of top-level `env`, avoiding GitHub Actions parser errors.

### Changed
- Default shared scheme no longer includes UI smoke tests; they are opt-in via `GSEControllerUISmoke` scheme.
- README updated to explain helper trust boundaries, maintenance surface, and the verified local build/test workflow.
- README no longer narrates obvious code behavior; focuses on architecture decisions and operational constraints.

---

## v1.1.2 — 2026-04-09

### Fixed
- The WoW focus guard now blocks Tap and Modifier bindings as well as Rapid bindings, preventing accidental key or modifier output outside WoW.
- Held modifiers are now released when WoW loses focus while the focus guard is enabled, preventing stuck modifier keys after app switches.
- `ControllerManager.stop()` now routes its final modifier-release safety pass through the injected key-delivery interface instead of bypassing it.
- Low-battery notification hysteresis now resets only above 25% or while charging, matching the documented alert behavior.
- DualSense battery fallback reads are now explicitly nonisolated, clearing the Swift actor-isolation build warning for the background HID polling path.
- README profile and rate documentation now matches the current sidebar UI, millisecond presets, and templates.
- README helper-agent and uninstall documentation now reflects the bundle-identifier-derived launchd label instead of the old hardcoded label.

### Changed
- Added regression tests for focus-guard behavior across Tap, Modifier Hold, Rapid, accessibility revocation, and Stop-time modifier release.

---

## v1.1.1 — 2026-03-30

### Added
- `AppModel`, `ProfileStore`, and `KeyInjecting` seams to separate app workflow, profile persistence, and key-delivery concerns.
- Smoke UI test target for the create/edit/start/switch profile workflow, plus stable accessibility identifiers for the main editor actions.

### Fixed
- `install.sh` now creates `LocalConfig.xcconfig` automatically on fresh clones, so the documented install path works without manual setup.
- Start-up now waits for the key helper to be ready before marking a profile active, and pending starts are cancelled cleanly on Stop.
- Rapid and tap bindings now honor configured modifiers at runtime instead of silently dropping them.
- Template-based profile creation now regenerates profile/binding UUIDs and auto-selects the newly created profile.
- Duplicate controller-button assignments are surfaced in the editor, blocked from saving/starting, and no longer fail silently at runtime.
- Empty profile imports now surface a clear error, and importing over the active profile refreshes the editor draft correctly.
- Export failures now report as export errors, not import errors.
- Icon-only toolbar controls now provide explicit accessibility labels.

### Changed
- Project metadata and docs now target the Xcode 26.4 / Swift 6.3 toolchain while keeping Xcode's `SWIFT_VERSION = 6` language mode.
- App state now uses Swift Observation for the main workflow, controller, and profile store models, replacing the old manual Combine forwarding layer.
- The editor and runtime now share a single app-level workflow model, so selection/import/delete flows stop active sessions consistently.
- Battery fallback polling now runs off the main thread to avoid UI hitches during DualSense reads.
- The glass shimmer respects Reduce Motion and no longer idles on untinted surfaces.
- CI now uses `macos-26`, runs the test suite instead of build-only checks, and the test target inherits the base xcconfig so bundle identifiers resolve correctly.
- Test coverage expanded across helper readiness, duplicate binding validation, modifier delivery, empty import handling, corrupt-data backup recovery, and active-profile preservation.

---

## v1.1.0 — 2026-03-20

### Added
- **DualSense battery monitoring** — battery level and charging status now shown in the controller card. Uses `IOHIDDeviceGetReport` to pull the full BT input report (0x31) directly, working around macOS `GCDeviceBattery` always returning 0% for DualSense.
- **Low battery notification** — sends a macOS notification when the controller drops to or below 20%, with hysteresis (resets above 25% or when charging) to avoid repeated alerts.
- **Profile sidebar** — replaced the flat toolbar `Picker` with a `NavigationSplitView` sidebar for profile selection; profiles are listed with `+`/`−` controls and support right-click to delete.
- **Profile export / import** — Export and Import buttons in the sidebar toolbar write/read profiles as JSON via a save/open panel, making it easy to back up or share macro configs.
- **Unified accessibility setup card** — replaces sequential banners with a single card showing the status of both the app and Key Helper permissions simultaneously, with an auto-recheck on app focus.
- **FIFO health banner** — a yellow warning banner appears in the UI when the key-event delivery pipe to the helper is unhealthy, and clears automatically on recovery.
- **Graceful shutdown** — a SIGTERM handler releases any held modifier keys and stops the helper binary cleanly before the app exits.
- **Start/Stop button disabled caption** — the button now shows an inline explanation when it cannot be pressed (no controller connected, no bindings configured, or helper not yet ready).

### Fixed
- Silent key drops during rapid Stop/Start cycles — `KeySimulator` no longer closes the FIFO write fd on `stop()`, eliminating the blocking `O_WRONLY` open that could silently discard key events during the launchd restart window.
- AX permission revocation now detected immediately — the monitor loop no longer sleeps before its first check, so Accessibility being removed is caught at the next tick rather than after a 3-second delay.
- Retain cycle in `checkAccessibility()` — `Task.detached` now captures `[weak self]`, preventing `ControllerManager` from being kept alive indefinitely on rapid app activation.
- IOKit buffer race with two simultaneous DualSense controllers — each device now gets its own per-device buffer allocated in `attach()` and freed in `stop()`.
- Stale profile state in `ControllerManager` — replaced the cached `activeGroup: ProfileGroup?` snapshot with `activeGroupName` + `activeBindings` sourced live from `ProfileStore`, eliminating a divergence that could make the wrong bindings fire after a profile switch.
- "Publishing changes from within view updates" console warnings on launch — `@Published` mutations in `ControllerManager.init()` are now deferred into a `Task { @MainActor }`.
- Spurious `>` chevron artifact in sidebar toggle — replaced the system `NavigationSplitView` toggle button with a custom button; the built-in button left a persistent `>` toolbar artifact with no action.
- Transient navigation chevron visible during sidebar open/close animation — the custom toggle button is now hidden during the transition.

### Changed
- Liquid glass styling applied to the firing indicator status row.
- Glass effect polish on the permissions banner and new-profile sheet.
- Test suite expanded from 74 tests (15 suites) to 98 tests (21 suites).

---

## v1.0.0 — 2026-03-15

### Added
- Unit test suite (`GSEControllerTests`) — 29 tests covering `Models`, `FireEngine`, and `KeySimulator` pure logic using Swift Testing framework
- `ProfileStore.init(defaults:)` — injectable `UserDefaults` for testability
- `FireEngine.clampedInterval(rate:)` — extracted rate-to-interval formula, now testable
- `KeySimulator.encodeCommand(type:keyCode:)` — extracted FIFO encoding logic, now testable
- Shared Xcode scheme at `xcshareddata/xcschemes/GSEController.xcscheme` with test action

### Fixed
- `KeySimulator`: eliminated Swift 6 strict-concurrency warning — `kAXTrustedCheckOptionPrompt` global was accessed at static-let init time; now inlined at call site
- `KeyHelper.c.txt`: updated to document the actual 4-byte FIFO protocol (was showing the old 2-byte protocol)
- `ControllerManager`: removed dead property `lastAccessibilityCheck` (declared but never used; shadowed by a local inside `startTimer`)
- FIFO path moved from world-readable `/tmp` to per-user `$TMPDIR` — prevents same-uid processes from injecting keystrokes
- Helper binary is now ad-hoc signed after compilation for stable Accessibility trust identity
- `ensureHelper()` is now guarded by a one-shot flag — prevents concurrent compile on rapid Start/Stop
- `ensureHelper()` aborts before `open(fifoPath, O_WRONLY)` if binary is missing — prevents indefinite GCD thread block on compile failure
- `install.sh`: build failures now abort the script instead of being swallowed; app is no longer deleted before the new copy is confirmed
- `install.sh`: `xattr -cr` applied after install to remove quarantine attributes
- `install.sh`: `BUILD_DIR` derivation now asserts non-empty before proceeding
- Helper stderr log moved from `/tmp` to `~/Library/Logs/GSEController/helper.log`
- Added `NSAccessibilityUsageDescription` to `Info.plist`
- `make_icon.swift`: replaced `try!` with proper error handling
- Removed committed `xcuserdata/` from the repo
- `SWIFT_VERSION` set to `6` in both build configs
- `handleButton`: added `guard isRunning else { return }` to prevent stale button events from starting timers after `stop()`
- Profile persistence: `activeGroupId` is validated against loaded groups on init; orphaned IDs fall back to first group
- `ensureHelper()` called at app launch so the binary is compiled before the user ever presses Start

### Changed
- `FireEngine` extracted from `ControllerManager` — owns timers, modifier state, fire queue, and `NSProcessInfo` activity. `ControllerManager` is now a thin hardware adapter.
- `ProfileStore` switched to Swift 6 `@MainActor` isolation with `complete` strict concurrency checking
- Bundle ID, launchd label, and FIFO path derived at runtime from `Bundle.main.bundleIdentifier` — no more hardcoded `com.jcll` strings in the source
