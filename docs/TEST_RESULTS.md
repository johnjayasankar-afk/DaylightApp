# Test results

## Automated

Run:

```bash
make test
# runs Sources/DaylightChecks — XCTest is unavailable with Command Line Tools only
```

Latest local run: **108 / 108 checks passed** (`DaylightChecks`).

Covered without hardware:

- Mired vs linear Kelvin interpolation
- Personal schedule hold and transition windows
- Midnight-crossing / night-shift schedules
- Weekend selection
- Late-night next change stays in the future
- Overnight weekday/weekend handoff (Saturday 1 AM keeps Friday night; Monday 1 AM keeps Sunday night)
- Spring-forward timeline samples stay on the calendar day
- Probable built-in display identity keeps the saved name
- Idle-but-online displays are distinct from disconnected
- Hybrid solar-vs-personal conflict window
- Missing location fallback
- Spring-forward date evaluation
- Wake recomputation (current state, not replay)
- Polar day and polar night fallbacks with resolvable clock times
- Rule precedence: emergency > pause > override > schedule
- Settings round-trip, invalid import, malformed JSON
- Display identity matching
- Transition write suppression
- Simulation adapter (no hardware writes)
- Timeline snapping
- Per-display override targeting
- Warmth comfort phrases
- Clock times built from date components
- Overnight wrap uses calendar days, not a fixed 86,400 seconds
- Spring-forward gap still resolves a time
- Per-display write clocks are independent
- Linked displays share override targeting
- Partial settings files keep defaults for new fields
- An empty weekend schedule is migrated back to usable times
- Unreadable settings files are copied aside instead of silently replaced
- Weekend editing is previewed on Saturday
- City typeahead applies only an unambiguous match
- Clearing the city field does not snap to San Francisco
- Status and timeline times follow the locale (12-hour or 24-hour)
- Activity history is stored newest first and yesterday uses a relative stamp
- The last selected window tab is restored from settings
- Activity history creates its folder if settings have not been saved yet
- A probable built-in rematch migrates the durable key, link group, and last selected display
- Hardware brightness is applied during a transition as soon as the target includes it
- Expired pauses and overrides are pruned instead of lingering in the UI
- An indefinite pause is kept
- A second custom time is placed on a free clock slot
- Setup does not write hardware unless the user starts a live preview
- Reset to defaults keeps the Mac onboarded so the new schedule can apply
- Importing a settings file marks the Mac onboarded
- Slider duration and “only this display” persist
- Linking ignores idle and mirrored displays
- Per-display captions distinguish a scoped hold from the schedule
- Idle, excluded, disabled, and previewing displays do not accept slider writes
- Compact remaining-time labels stay short enough for buttons
- A solar schedule uses wake and wind-down warmth instead of a fixed Balanced preset
- Pause, preview, and off block slider writes
- Lifecycle wake/display events are not written to activity history
- Solar offsets add calendar minutes, including across spring-forward
- The default transition slider updates existing wake, wind-down, and custom times
- Clock labels are formatted on a date that always exists, so 2:30 AM does not jump on DST days
- A single time can keep its own transition after the default length changes
- Pause and restore do not claim a live warmth target
- Paused status copy says native output
- Solar sunrise and sunset marks are not movable on the timeline
- Restored per-display captions stay honest
- A first hardware write is retried when nothing has been applied yet
- Sparse JSON is not treated as a Daylight settings export
- A complete export still imports
- Ending a live preview during setup restores tables instead of applying the schedule
- Simulation restore still visits remembered sessions
- Native presentation Kelvin is the daylight reference
- Scoped Color Work leaves other displays on the schedule
- Day preview reaches the next midnight
- Display list buffer grows when the first page is full
- An unrecognized city stays unmatched
- A custom time keeps the personal routine
- A solar schedule still uses a custom time
- Removing the last custom time restores a personal approach
- A city carries its own time zone
- Until-next-change follows a later schedule edit
- Until-next-change with no upcoming change becomes a hold
- Until-next-change that already passed expires
- A slider hold is labeled Manual
- Weekend weekday-editing maps onto Friday
- Sunday weekday-editing maps onto Monday
- Identity migration remaps a scoped hold
- A slider hold wins as Manual
- A hold until resume has no schedule countdown
- Approach and solar offsets apply to both schedules
- Weekend edit is remembered on a weekday
- Weekend edit defaults to the calendar day when never set
- Display cycling wraps backward
- Living surfaces keep Saturday on a weekend
- Schedule editing maps Saturday onto Friday
- Linking expands a scoped hold onto the group
- Unlinking shrinks a scoped hold to the selection
- Removed display keys skip remapped identities
- Timeline warmth uses the visible temperature range
- Live hardware preview is blocked while paused

## Hardware

| Check | Result |
| --- | --- |
| Enumerate displays in this agent environment | Failed (0 displays) |
| Apply 4200 K and observe readback | Not run with a visible panel from the agent |
| Visual warmth change | Unverified |
| Pause / resume / quit restore | Code path implemented; hardware unverified |
| Sleep / wake | Code path implemented; hardware unverified |
| Dock / undock | Code path implemented; hardware unverified |

Do not treat a screenshot as proof of a physical transform.

## Interface

Review locally in light mode, dark mode, a narrow window, and with Reduce Motion enabled. The agent did not drive the packaged app’s real menu bar on this host.
