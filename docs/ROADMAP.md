# Roadmap and feature checklist

Status values: implemented, tested, experimental, blocked, planned.

## Release 1 — everyday utility

| Feature | Status | Notes |
| --- | --- | --- |
| Display warmth via transfer tables | implemented | Public Core Graphics API |
| Scheduling engine | tested | Deterministic tests, no hardware |
| Manual and automatic modes | implemented | |
| Daily schedule editing | implemented | Timeline + numeric editors |
| Weekday / weekend schedules | tested | Overnight handoff uses the day that just ended |
| Per-display settings | implemented | Independent where the backend allows |
| Linked display overrides | implemented | A manual override applies to the whole group |
| Menu bar controls | implemented | |
| Temporary overrides | implemented | 15m / 30m / 1h / next anchor / until resume; next-anchor follows live nextChange; slider holds are Manual |
| Safe preview and restore | implemented | Live preview is explicit |
| Persistent local settings | tested | |
| Sleep, wake, reconnect handling | implemented | Hardware recovery unverified in-agent |
| Onboarding | implemented | |
| Settings window | implemented | |
| Capability and error copy | implemented | |
| Installable .app | implemented | Unsigned |
| Hardware brightness | experimental | IOKit + DisplayServices fallback |
| Night Shift private API | blocked | Not used |

## Release 2 — advanced personalization

| Feature | Status |
| --- | --- |
| Richer weekday/weekend timeline editing | planned |
| Night-shift schedule templates | planned |
| Application-specific rules | planned |
| Workspace profiles beyond display-set matching | planned |
| Command search and global shortcuts | planned |
| Break reminders | planned |
| Local preference learning with approval | planned |
| Ambient-light adaptation | planned |
| Settings export / import polish | implemented |
| Remembered slider duration and display scope | implemented |
| Selected-display sliders and preview lock | implemented |
| Solar times follow the chosen comfort warmth | implemented |
| Pause locks sliders; Reduce Motion follows the system | implemented |
| Default and per-time transition lengths | implemented |
| Double-click the timeline to add a time | implemented |
| Warmth-tinted menu bar icon | implemented |
| Honest pause / restore captions | implemented |
| Display session re-key on identity change | implemented |
| Quit restores disconnected sessions | implemented |
| Failed writes retry instead of sticking | implemented |
| Setup live preview restores on stop | implemented |
| Import rejects sparse JSON | implemented |
| Restore still runs in simulation | implemented |
| Last display gone restores before simulating | implemented |
| Scoped Color Work | implemented |
| Idle displays restore | implemented |
| Display list beyond 16 | implemented |
| Restore native tables on sleep | implemented |
| Custom times keep the current routine | implemented |
| Solar uses the city’s time zone | implemented |
| Until-next-change follows live nextChange | implemented |
| Weekday editing on a weekend day | implemented |
| Scoped hold keys migrate with identity | implemented |
| Preview does not expire a hold | implemented |
| Honest Custom / Solar editors | implemented |
| Hold until resume has no schedule countdown | implemented |
| Approach and solar offsets apply to both schedules | implemented |
| Weekend-edit mode persists | implemented |
| Failed writes do not mark ownership as applying | implemented |
| Import restores weekend-edit mode | implemented |
| Native chrome stays untinted | implemented |
| Per-display chrome when excluded or idle | implemented |
| Resume is blocked during preview | implemented |
| Setup does not leave schedule undo | implemented |
| Preview follows the timeline’s day | implemented |
| Pause clears a hold | implemented |
| Scoped-hold chrome uses schedule on other displays | implemented |
| Linking retargets an active scoped hold | implemented |
| Unplugged displays restore before reconnect | implemented |
| Day preview locks schedule editing | implemented |
| Timeline and slider Esc cancel | implemented |
| Next-change copy stays live on refresh | implemented |
| Extreme-slider cancel restores the pre-drag hold | implemented |
| Live preview blocked while paused | implemented |

## Release 3 — lighting ecosystem

| Feature | Status |
| --- | --- |
| Desk and bias lights | planned |
| RGB devices | planned |
| Home automation | planned |
| Cross-device sync | planned |
| Advanced diagnostics | planned |

Later features will ship as complete vertical slices. The production UI does not show dead Lights or Rules pages.
