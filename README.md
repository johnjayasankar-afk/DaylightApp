# Daylight

Daylight is a macOS menu-bar utility that adjusts display warmth — and hardware brightness where the system allows — according to a schedule you control.

It is a lighting-comfort and routine-support tool. It does **not** treat eye strain, measure melatonin, know your circadian phase, or replace daylight, breaks, or medical care. Temperature values are approximate display targets, not spectral measurements.

> Adjust your display to your preferences. Use gentler evening settings. Build a consistent wind-down routine.

## Platform

Primary platform: **macOS 14+** on Apple silicon and Intel. This repository implements a native Swift / AppKit app. Scheduling logic is platform-independent so Windows or Linux adapters can be added later without rewriting the engine.

## Requirements

- macOS 14 or later
- Swift 6 command-line tools (`xcode-select --install` is enough; full Xcode is not required)
- No account, network service, or location permission for the core app

## Build and run

```bash
cd daylight
make test
make app
make run
```

Or step by step:

```bash
swift build --disable-sandbox --cache-path .build/spm-cache --product DaylightChecks
.build/debug/DaylightChecks
swift build --disable-sandbox --cache-path .build/spm-cache -c release --product Daylight
./Scripts/package-app.sh
open dist/Daylight.app
```

The packaged app lives at `dist/Daylight.app`. It is **not signed or notarized**. To keep Gatekeeper quiet for local use:

```bash
xattr -dr com.apple.quarantine dist/Daylight.app
```

To sign and notarize later, use your Developer ID certificate and `notarytool`. Those steps are not claimed as done here.

## Prove display control

This is the first thing to run on a new machine:

```bash
make probe
```

The probe:

1. Lists connected displays and their detected capabilities
2. Applies a conservative 4200 K transfer-table adjustment
3. Holds for a few seconds
4. Restores the previous table

It reports four evidence classes separately: requested state, API acceptance, readback, and visual confirmation. Visual confirmation is never inferred from an API result.

If you need to undo an adjustment immediately:

```bash
make restore
```

## Everyday use

1. Open Daylight from the menu bar sun icon.
2. Finish the short setup, or skip ahead — defaults are usable.
3. Edit the daily timeline on **Today** or **Schedule**. Drag a time to move it, double-click to add one, and hold Shift for one-minute precision. Settings can set how long every time takes to arrive; Schedule can still refine a single time.
4. Use **Reading**, **Focus**, **Wind Down**, or **Color Work** as temporary modes.
5. Close the window; automation continues if that preference is enabled.
6. **Restore** or **Quit** removes Daylight’s transfer-table adjustments.

A manual slider change is a temporary override with an expiration. It does not rewrite the saved schedule. Linking groups every active display so that override applies to all of them.

- Option-click the menu bar icon to restore output immediately.
- Settings can hide the menu-bar temperature if you want a quieter extra.
- Right-click the icon for Pause, Resume, Restore, and Quit.
- Emergency restore: **⌥⇧⌘R**.

## Scheduling

- **Personal** — wake, wind-down, bedtime, overnight
- **Solar** — sunrise and sunset from a typed city or coordinates (no location permission)
- **Custom** — named anchors
- **Hybrid** — solar events plus your routine. If a personal or custom time falls within 20 minutes of a solar event, the personal time is used and the solar event is skipped.

A separate weekend schedule uses that day’s times. Overnight still belongs to the day that just ended: Saturday 1 AM holds Friday’s weekday night until Saturday morning, and Monday 1 AM holds Sunday’s weekend night until Monday’s wake.

After sleep or wake, Daylight recomputes the current desired state. It does not replay missed transitions.

## What is implemented

See [docs/ROADMAP.md](docs/ROADMAP.md) for the precise checklist (implemented, tested, experimental, blocked, planned).

Release 1 includes warmth control, the scheduling engine, menu-bar controls, per-display settings, overrides, onboarding, and local persistence.

Not in this release: application rules, ambient-light sensors, desk/RGB lights, accounts, or analytics.

## Privacy

Settings live in `~/Library/Application Support/Daylight/`. There is no telemetry. History is off by default. Exports do not include integration secrets because none are stored.

## Uninstall

1. Quit Daylight (this restores its display adjustments).
2. Delete `Daylight.app`.
3. Optionally delete `~/Library/Application Support/Daylight`.
4. If you enabled launch at login, turn that off in Daylight first, or remove the login item in System Settings.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Compatibility](docs/COMPATIBILITY.md)
- [Test results](docs/TEST_RESULTS.md)
- [Release checklist](docs/RELEASE_CHECKLIST.md)
- [Roadmap](docs/ROADMAP.md)
