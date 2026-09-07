# Compatibility matrix

| Configuration | Warmth | Hardware brightness | Status |
| --- | --- | --- | --- |
| macOS 14+ built-in display, Apple silicon (M1–M4) | Transfer table (`CGSetDisplayTransferByTable`) | IOKit and/or DisplayServices | Implemented; verify with `make probe` |
| macOS 14+ Intel built-in | Transfer table | IOKit | Implemented; not verified on this machine |
| External display, independent gamma | Transfer table | Usually software dimming only | Implemented for warmth |
| External display brightness via DDC/CI | — | — | Planned |
| Mirrored displays | Shared or primary-owned tables | Shared | Detected and labeled |
| HDR / Reference modes | Unknown | Unknown | Disclose as unverified |
| Screen capture / screenshots | Capture may omit the transform | — | Do not use screenshots as proof |
| Night Shift / True Tone running together | Possible conflict | — | Daylight does not disable system tools; it reports foreign table changes |
| DisplayLink / some docks | Often unsupported | Unsupported | Capability notes when enumeration fails |
| M5 Pro / Max on macOS 26+ | Public reports of silent no-op | Varies | Detected as a known-broken generation; still attempted and reported honestly |
| Windows | — | — | Planned; do not use `SetDeviceGammaRamp` as a universal solution |
| Linux X11 / Wayland | — | — | Planned; compositor-specific |

This machine during development: Apple M1 Max, macOS 27.0 (build 26A5425a), Swift 6.4, Command Line Tools only.

The agent environment could not enumerate displays (`CGGetActiveDisplayList` returned 0) and could not read `machdep.cpu.brand_string`. Treat in-agent hardware checks as **incomplete verification**. Run `make probe` locally.
