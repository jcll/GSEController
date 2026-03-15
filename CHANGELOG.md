# Changelog

All notable user-facing changes to GSEController are documented here.

---

## Unreleased

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
