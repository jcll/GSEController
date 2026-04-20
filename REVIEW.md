# GSEController — Remaining Review Findings

> Review date: 2026-04-20
> Build: **succeeds** | Tests: **137/137 pass**

---

## Architecture

### ARCH-01 — `ControllerManager` is still a God Object (partial fix only)
- **Severity:** Medium
- **File:** `GSEController/ControllerManager.swift`
- **Note:** `FocusTracker` extracted. Battery monitoring, permission rechecking, and controller connection logic still live inside `ControllerManager` (~570 lines). Further extraction into `BatteryMonitor`, `PermissionChecker`, and `ControllerConnectionService` deferred.
- **Effort:** large

### ARCH-03 — `ContentView` is a God View
- **Severity:** Medium
- **File:** `GSEController/ContentView.swift`
- **Note:** Still ~955 lines. Draft state, unsaved-changes guard, action routing, and panel presentation belong in a `ContentViewModel`.
- **Effort:** large

### ARCH-05 — No central error taxonomy
- **Severity:** Medium
- **Files:** `GSEController/ControllerManager.swift`, `AppModel.swift`, `KeySimulator.swift`
- **Note:** Failures still surface as ad-hoc strings. No unified `GSEError` enum or `ErrorCoordinator`.
- **Effort:** medium

### ARCH-07 — Flat module structure
- **Severity:** Low
- **File:** `GSEController/` directory
- **Note:** All source files still in single flat directory. No `Domain/`, `Services/`, `UI/` grouping.
- **Effort:** small

---

## Features

### FEAT-07 — `DualSenseBatteryMonitor.deinit` uses `MainActor.assumeIsolated`
- **Severity:** Medium
- **File:** `GSEController/DualSenseBatteryMonitor.swift:58-61`
- **Note:** `deinit` of a `@MainActor` class is not guaranteed to run on main. Move cleanup to an explicit `shutdown()` called from `ControllerManager.deinit`.
- **Effort:** small

### FEAT-13 — D-pad mode picker allows invalid selection before forced override
- **Severity:** Low
- **File:** `GSEController/BindingRow.swift`
- **Note:** Mode picker shows all three modes for every button. D-pad selection silently overrides to `.modifierHold`, causing flicker.
- **Effort:** small

---

## UI/UX

### UI-11 — Helper error card offers Terminal command without copy action
- **Severity:** Low
- **File:** `GSEController/ContentView.swift`
- **Note:** Card tells user to "Run `xcode-select --install` in Terminal" with no button to copy or open Terminal.
- **Effort:** small

### UI-13 — No keyboard shortcut for Save in profile editor
- **Severity:** Low
- **File:** `GSEController/GroupEditorCard.swift`
- **Note:** Save button lacks `.keyboardShortcut(.defaultAction)` or `.keyboardShortcut("s", modifiers: .command)`.
- **Effort:** small

---

## Tests

All TEST-02 through TEST-16 coverage gaps remain:
- **TEST-02:** Zero tests for `BindingRow` editor normalization
- **TEST-03:** Zero tests for `GroupEditorCard` draft lifecycle
- **TEST-04:** `ContentView` unsaved-changes navigation untested
- **TEST-05:** `FireEngine` rapid-fire timer never verified to fire
- **TEST-06:** `ControllerManager.handleButton` routing untested
- **TEST-08:** Missing e2e tests (start/stop, export/import, unsaved changes)
- **TEST-09:** `uniqueName` collision logic untested
- **TEST-10:** `KeySimulator` helper lifecycle failure branches untested
- **TEST-11:** `AppModel` export/import error paths untested
- **TEST-12:** `DualSenseBatteryMonitor` IOKit paths untested
- **TEST-13:** Flaky polling in `ScheduleSaveDebounceTests`
- **TEST-14:** No macOS 26-specific API behavior tests
- **TEST-15:** `GSEControllerApp` SIGTERM handler untested
- **TEST-16:** `retryHelperSetup` / `checkAccessibility` untested

---

## DevOps

### OPS-03 — Unsigned CI builds with hardened runtime enabled
- **Severity:** Medium
- **File:** `.github/workflows/build.yml`
- **Note:** CI still disables code signing (`CODE_SIGN_IDENTITY=""`). Add a signed release lane with Developer ID.
- **Effort:** medium

### OPS-05 — `ENABLE_USER_SCRIPT_SANDBOXING` conflicts with disabled app sandbox
- **Severity:** Low
- **File:** `GSEController.xcodeproj/project.pbxproj`
- **Note:** `ENABLE_USER_SCRIPT_SANDBOXING = YES` while entitlements set `app-sandbox = false`.
- **Effort:** small

### OPS-06 — GitHub Actions use floating major versions
- **Severity:** Low
- **Files:** `.github/workflows/build.yml`, `.github/workflows/ui-smoke.yml`
- **Note:** `actions/checkout@v4`, `actions/upload-artifact@v4`, `actions/cache@v4` still floating.
- **Effort:** small

### OPS-09 — `install.sh` xattr removal is overly broad
- **Severity:** Low
- **File:** `install.sh:156`
- **Note:** `xattr -cr` strips all extended attributes. Should target only `com.apple.quarantine`.
- **Effort:** small

---

## Grade

**B** — All critical blockers resolved. App compiles, tests pass, hot-path performance fixed, silent failures surfaced, and major architectural debt reduced. Remaining work is medium/low priority: deeper god-object splits, test coverage, and CI hardening.
