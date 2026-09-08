# Daylight — landing page

A static marketing and download page for [Daylight](https://github.com/), the
macOS adaptive display-lighting app.

No framework, no build step, no dependencies. Three files and some images.

## Deploy to Vercel

**From the dashboard:** create a new project, drag this folder in, and deploy.
There is nothing to configure — Vercel serves it as a static site.

**From the CLI:**

```bash
npm i -g vercel
vercel        # preview
vercel --prod # production
```

**From GitHub:** push this folder to a repository and import it in Vercel. If
it lives in a subdirectory of a larger repo, set *Root Directory* to that
subdirectory in the project settings.

Leave the build command and output directory empty. There is no build.

## What's here

```
index.html         the page
styles.css         design tokens and layout, dark-first with a light scheme
app.js             the demo: day curve, year ribbon, schedule editor, sharing
assets/policy.js   a port of the app's precedence resolver
vercel.json        security headers and cache policy
assets/engine.js   a port of the app's schedule engine
assets/export.js   builds a settings file the app can import
assets/data.js     generated — presets, cities, and a real settings template
assets/            icon, screenshots
downloads/         the app build and the source archive
```

## The demo is not a mock-up

`assets/engine.js` is a port of `Sources/DaylightCore`: the same
colour-temperature maths, the same NOAA solar calculation, the same schedule
resolution including the 15-minute anchor merge. `assets/data.js` is generated
by `Daylight --export-site-data`, so the presets and the 101 cities are the
app's own values rather than transcriptions.

Neither is trusted on faith. `Scripts/verify-site-engine.sh` runs both engines
over the same inputs and diffs them — currently 112 solar probes and 56
resolved-anchor days.

Regenerate the data with `Scripts/build-site-data.sh` after changing any preset
or the city list.

## The precedence ladder is the real one

The "It tells you what it is doing" section lets a visitor switch the app's six
control layers on and off and watch which one wins each control. That is
`assets/policy.js`, a port of `PrecedenceResolver` — the same fixed ladder, the
same rule that warmth and brightness are resolved separately, and the same
plain-language sentence.

`Scripts/verify-site-policy.sh` runs every one of the 64 layer combinations
through both implementations and diffs them, including a proposal that sets
brightness and no warmth, because per-control resolution is both the behaviour
the section claims and the one most likely to be lost in a port.

The layers and their order come from the app via `data.js`. The little schedules
and rules hung on them are examples — the resolver needs something to decide
between — and the copy beside the ladder says so.

## Editing a schedule

Steps can be opened and changed, added, removed and renamed, and the schedule
itself can be named — that name travels into the exported file and along a
shared link. A step's controls
are its time (or, for a sun-following step, its offset and the *never before* /
*never after* clamps), warmth, brightness and fade. Everything runs through the
same engine as the rest of the page, so the day curve, the year ribbon and the
warmth preview all move together.

Edits are stored per preset in `localStorage` under `daylight.schedule.v2`, so
switching preset and coming back does not lose them. Nothing is sent anywhere.

## Taking a schedule into the app

The result downloads as a real settings file. The app reads it through
Settings → Your settings → **Import…**.

A schedule can also be shared as a link. The whole thing is encoded into the
fragment, so no server is involved and nothing is stored: opening the link shows
that schedule, in whichever city the visitor is in. Everything arriving from a
link goes through the same clamping as everything else, and names are inserted
as text, never as markup.

The file's shape is not invented in JavaScript. `data.js` carries a
`settingsTemplate` that the app itself exported, and `assets/export.js` only
replaces values inside a copy of it. `Scripts/verify-site-export.sh` closes the
loop: it builds a file with the page's own exporter and feeds it to the app's
real importer via `Daylight --import-check <file>`, then checks that the values
asked for are the values read back — across five cases: a fixed-clock preset, a
sun-following one with its clamps, a schedule with a step added, one with steps
removed, and one the visitor has named.

Two things worth knowing, both stated on the page:

- **Importing replaces the whole settings file.** That is how the app's import
  works, not a limitation of the page. Export your settings first if you have
  any worth keeping.
- The downloaded file carries the four built-in schedules as well as the edited
  one, so importing does not cost you the presets.

## Updating the download

1. Build the app: `./Scripts/build-app.sh release` in the Daylight repo.
2. Zip the *verifiable* copy — on a synced folder (iCloud Drive, Dropbox) the
   one under `build/` cannot carry a valid signature:
   ```bash
   ditto -c -k --keepParent ~/Library/Caches/Daylight/Daylight.app \
     downloads/Daylight-1.0.0.zip
   ```
3. Update the version, size and SHA-256 in `index.html`:
   ```bash
   shasum -a 256 downloads/Daylight-1.0.0.zip
   ```

## Accessibility and browser support

Checked, not assumed:

- Every piece of text meets WCAG AA contrast in both colour schemes — measured
  across 349 text nodes with every schedule step expanded and every precedence
  layer on, lowest ratio 5.96 dark and 5.10 light. The ribbon's hour marks sit on the painted colour field
  rather than on a themed surface, so they are measured separately against
  sampled field pixels: worst 8.31:1.
- No horizontal overflow at 320, 375, 768, 1024 or 1280 px.
- One `h1`, no heading-level skips, every interactive element has an
  accessible name, every image has alt text.
- The curve has a text description, and every scrubber — day, year, and each
  control in the schedule editor — is a real `input[type=range]` with a live
  `aria-valuetext`, so they work from the keyboard and read correctly in a
  screen reader.
- Each schedule step is a `button` with `aria-expanded` and `aria-controls`
  over a labelled `role="group"` panel, so the editor is operable without a
  mouse. Touch targets grow under `(pointer: coarse)`.
- Adding or removing a step rebuilds the list, so focus is placed deliberately
  afterwards — into the new step's name field, or onto "Add a step" — and the
  change is announced in a polite live region.
- If `data.js` or `engine.js` fails to load, the demo says so and hides its own
  dead controls rather than leaving copy that promises a live chart; the same
  goes for `policy.js` and the ladder. If no script runs at all, the `no-js`
  class swaps the hero's "below is the real engine" line for one that says it
  did not load.
- Section reveals are an enhancement: the hidden state is only applied once
  scripting has confirmed it can remove it again, with a timer and a
  `visibilitychange` handler as failsafes. A blocked or broken script leaves
  the page fully readable rather than blank.
- `prefers-reduced-motion` disables the reveals and smooth scrolling.

`vercel.json` sets a strict Content-Security-Policy with no `'unsafe-inline'`,
which is why there is no inline `<style>` or `<script>` anywhere in the markup.
