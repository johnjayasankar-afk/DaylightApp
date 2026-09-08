/* Builds a Daylight settings file from an edited schedule.
 *
 * Kept free of the DOM so the same code runs in the page and in
 * Scripts/verify-site-export.sh, which feeds its output to the real app and
 * checks that `importData` accepts it. The file's shape is not invented here:
 * `settingsTemplate` in data.js is a genuine settings file exported by the
 * app, and this only replaces values inside a copy of it.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.DaylightExport = api;
}(typeof self !== 'undefined' ? self : this, function () {

  /* RFC 4122 v4, uppercase — the form Foundation's UUID decoder accepts.
     `random(n)` returns n random bytes. */
  function makeUUID(random) {
    const b = random(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('').toUpperCase();
    return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  }

  /**
   * @param template  the settings object emitted by the app
   * @param baseName  which stock schedule the edits are based on
   * @param anchors   the page's own anchor objects, edits already applied
   * @param city      optional {name, region, lat, lon, tz}
   * @param random    (n) => Uint8Array of n random bytes
   * @param title     optional name for the schedule; defaults to the base name
   */
  function buildSettingsFile(template, baseName, anchors, city, random, title) {
    if (!template) return null;
    const out = JSON.parse(JSON.stringify(template));
    const source = out.schedules.find((s) => s.name === baseName);
    if (!source) return null;

    /* Steps can be added and removed on the page, so the exported list is built
       from what the page has rather than by walking the template's own steps —
       doing that silently dropped extras and kept ones already deleted.
       Template anchors are still the source of the *shape*: one of each kind is
       borrowed and its values replaced. */
    const prototypes = { clock: null, solar: null };
    for (const schedule of out.schedules) {
      for (const anchor of schedule.weekdayAnchors || []) {
        if (anchor.time && anchor.time.clock && !prototypes.clock) prototypes.clock = anchor;
        if (anchor.time && anchor.time.solar && !prototypes.solar) prototypes.solar = anchor;
      }
    }
    if (!prototypes.clock) return null;

    const mine = JSON.parse(JSON.stringify(source));
    mine.id = makeUUID(random);
    mine.name = (title && String(title).trim().slice(0, 60))
      || `${baseName} (edited on the web)`;

    mine.weekdayAnchors = anchors.map((def) => {
      const wantsSolar = def.kind === 'solar' && prototypes.solar;
      const anchor = JSON.parse(JSON.stringify(wantsSolar ? prototypes.solar : prototypes.clock));
      anchor.id = makeUUID(random);
      anchor.name = def.name;
      anchor.isEnabled = true;
      anchor.temperature.kelvin = def.kelvin;
      anchor.dimming.factor = def.brightness;
      anchor.transitionMinutes = def.fade;
      if (wantsSolar) {
        anchor.time.solar.event = def.event;
        anchor.time.solar.offsetMinutes = Math.round(def.offset || 0);
        if (def.earliest == null) delete anchor.time.solar.earliest;
        else anchor.time.solar.earliest = Math.round(def.earliest) * 60;
        if (def.latest == null) delete anchor.time.solar.latest;
        else anchor.time.solar.latest = Math.round(def.latest) * 60;
      } else {
        anchor.time = { clock: { secondsFromMidnight: Math.round(def.minute) * 60 } };
      }
      return anchor;
    });

    /* Only weekday steps are editable on the page. Leaving the weekend ones at
       the preset's values would quietly give a different evening on Saturday
       than the one just designed, so they are matched to it. */
    mine.weekendAnchors = mine.weekdayAnchors.map((a) => ({
      ...JSON.parse(JSON.stringify(a)), id: makeUUID(random),
    }));

    // Importing replaces everything, so the stock schedules travel too.
    out.schedules.push(mine);
    out.activeScheduleID = mine.id;
    if (city) {
      out.location = {
        latitude: city.lat, longitude: city.lon,
        label: `${city.name}, ${city.region}`,
        timeZoneIdentifier: city.tz,
      };
    }
    return out;
  }

  return { buildSettingsFile, makeUUID };
}));
