# GSEController

A macOS menu bar app that turns your PS5 (or Xbox) controller into a rapid-fire keyboard macro trigger for World of Warcraft — designed for use with [GSE (GnomeSequencer Enhanced)](https://www.curseforge.com/wow/addons/gnome-sequencer-enhanced).

Hold a button → the app spams your macro key at a configurable rate. D-pad buttons can hold modifier keys (Alt/Shift/Ctrl) to activate modifier blocks inside your GSE rotation.

## Features

- **Multiple profiles** — one per class/spec, switch from the toolbar
- **Per-button configuration** — assign any controller button to any key
- **Three fire modes:**
  - **Rapid** — spams the key while held (for GSE rotation macros)
  - **Tap** — fires once per press (for manual cooldowns)
  - **Modifier** — holds Alt/Shift/Ctrl while pressed (activates GSE modifier blocks)
- **Configurable rate** — 6/10/15/20 presses per second, or custom
- **Controller map** — visual overview of all your bindings at a glance
- **WoW focus guard** — optionally only fires when WoW is the active window
- **Profile templates** — pre-built setups for Guardian Druid, Tank, Melee DPS, Ranged/Caster, Healer

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 16+ (to build)
- A PS5 DualSense or Xbox controller connected via USB or Bluetooth
- Accessibility permission (to send key events to WoW)

## Installation

```bash
git clone https://github.com/jcll/GSEController.git
cd GSEController
./install.sh
```

`install.sh` builds a Release binary and copies it to `/Applications/GSEController.app`.

On first launch, macOS will ask for Accessibility permission — this is required for the app to send keystrokes to WoW.

## Building manually

```bash
xcodebuild -scheme GSEController -destination 'platform=macOS' build
```

## Setup guide

1. Launch GSEController and connect your controller
2. Click **+** and pick a profile template (or start blank)
3. For each binding, set the button, mode, and key to match your GSE macro keybind
4. Click **Save**, then click **Start**
5. In WoW, make sure the key you configured is bound to your GSE macro

### ConsolePort users

If you use ConsolePort alongside this app:
- Unbind the trigger button in ConsolePort so it doesn't double-fire
- Or use L3/R3 as your trigger — ConsolePort rarely binds those by default
- D-pad directions used for Modifier mode will also fire as native WoW gamepad inputs — unbind them in ConsolePort, or accept the double-fire

## How it works

The app uses Apple's GameController framework to read controller input. Key events are sent via a small helper binary (`KeyHelper`) that is compiled from source at runtime — this allows it to hold the Accessibility permission separately from the sandboxed main app.

## License

MIT — see [LICENSE](LICENSE)
