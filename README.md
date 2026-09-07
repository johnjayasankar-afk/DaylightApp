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
index.html      the page
styles.css      design tokens and layout, dark-first with a light scheme
app.js          the interactive day curve
vercel.json     security headers and cache policy
assets/         icon, screenshots
downloads/      the app build and the source archive
```

## The curve is not a mock-up

`app.js` contains a port of the app's own schedule evaluation and
colour-temperature maths, running the same "Balanced" preset the app ships
with. Values were diffed against the Swift engine across fifteen times of day,
including mid-fade points, and match exactly.

If the app's presets or interpolation change, `ANCHORS` and the colour helpers
in `app.js` need to change with them, or the page starts telling a story the
app no longer performs.

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
  across 100 text nodes, lowest ratio 6.34 dark and 5.10 light.
- No horizontal overflow at 320, 375, 390, 768, 1024 or 1440 px.
- One `h1`, no heading-level skips, every interactive element has an
  accessible name, every image has alt text.
- The curve has a text description, and the scrubber is a real
  `input[type=range]` with a live `aria-valuetext`, so it works from the
  keyboard and reads correctly in a screen reader.
- Section reveals are an enhancement: the hidden state is only applied once
  scripting has confirmed it can remove it again, with a timer and a
  `visibilitychange` handler as failsafes. A blocked or broken script leaves
  the page fully readable rather than blank.
- `prefers-reduced-motion` disables the reveals and smooth scrolling.

`vercel.json` sets a strict Content-Security-Policy with no `'unsafe-inline'`,
which is why there is no inline `<style>` or `<script>` anywhere in the markup.
