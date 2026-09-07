# Architecture

Daylight keeps scheduling independent of display hardware.

```
Inputs → schedule + rules → desired state → safety limits
      → transition coordinator → device adapter → reported result
```

The user interface never writes hardware itself.

## Modules

| Module | Responsibility |
| --- | --- |
| `DaylightCore` | Branding, models, solar math, schedule engine, rules, transitions, persistence |
| `DaylightMac` | Display enumeration, transfer-table warmth, brightness backends, lifecycle |
| `DaylightApp` | AppKit menu bar, windows, and onboarding (Command Line Tools on this machine do not ship SwiftUI macros) |
| `DaylightProbe` | Hardware capability probe and restore tool |

## Core concepts

- **Display identity** — UUID when available, then vendor/model/serial, then built-in fallback. A rematch migrates saved names, exclusions, link keys, and scoped hold keys onto the live key.
- **Display sessions** — baselines stay across dock/undock so reconnect cannot stack warmth on a newly captured table. When a display’s durable key changes (EDID → UUID), the captured session is re-keyed instead of capturing the already-warm table. A display that leaves the live set is restored to its captured baseline before the session is kept for reconnect. Identity remaps are not treated as removals.
- **Capability set** — warmth and brightness independently
- **Schedule / anchors** — clock or solar-relative. The default transition slider writes every personal and custom time; Schedule can still set one time’s length. Clock labels are formatted on a date that always exists, so 2:30 AM does not jump on DST days. Timeline drags preview in memory and persist on mouse-up; Esc restores a drag or a keyboard nudge. The curve’s vertical scale matches the warmth range in Settings. Default transitions stay locked during a day preview.
- **Desired vs applied output** — requested values versus adapter results
- **Baseline / ownership** — the table captured before Daylight writes; later writes are always relative to that baseline, never stacked
- **Temporary override** — mode or slider change with an expiration. Changing “Keep for” updates the active hold. Changing “only this display” retargets the active hold. “Until the next schedule change” follows the live nextChange — moving Wake updates it; a past nextChange ends the hold; no upcoming change becomes a hold until resume. A hold until resume does not count down to the next schedule time. Slider holds are labeled Manual, not Focus. Sliders follow the selected display’s real target, not a global Kelvin. Pause, Restore, and Color Work restore native tables and the UI says so — it does not show a schedule Kelvin that is not on the panel. Expired pauses and overrides are pruned on the real clock, never on a preview playhead. A day preview does not expire or rewrite the user’s hold. A day preview locks lighting controls so a slider cannot hijack the sweep. Settings edits persist even during a preview.
- **Locale times** — status, history, and timeline hours follow the Mac’s 12-hour or 24-hour setting. Preview clocks use the playhead, not the wall clock.
- **Native chrome** — when Daylight is not holding a target (pause, restore, Color Work, off, excluded, idle), warmth washes, badges, and the menu-bar sun stay neutral instead of tinting at 6500 K. Headlines and Kelvin labels follow the selected display, not a global schedule that is not on that panel. Linking or unlinking retargets an active scoped hold so the group and the hardware stay aligned.
- **Simulation adapter** — injectable, clearly labeled, never counted as hardware support

## Hybrid schedule resolution

1. Resolve personal, solar, and custom anchors for yesterday, today, and tomorrow. Each day uses that day’s weekday or weekend schedule, so Saturday 1 AM still holds Friday night. Solar sunrise and sunset use that schedule’s wake and wind-down warmth, so a comfort preset applies to a solar day. Solar offsets add calendar minutes so spring-forward and fall-back stay honest.
2. If a solar anchor falls within `hybridConflictWindowMinutes` (default 20) of a personal or custom anchor, suppress the solar anchor.
3. Sort remaining anchors and interpolate with mired (reciprocal-temperature) blending.
4. A transition finishes at the next anchor. If the gap is shorter than the configured duration, the full gap is used. “Next change” and “until the next schedule change” use that upcoming time, never a past wrap. Today and Preview follow the calendar day you are living. Schedule editing on a weekend day maps onto Friday or Monday so the canvas and the editors stay on the same day kind. Approach and sunrise/sunset offsets are one product choice and write to both weekday and weekend schedules; weekend editing is remembered across launches. A pause clears a hold so the schedule, not the hold, returns when the pause ends.

## Ownership and restore

1. On first write to a display, capture its current transfer table as the baseline.
2. Apply warmth and software dimming as a scale on that baseline.
3. On pause, Color Work, disable, preview cancel, or quit, write the baseline back (or ColorSync restore for emergency / crash recovery). Setup does not write hardware until the user finishes, unless they start an explicit live preview. Reset to defaults keeps the Mac onboarded so the replacement schedule can apply. Launch-at-login approval, crash-recovery, and save failures stay visible instead of being overwritten by the next write note.
4. If readback differs from the last table Daylight wrote, report a possible foreign change and do not adopt that table as a new baseline.
5. Quit and Restore visit every remembered session even if the app later entered simulation mode, then ColorSync. Failed writes do not advance the last-applied clock or mark the session as applying, so the next tick can retry and a crash recovery is not invented.
6. Ending a live preview during setup restores ColorSync tables. Import requires a weekday schedule object so a one-key JSON file cannot wipe settings.
7. If the last physical display disappears, Daylight restores native tables before switching to simulation. Importing a complete export while setup is open finishes setup and opens the main window.
8. Color Work scoped to one display restores only that display; others stay on the schedule. Idle displays are restored instead of left warm. Display enumeration grows past 16. Sleep can restore native tables (on by default) and wake reapplies the schedule. A lifecycle event cancels a live preview through the same cleanup path as Stop.
9. A custom time is added to the current approach. It does not replace wake, wind-down, or solar times. Removing the last custom time from a Custom approach returns to Personal. Solar events use the city’s time zone.

Crash recovery cannot be guaranteed by the operating system. On the next launch, if an ownership file says a transform was active, Daylight restores ColorSync tables and then applies the current schedule.

## Brightness

Hardware brightness and software dimming are separate controls.

- Hardware brightness uses IOKit when available, then an experimental DisplayServices fallback.
- Software dimming multiplies the transfer table. It is not backlight control and is not described as saving power.

## Future platforms

New operating systems should implement a `DisplayAdapter` and a lifecycle monitor. `DaylightCore` does not import AppKit or Core Graphics.
