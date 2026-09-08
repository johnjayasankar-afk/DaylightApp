/*
 * Daylight — the app's schedule engine, in the browser.
 *
 * This is a port of Sources/DaylightCore: the same colour-temperature maths,
 * the same NOAA solar calculation, and the same schedule resolution. The
 * preset and city data beside it are generated from the app itself, so the
 * curve on this page is what the app would actually do rather than a drawing
 * of roughly that.
 *
 * Values here are checked against the Swift engine — see IMPROVEMENTS.md.
 */
(() => {
  'use strict';

  const C = window.DAYLIGHT_DATA.constants;
  const DAY = 24 * 60;

  // ------------------------------------------------------------- colour

  const mired = (k) => 1e6 / k;
  const fromMired = (m) => 1e6 / m;

  /* Interpolation happens in mired because equal steps in kelvin are nothing
     like equal steps to the eye: 2000→3000 K is a large visible change and
     8000→9000 K is nearly invisible. */
  function lerpKelvin(a, b, t) {
    const c = Math.min(Math.max(t, 0), 1);
    return fromMired(mired(a) + (mired(b) - mired(a)) * c);
  }

  /* CCT → CIE 1931 xy, Kim et al. (2002) cubic-spline fit of the Planckian
     locus. Valid 1667–25000 K. */
  function planckianXY(kelvin) {
    const t = Math.min(Math.max(kelvin, 1667), 25000);
    const i = 1 / t, i2 = i * i, i3 = i2 * i;
    const x = t <= 4000
      ? (-0.2661239e9 * i3 - 0.2343589e6 * i2 + 0.8776956e3 * i + 0.179910)
      : (-3.0258469e9 * i3 + 2.1070379e6 * i2 + 0.2226347e3 * i + 0.240390);
    const x2 = x * x, x3 = x2 * x;
    let y;
    if (t <= 2222)      y = -1.1063814 * x3 - 1.34811020 * x2 + 2.18555832 * x - 0.20219683;
    else if (t <= 4000) y = -0.9549476 * x3 - 1.37418593 * x2 + 2.09137015 * x - 0.16748867;
    else                y =  3.0817580 * x3 - 5.87338670 * x2 + 3.75112997 * x - 0.37001483;
    return { x, y };
  }

  function linearRGB(kelvin) {
    const { x, y } = planckianXY(kelvin);
    if (y < 1e-9) return [1, 1, 1];
    const X = x / y, Y = 1, Z = (1 - x - y) / y;
    return [
       3.2404542 * X - 1.5371385 * Y - 0.4985314 * Z,
      -0.9692660 * X + 1.8760108 * Y + 0.0415560 * Z,
       0.0556434 * X - 0.2040259 * Y + 1.0572252 * Z,
    ];
  }

  /* Per-channel gains, normalised so neutral is exactly (1,1,1) and no channel
     ever exceeds 1 — gains above 1 would clip against the panel's white point.
     These are the numbers the app actually writes to the display. */
  function channelGains(kelvin) {
    const c = linearRGB(kelvin), w = linearRGB(C.neutralKelvin);
    const v = [Math.max(c[0] / w[0], 0), Math.max(c[1] / w[1], 0), Math.max(c[2] / w[2], 0)];
    const m = Math.max(...v);
    return m > 0 ? v.map((n) => n / m) : v;
  }

  /* The cool-to-warm scale used for the timeline. A literal 6500 K swatch is
     white and disappears against the page, so the range is mapped onto
     something visible. It shows relative warmth, not emitted light. */
  function swatch(kelvin) {
    const f = Math.min(Math.max((C.neutralKelvin - kelvin) / (C.neutralKelvin - C.warmestKelvin), 0), 1);
    const cool = [158, 189, 224], warm = [240, 140, 61];
    return cool.map((c, i) => Math.round(c + (warm[i] - c) * f));
  }

  // -------------------------------------------------------------- solar

  /* NOAA solar position. Returns minutes from local midnight, or a marker when
     the event genuinely does not happen — the sun really does stay up, or
     down, for whole days at high latitude, and pretending otherwise would put
     a sunset in the schedule that never arrives. */
  const POLAR_DAY = 'polar-day', POLAR_NIGHT = 'polar-night';

  function julianDay(year, month, day) {
    let y = year, m = month;
    if (m <= 2) { y -= 1; m += 12; }
    const a = Math.floor(y / 100);
    const b = 2 - a + Math.floor(a / 4);
    return Math.floor(365.25 * (y + 4716)) + Math.floor(30.6001 * (m + 1)) + day + b - 1524.5;
  }

  function solarTerms(t) {
    const geomMeanLong = ((280.46646 + t * (36000.76983 + t * 0.0003032)) % 360 + 360) % 360;
    const geomMeanAnom = 357.52911 + t * (35999.05029 - 0.0001537 * t);
    const eccent = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);
    const mRad = geomMeanAnom * Math.PI / 180;
    const centre = Math.sin(mRad) * (1.914602 - t * (0.004817 + 0.000014 * t))
                 + Math.sin(2 * mRad) * (0.019993 - 0.000101 * t)
                 + Math.sin(3 * mRad) * 0.000289;
    const trueLong = geomMeanLong + centre;
    const omega = 125.04 - 1934.136 * t;
    const appLong = trueLong - 0.00569 - 0.00478 * Math.sin(omega * Math.PI / 180);
    const seconds = 21.448 - t * (46.8150 + t * (0.00059 - t * 0.001813));
    const meanObliq = 23 + (26 + seconds / 60) / 60;
    const obliqCorr = meanObliq + 0.00256 * Math.cos(omega * Math.PI / 180);
    const declination = Math.asin(Math.sin(obliqCorr * Math.PI / 180)
                                * Math.sin(appLong * Math.PI / 180)) * 180 / Math.PI;
    const vy = Math.pow(Math.tan(obliqCorr * Math.PI / 360), 2);
    const l0 = geomMeanLong * Math.PI / 180;
    const eqTime = 4 * (vy * Math.sin(2 * l0)
                 - 2 * eccent * Math.sin(mRad)
                 + 4 * eccent * vy * Math.sin(mRad) * Math.cos(2 * l0)
                 - 0.5 * vy * vy * Math.sin(4 * l0)
                 - 1.25 * eccent * eccent * Math.sin(2 * mRad)) * 180 / Math.PI;
    return { declination, eqTime };
  }

  /* `offsetMinutes` is the zone's own UTC offset on that date, passed in so the
     result lands on the clock the schedule runs on. */
  function solarEvent(kind, { year, month, day, lat, lon, offsetMinutes }) {
    if (!(lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180)) return POLAR_NIGHT;
    const morning = kind === 'sunrise';
    const zenith = 90.833; // includes refraction and the sun's radius
    const t0 = (julianDay(year, month, day) - 2451545) / 36525;

    let { declination, eqTime } = solarTerms(t0);
    let hourAngle = NaN;
    for (let pass = 0; pass < 2; pass++) {
      const latRad = lat * Math.PI / 180, decRad = declination * Math.PI / 180;
      const cosH = (Math.cos(zenith * Math.PI / 180) - Math.sin(latRad) * Math.sin(decRad))
                 / (Math.cos(latRad) * Math.cos(decRad));
      if (cosH > 1) return POLAR_NIGHT;
      if (cosH < -1) return POLAR_DAY;
      hourAngle = Math.acos(cosH) * 180 / Math.PI;
      const signed = morning ? hourAngle : -hourAngle;
      const minutesUTC = 720 - 4 * (lon + signed) - eqTime;
      ({ declination, eqTime } = solarTerms(t0 + (minutesUTC / 1440) / 36525));
    }
    if (!isFinite(hourAngle)) return POLAR_NIGHT;

    const signed = morning ? hourAngle : -hourAngle;
    let minutes = 720 - 4 * (lon + signed) - eqTime + offsetMinutes;
    while (minutes < 0) minutes += DAY;
    while (minutes >= DAY) minutes -= DAY;
    return minutes;
  }

  /* A zone's UTC offset on a given date, taken from the browser's own time-zone
     database so daylight saving is handled by it rather than by us. */
  function zoneOffsetMinutes(timeZone, date) {
    try {
      const fmt = new Intl.DateTimeFormat('en-US', {
        timeZone, timeZoneName: 'longOffset',
        year: 'numeric', month: '2-digit', day: '2-digit',
      });
      const part = fmt.formatToParts(date).find((p) => p.type === 'timeZoneName');
      const m = part && part.value.match(/GMT([+-])(\d{1,2}):?(\d{2})?/);
      if (!m) return 0;
      const sign = m[1] === '-' ? -1 : 1;
      return sign * (parseInt(m[2], 10) * 60 + parseInt(m[3] || '0', 10));
    } catch { return 0; }
  }

  /* The calendar date in a given zone, so "today" means today where the city
     is rather than where the visitor is. */
  function dateInZone(timeZone, date) {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone, year: 'numeric', month: '2-digit', day: '2-digit',
    }).formatToParts(date);
    const get = (t) => parseInt(parts.find((p) => p.type === t).value, 10);
    return { year: get('year'), month: get('month'), day: get('day') };
  }

  // ----------------------------------------------------------- schedule

  const FALLBACK = { sunrise: 7 * 60, sunset: 19 * 60 };

  /* Resolves a preset's anchors to minutes for a given day and place.
     Solar anchors carry earliest/latest clamps, which is what keeps a
     sun-following schedule sensible in midwinter and midsummer without being
     re-tuned twice a year. */
  function resolveAnchors(preset, city, when = new Date()) {
    return preset.anchors.map((a) => {
      if (a.kind === 'clock') {
        return { ...a, minute: a.minute, origin: 'clock' };
      }
      if (!city) {
        const fallback = FALLBACK[a.event] ?? 12 * 60;
        return { ...a, minute: clamp(fallback, a), origin: 'no-location' };
      }
      const { year, month, day } = dateInZone(city.tz, when);
      const offsetMinutes = zoneOffsetMinutes(city.tz, when);
      const raw = solarEvent(a.event, { year, month, day, lat: city.lat, lon: city.lon, offsetMinutes });
      if (raw === POLAR_DAY || raw === POLAR_NIGHT) {
        return { ...a, minute: clamp(FALLBACK[a.event] ?? 12 * 60, a), origin: raw };
      }
      const shifted = raw + (a.offset || 0);
      if (a.earliest != null && shifted < a.earliest) return { ...a, minute: a.earliest, origin: 'clamped-early', solar: raw };
      if (a.latest != null && shifted > a.latest) return { ...a, minute: a.latest, origin: 'clamped-late', solar: raw };
      return { ...a, minute: shifted, origin: 'solar', solar: raw };
    }).sort((p, q) => p.minute - q.minute);
  }

  function clamp(minute, a) {
    let m = minute;
    if (a.earliest != null) m = Math.max(m, a.earliest);
    if (a.latest != null) m = Math.min(m, a.latest);
    return m;
  }

  /* A fade of length `fade` arrives *at* its anchor; between fades the previous
     anchor's values hold. The day is cyclic, so the anchor before the first is
     the last one, from yesterday. */
  function evaluate(anchors, minute) {
    if (!anchors.length) return { kelvin: C.neutralKelvin, brightness: 1, name: 'Neutral' };
    const m = ((minute % DAY) + DAY) % DAY;
    let nextIndex = anchors.findIndex((a) => a.minute > m);
    let wrapped = false;
    if (nextIndex === -1) { nextIndex = 0; wrapped = true; }
    const next = anchors[nextIndex];
    const prev = anchors[(nextIndex - 1 + anchors.length) % anchors.length];
    const nextAt = wrapped ? next.minute + DAY : next.minute;
    const rampStart = nextAt - next.fade;

    if (next.fade > 0 && m >= rampStart) {
      const p = Math.min(Math.max((m - rampStart) / next.fade, 0), 1);
      return {
        kelvin: lerpKelvin(prev.kelvin, next.kelvin, p),
        brightness: prev.brightness + (next.brightness - prev.brightness) * p,
        name: next.name,
        transitioning: true,
      };
    }
    return { kelvin: prev.kelvin, brightness: prev.brightness, name: prev.name, transitioning: false };
  }

  const clockString = (minute) => {
    const m = ((Math.round(minute) % DAY) + DAY) % DAY;
    return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
  };

  window.DaylightEngine = {
    DAY, POLAR_DAY, POLAR_NIGHT,
    mired, lerpKelvin, channelGains, swatch,
    solarEvent, zoneOffsetMinutes, dateInZone,
    resolveAnchors, evaluate, clockString,
    presets: window.DAYLIGHT_DATA.presets,
    cities: window.DAYLIGHT_DATA.cities,
    constants: C,
  };
})();
