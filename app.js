/*
 * Daylight — landing page behaviour.
 *
 * The curve on this page is not an illustration. It runs the same schedule
 * evaluation and the same colour maths the application does, over the same
 * "Balanced" preset the app ships with, so what you scrub through here is what
 * the app would actually do.
 *
 * No dependencies, no build step.
 */
(() => {
  'use strict';

  // Scripting is available, so anything hidden for its absence can come back.
  document.documentElement.classList.remove('no-js');

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---------------------------------------------------------------------
  // Colour temperature
  //
  // Ported from Sources/DaylightCore/Lighting.swift so the page and the app
  // cannot drift apart. Interpolation happens in mired (10^6 / K) because
  // equal steps in kelvin are nothing like equal steps to the eye.
  // ---------------------------------------------------------------------

  const NEUTRAL_K = 6500;
  const WARMEST_K = 1900;
  const mired = (k) => 1e6 / k;
  const fromMired = (m) => 1e6 / m;

  function lerpTemperature(a, b, t) {
    const clamped = Math.min(Math.max(t, 0), 1);
    return fromMired(mired(a) + (mired(b) - mired(a)) * clamped);
  }

  /* The cool-to-warm scale the app's timeline uses. A literal 6500 K swatch is
     white, which vanishes against the page, so the same range is mapped onto a
     scale that stays visible. It shows relative warmth; it is not a rendering
     of emitted light. */
  function swatch(kelvin) {
    const f = Math.min(Math.max((NEUTRAL_K - kelvin) / (NEUTRAL_K - WARMEST_K), 0), 1);
    const cool = [158, 189, 224];
    const warm = [240, 140, 61];
    return cool.map((c, i) => Math.round(c + (warm[i] - c) * f));
  }

  const rgb = (c, alpha) => `rgba(${c[0]}, ${c[1]}, ${c[2]}, ${alpha})`;

  // ---------------------------------------------------------------------
  // The schedule — the app's "Balanced" preset, values unchanged
  // ---------------------------------------------------------------------

  const ANCHORS = [
    { name: 'Morning',   at: 7 * 60,        kelvin: 6500, brightness: 1.00, fade: 40 },
    { name: 'Day',       at: 9 * 60 + 30,   kelvin: 6500, brightness: 1.00, fade: 30 },
    { name: 'Evening',   at: 19 * 60,       kelvin: 4200, brightness: 0.95, fade: 90 },
    { name: 'Wind down', at: 21 * 60 + 30,  kelvin: 3200, brightness: 0.82, fade: 60 },
    { name: 'Night',     at: 23 * 60 + 30,  kelvin: 2800, brightness: 0.70, fade: 45 },
  ];

  const DAY = 24 * 60;

  /* Evaluates the schedule at a wall-clock minute, exactly as the app does:
     a fade of length `fade` arrives *at* its anchor, and between fades the
     previous anchor's values are held. The day is cyclic, so the anchor before
     the first one is the last one, from yesterday. */
  function evaluate(minute) {
    const m = ((minute % DAY) + DAY) % DAY;
    const sorted = [...ANCHORS].sort((a, b) => a.at - b.at);

    let next = sorted.find((a) => a.at > m);
    let nextWrapped = false;
    if (!next) { next = sorted[0]; nextWrapped = true; }

    const nextIndex = sorted.indexOf(next);
    const prev = sorted[(nextIndex - 1 + sorted.length) % sorted.length];

    const nextAt = nextWrapped ? next.at + DAY : next.at;
    const rampStart = nextAt - next.fade;

    if (next.fade > 0 && m >= rampStart) {
      const progress = Math.min(Math.max((m - rampStart) / next.fade, 0), 1);
      return {
        kelvin: lerpTemperature(prev.kelvin, next.kelvin, progress),
        brightness: prev.brightness + (next.brightness - prev.brightness) * progress,
        name: next.name,
        transitioning: true,
      };
    }
    // Before the first fade of the day, yesterday's last anchor still holds.
    if (m < rampStart && nextIndex === 0) {
      return { kelvin: prev.kelvin, brightness: prev.brightness, name: prev.name, transitioning: false };
    }
    return { kelvin: prev.kelvin, brightness: prev.brightness, name: prev.name, transitioning: false };
  }

  const clock = (minute) => {
    const m = ((Math.round(minute) % DAY) + DAY) % DAY;
    return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
  };

  // ---------------------------------------------------------------------
  // Drawing the curve
  // ---------------------------------------------------------------------

  const svg = document.getElementById('curve');
  if (!svg) return;

  const NS = 'http://www.w3.org/2000/svg';
  const W = 1000, H = 260, PAD_TOP = 18, PAD_BOTTOM = 34;
  const plotH = H - PAD_TOP - PAD_BOTTOM;

  const x = (minute) => (minute / DAY) * W;
  const y = (kelvin) => {
    const f = (mired(kelvin) - mired(NEUTRAL_K)) / (mired(WARMEST_K) - mired(NEUTRAL_K));
    return PAD_TOP + Math.min(Math.max(f, 0), 1) * plotH;
  };

  function build() {
    const step = 4; // minutes
    const samples = [];
    for (let m = 0; m <= DAY; m += step) samples.push({ m, ...evaluate(m) });

    // A gradient sampled from the curve itself, so the fill is the day's own
    // colour rather than a decorative wash.
    const defs = document.createElementNS(NS, 'defs');
    const grad = document.createElementNS(NS, 'linearGradient');
    grad.setAttribute('id', 'dayFill');
    grad.setAttribute('x1', '0'); grad.setAttribute('x2', '1');
    grad.setAttribute('y1', '0'); grad.setAttribute('y2', '0');
    for (let i = 0; i <= 48; i++) {
      const s = evaluate((i / 48) * DAY);
      const stop = document.createElementNS(NS, 'stop');
      stop.setAttribute('offset', `${(i / 48) * 100}%`);
      stop.setAttribute('stop-color', rgb(swatch(s.kelvin), 0.62));
      grad.appendChild(stop);
    }
    defs.appendChild(grad);
    svg.appendChild(defs);

    const area = document.createElementNS(NS, 'path');
    let d = `M 0 ${H - PAD_BOTTOM}`;
    samples.forEach((s) => { d += ` L ${x(s.m).toFixed(2)} ${y(s.kelvin).toFixed(2)}`; });
    d += ` L ${W} ${H - PAD_BOTTOM} Z`;
    area.setAttribute('d', d);
    area.setAttribute('fill', 'url(#dayFill)');
    svg.appendChild(area);

    const line = document.createElementNS(NS, 'path');
    let ld = '';
    samples.forEach((s, i) => {
      ld += `${i === 0 ? 'M' : 'L'} ${x(s.m).toFixed(2)} ${y(s.kelvin).toFixed(2)} `;
    });
    line.setAttribute('d', ld);
    line.setAttribute('class', 'curve-line');
    svg.appendChild(line);

    // Hour ticks, labelled every six.
    for (let h = 0; h <= 24; h += 3) {
      const tick = document.createElementNS(NS, 'line');
      tick.setAttribute('x1', x(h * 60)); tick.setAttribute('x2', x(h * 60));
      tick.setAttribute('y1', H - PAD_BOTTOM); tick.setAttribute('y2', H - PAD_BOTTOM + 5);
      tick.setAttribute('class', 'curve-tick');
      svg.appendChild(tick);
      if (h % 6 === 0 && h < 24) {
        const label = document.createElementNS(NS, 'text');
        label.setAttribute('x', x(h * 60) + 6);
        label.setAttribute('y', H - PAD_BOTTOM + 20);
        label.setAttribute('class', 'curve-label');
        label.textContent = h === 0 ? '12 AM' : h === 12 ? 'Noon' : h > 12 ? `${h - 12} PM` : `${h} AM`;
        svg.appendChild(label);
      }
    }

    // Anchor marks, so the shape is legible as a schedule rather than a blob.
    ANCHORS.forEach((a) => {
      const mark = document.createElementNS(NS, 'line');
      mark.setAttribute('x1', x(a.at)); mark.setAttribute('x2', x(a.at));
      mark.setAttribute('y1', PAD_TOP); mark.setAttribute('y2', H - PAD_BOTTOM);
      mark.setAttribute('class', 'curve-anchor');
      svg.appendChild(mark);
    });

    const marker = document.createElementNS(NS, 'line');
    marker.setAttribute('id', 'marker');
    marker.setAttribute('y1', PAD_TOP - 8); marker.setAttribute('y2', H - PAD_BOTTOM);
    marker.setAttribute('class', 'curve-marker');
    svg.appendChild(marker);

    const dot = document.createElementNS(NS, 'circle');
    dot.setAttribute('id', 'marker-dot');
    dot.setAttribute('r', '4');
    dot.setAttribute('class', 'curve-marker-dot');
    svg.appendChild(dot);
  }

  build();

  // ---------------------------------------------------------------------
  // Scrubbing
  // ---------------------------------------------------------------------

  const slider = document.getElementById('scrub');
  const readTime = document.getElementById('read-time');
  const readName = document.getElementById('read-name');
  const readKelvin = document.getElementById('read-kelvin');
  const readBright = document.getElementById('read-brightness');
  const nowButton = document.getElementById('scrub-now');
  const marker = document.getElementById('marker');
  const dot = document.getElementById('marker-dot');
  const stage = document.querySelector('.hero-demo');

  const nowMinute = () => { const d = new Date(); return d.getHours() * 60 + d.getMinutes(); };
  let following = true;

  function paint(minute) {
    const s = evaluate(minute);
    const px = x(minute);

    marker.setAttribute('x1', px); marker.setAttribute('x2', px);
    dot.setAttribute('cx', px); dot.setAttribute('cy', y(s.kelvin));

    readTime.textContent = clock(minute);
    readName.textContent = s.name;
    readKelvin.textContent = `${Math.round(s.kelvin / 50) * 50} K`;
    readBright.textContent = `${Math.round(s.brightness * 100)}%`;

    /* The page takes on the colour of the moment being previewed. This is the
       demonstration: the same shift, on the thing you are looking at. */
    const c = swatch(s.kelvin);
    stage.style.setProperty('--moment', rgb(c, 1));
    stage.style.setProperty('--moment-soft', rgb(c, 0.13));
    stage.style.setProperty('--moment-faint', rgb(c, 0.05));

    slider.setAttribute('aria-valuetext',
      `${clock(minute)}, ${s.name}, about ${Math.round(s.kelvin / 50) * 50} kelvin, ${Math.round(s.brightness * 100)} percent brightness`);
  }

  function setMinute(minute, userDriven) {
    if (userDriven) {
      following = false;
      nowButton.hidden = false;
    }
    slider.value = String(Math.round(minute));
    paint(minute);
  }

  slider.addEventListener('input', () => setMinute(Number(slider.value), true));

  nowButton.addEventListener('click', () => {
    following = true;
    nowButton.hidden = true;
    setMinute(nowMinute(), false);
    slider.focus();
  });

  // Start where the visitor actually is in their own day.
  setMinute(nowMinute(), false);
  nowButton.hidden = true;

  // Keep following the clock until the visitor takes over.
  setInterval(() => { if (following) setMinute(nowMinute(), false); }, 30000);

  // ---------------------------------------------------------------------
  // Small niceties
  // ---------------------------------------------------------------------

  /* Reveal sections as they arrive.
   *
   * The hidden state is only switched on once we know we can switch it off
   * again, and a timer un-hides everything regardless after a moment. Content
   * that cannot be read is worse than content that does not animate. */
  const revealables = document.querySelectorAll('[data-reveal]');
  const showAll = () => revealables.forEach((el) => el.classList.add('is-visible'));

  if (!reduceMotion && 'IntersectionObserver' in window && revealables.length) {
    document.documentElement.classList.add('js-reveal');
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) { e.target.classList.add('is-visible'); io.unobserve(e.target); }
      });
    }, { rootMargin: '0px 0px -12% 0px' });
    revealables.forEach((el) => io.observe(el));
    // Failsafe: if anything is still hidden after three seconds — an observer
    // that never fires in an unusual embedding, say — show it anyway.
    setTimeout(showAll, 3000);
    // A backgrounded tab throttles both timers and the observer, so a tab
    // restored after a while would otherwise come back blank.
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) setTimeout(showAll, 400);
    });
  } else {
    showAll();
  }

  // Copy buttons for the terminal commands.
  document.querySelectorAll('[data-copy]').forEach((button) => {
    button.addEventListener('click', async () => {
      const text = document.getElementById(button.dataset.copy)?.textContent?.trim();
      if (!text) return;
      try {
        await navigator.clipboard.writeText(text);
        const previous = button.textContent;
        button.textContent = 'Copied';
        button.classList.add('is-done');
        setTimeout(() => { button.textContent = previous; button.classList.remove('is-done'); }, 1600);
      } catch {
        button.textContent = 'Press ⌘C';
      }
    });
  });

  // Only claim macOS where it is true.
  const isMac = /Mac|iPhone|iPad/.test(navigator.platform) ||
                /Mac OS X/.test(navigator.userAgent);
  if (!isMac) {
    document.querySelectorAll('[data-mac-only]').forEach((el) => { el.hidden = false; });
  }

  document.getElementById('year').textContent = String(new Date().getFullYear());
})();
