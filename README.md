# GSEController

A macOS app that turns your PS5 (or Xbox) controller into a rapid-fire keyboard macro trigger for World of Warcraft — designed for use with [GSE (GnomeSequencer Enhanced)](https://www.curseforge.com/wow/addons/gse-gnome-sequencer-enhanced-advanced-macros).

> **Requires macOS 26 Tahoe and the Xcode 26.4 / Swift 6.3 toolchain.** This app does not run on macOS 15 Sequoia or earlier.

## Why use a controller?

GSE rotation macros advance their sequence on each keypress — which means you need to press the same key dozens of times per minute to keep your rotation going. Doing that manually is tiring, inconsistent, and hard on your hands.

With GSEController, you hold a trigger button and the app fires your macro key at a steady, configurable rate. Your rotation runs consistently without any hammering, and your keyboard hand stays free for cooldowns, targeting, and movement.

D-pad buttons add a second layer: hold one and it sends a modifier key (Alt/Shift/Ctrl) to WoW, which activates a conditional branch in your GSE sequence — letting you inject an interrupt, a defensive, or a proc ability mid-rotation without breaking the loop.

<p align="center"><img src="screenshot.png" width="500"></p>
<p align="center"><em>Profile editor showing a Guardian Druid setup — an R1 Rapid binding with D-pad modifier bindings shown in the controller map.</em></p>

## Features

- **Multiple profiles** — one per class/spec, switch from the sidebar
- **Profile duplication and notes** — clone a setup for a variant and keep keybind/spec notes with it
- **Per-button configuration** — assign any controller button to any key, with any fire mode
- **Three fire modes:**
  - **Rapid** — spams the key while held (for GSE rotation macros)
  - **Tap** — fires once per press (for manual cooldowns)
  - **Modifier** — holds Alt/Shift/Ctrl while pressed (activates conditional branches in your GSE sequence)
- **Configurable rate** — preset millisecond delays from 340 ms to 100 ms, or a custom slider
- **Controller map** — visual overview of all your bindings at a glance
- **WoW focus guard** — optionally only fires when WoW is the active window
- **Profile templates** — pre-built starting points for common specs and roles
- **Safer imports and diagnostics** — preview replace/merge imports, release held keys, and copy helper diagnostics for troubleshooting

## Requirements

- macOS 26 Tahoe beta (does not run on macOS 15 Sequoia or earlier)
- Xcode 26.4 with command-line tools (Swift 6.3)
- A PS5 DualSense or Xbox controller connected via USB or Bluetooth
- Accessibility permission (to send key events to WoW)
- World of Warcraft (Retail or Classic) with GSE installed

## Installation

> **No pre-built binary is available.** The app is unsandboxed and can't be signed for general distribution, so you must build from source. Xcode 26.4 and macOS 26 are required.

```bash
git clone https://github.com/jcll/GSEController.git
cd GSEController
./install.sh
```

`install.sh` builds a Release binary and copies it to `/Applications/GSEController.app`.

Before **Start** becomes available, grant Accessibility access in two steps:
- Step 1: the helper binary that actually posts key events
- Step 2: `GSEController.app` itself so it can receive controller input in the background

## Setup guide

### In GSEController

1. Launch GSEController and connect your controller
2. Click **+** and pick a profile template for your role, or start blank
3. For each binding, set the button, fire mode, and key to match your GSE macro keybind
4. Add notes for the macro/keybind setup if you want that context saved with the profile
5. Set the fire rate — **250 ms** is the conservative default, and **100 ms** is available for faster sequences. If your GSE macro has a custom `ms` setting, match that value.
6. Click **Save**, then click **Start**

### In WoW

1. Create or import a GSE macro for your spec (Wago.io has many ready-to-use sequences)
2. Drag the macro to an action bar slot
3. Keybind that slot to the same key you configured in GSEController
4. Test the keybind manually in WoW before relying on GSEController

### Profile templates

All templates default to key **K** — change it to match your actual GSE keybind after selecting.

| Template | R1 | R2 | D↓ (Alt) | D← (Shift) | D→ (Ctrl) |
|---|---|---|---|---|---|
| Guardian Druid | Rapid 250ms | Rapid 250ms | Frenzied Regen | Incapacitating Roar | Rebirth |
| Generic Tank | Rapid 250ms | Rapid 250ms | Defensive CD | CC / Utility | Taunt / Off-GCD |
| Melee DPS | Rapid 250ms | Rapid 250ms | Defensive CD | Interrupt | Major DPS CD |
| Ranged / Caster | Rapid 250ms | Rapid 100ms | Defensive CD | Interrupt / Kick | Major DPS CD |
| Healer | Rapid 250ms | — | Major CD | Dispel / Utility | Raid CD |
| Simple — R1 Only | Rapid 250ms | — | — | — | — |

D-pad buttons use Modifier Hold mode in all templates — holding the button sends that modifier key to WoW. Any button can use any fire mode; D-pad for modifiers is just a convention.

### ConsolePort users

If you use ConsolePort alongside this app:
- Unbind the trigger button in ConsolePort so it doesn't double-fire
- Or use L3/R3 as your trigger — ConsolePort rarely binds those by default
- D-pad directions used for Modifier mode will also fire as native WoW gamepad inputs — unbind them in ConsolePort, or accept the double-fire
- If you run ConsolePort's **Enhanced Gamepad** mode, it may intercept all controller input before GSEController sees it. You'll need to disable Enhanced Gamepad mode or assign non-overlapping buttons to each app

## Blizzard ToS

GSEController requires you to physically hold a button to fire — it does not play the game for you. It sends keypresses at a fixed rate on your behalf, which is functionally similar to keyboard hardware key repeat. GSE itself is an approved addon.

That said, Blizzard's policies can change and this app is not officially endorsed. Use it at your own discretion.

## How it works

The app uses Apple's GameController framework to read controller input. Key events are sent via a small helper binary (`KeyHelper`) that is compiled from source at runtime — this allows it to hold the Accessibility permission separately from the main app process.

When no controller is connected, the helper stays running in the background but is dormant — it only forwards key events when the main app sends them, which only happens in response to button input.

## Security model

GSEController has an unusual architecture that security-conscious users should understand before installing:

- **No sandbox:** The app runs without the macOS app sandbox. This is required to compile and launch the KeyHelper binary at runtime. It means the app has unrestricted filesystem and process access under your user account.

- **Runtime C compilation:** On first launch, the app compiles a small C program (`KeyHelper`) using `/usr/bin/cc` and stores the binary at `~/Library/Application Support/GSEController/keyhelper`. The source is embedded in `KeySimulator.swift` — you can audit it before building.

- **Persistent launchd agent:** The helper is registered as a launchd user agent derived from your bundle identifier, for example `com.example.GSEController.helper` with the default local config. It starts at login and stays running in the background. It receives key events from the main app via a FIFO and posts them via `CGEventPost`. When no controller is connected and the main app is not running, it is dormant.

- **Accessibility permission:** The helper binary holds the permission used to post keystrokes, and the app itself needs Accessibility access so it can keep receiving controller input while other apps are focused.

If you have concerns about any of this, you can review the full source at [github.com/jcll/GSEController](https://github.com/jcll/GSEController) before building.

### Uninstalling

To fully remove GSEController:

```bash
# Unload and remove the launchd agent
APP_BUNDLE_ID="$(defaults read /Applications/GSEController.app/Contents/Info CFBundleIdentifier 2>/dev/null || echo com.example.GSEController)"
HELPER_LABEL="${APP_BUNDLE_ID}.helper"
launchctl bootout gui/$(id -u) "$HOME/Library/LaunchAgents/$HELPER_LABEL.plist"
rm "$HOME/Library/LaunchAgents/$HELPER_LABEL.plist"

# Remove the app and support files
rm -rf /Applications/GSEController.app
rm -rf ~/Library/Application\ Support/GSEController
rm -rf ~/Library/Logs/GSEController
```

## Development

### Architecture

The codebase is split into a small set of layers with deliberately different jobs:

- `AppModel.swift` coordinates app-level actions such as import/export, alerts, and stop-before-mutate flows.
- `ProfileStore.swift` owns persistence, migrations, and profile import/export semantics.
- `ControllerManager.swift` bridges GameController input, helper readiness, Accessibility state, WoW focus tracking, and battery reporting.
- `FireEngine.swift` owns repeat timers, modifier reference counts, and the final "can input leave the app?" gating rules.
- `KeySimulator.swift` handles helper compilation, launchd registration, FIFO transport, and helper-specific Accessibility checks.
- `KeyInjection.swift` is the seam that keeps the runtime testable without talking to the real helper.
- `ContentView.swift`, `GroupEditorCard.swift`, `BindingRow.swift`, `ControllerMapView.swift`, and `NewGroupSheet.swift` make up the editable UI surface.
- `EnhancedGlassModifier.swift` is a local visual polish layer for Tahoe glass depth and tint behavior.
- `GSEControllerTests` covers pure logic and controller/runtime state without a live helper.
- `GSEControllerUITests` contains the opt-in UI smoke flows.

### Building manually

```bash
[ -f LocalConfig.xcconfig ] || cp LocalConfig.xcconfig.template LocalConfig.xcconfig
xcodebuild -project GSEController.xcodeproj -scheme GSEController -destination 'platform=macOS' build
```

### Running tests

```bash
[ -f LocalConfig.xcconfig ] || cp LocalConfig.xcconfig.template LocalConfig.xcconfig
xcodebuild test -project GSEController.xcodeproj -scheme GSEController -destination 'platform=macOS,arch=arm64'
```

The default shared scheme runs the non-UI suite only. It covers the model, controller/runtime, persistence/import, helper transport, and battery logic paths. CI also enables a small real-helper smoke check inside that suite so helper compilation, launch-agent registration, and FIFO setup do not rely entirely on manual verification.

UI smoke tests are intentionally separate so they only run when you explicitly ask for them locally, or when CI sees meaningful UI-facing changes:

```bash
[ -f LocalConfig.xcconfig ] || cp LocalConfig.xcconfig.template LocalConfig.xcconfig
xcodebuild test -project GSEController.xcodeproj -scheme GSEControllerUISmoke -destination 'platform=macOS,arch=arm64'
```

The UI smoke scheme covers profile creation/start, unsaved-edit protection, and numeric rate entry. It launches the app with `--uitesting`, which swaps the real helper bridge for `UITestKeyInjector` so the XCUI lane never depends on the live FIFO helper or local Accessibility grants.

### Repository Guide

- `install.sh` is the supported build-and-install entry point for local source installs.
- `make_icon.swift` regenerates the macOS app icon set from code so the committed icon assets stay reproducible.
- `.github/workflows/build.yml` is the default CI lane.
- `.github/workflows/ui-smoke.yml` is the path-gated UI smoke lane.

## License

MIT — see [LICENSE](LICENSE)

See [CHANGELOG.md](CHANGELOG.md) for version history.
