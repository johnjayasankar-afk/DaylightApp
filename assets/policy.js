/*
 * Daylight — the app's precedence resolver, in the browser.
 *
 * A port of PrecedenceResolver in Sources/DaylightCore/Policy.swift: the same
 * fixed ladder, the same rule that warmth and dimming are resolved separately,
 * and the same plain-language sentence. The page claims Daylight can always say
 * why your screen looks the way it does; running the real resolver is the only
 * honest way to show that rather than assert it.
 *
 * Checked against the Swift original by Scripts/verify-site-policy.sh.
 */
(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.DaylightPolicy = api;
}(typeof self !== 'undefined' ? self : this, function () {

  /* The ladder. Higher wins. Names come from the app via data.js where it is
     available, so they cannot drift; these are the fallback. */
  const LAYERS = [
    { key: 'baseSchedule', rank: 0, name: 'Schedule' },
    { key: 'workspaceProfile', rank: 1, name: 'Workspace' },
    { key: 'activityRule', rank: 2, name: 'App rule' },
    { key: 'manualOverride', rank: 3, name: 'Manual override' },
    { key: 'userPause', rank: 4, name: 'Paused' },
    { key: 'emergencyRestore', rank: 5, name: 'Restored' },
  ];

  const rankOf = (key) => {
    const found = LAYERS.find((l) => l.key === key);
    return found ? found.rank : 0;
  };

  function describeWarmth(kelvin) {
    if (kelvin < 2400) return 'very warm';
    if (kelvin < 3200) return 'warm';
    if (kelvin < 4300) return 'slightly warm';
    if (kelvin < 5600) return 'close to neutral';
    if (kelvin < 6400) return 'nearly neutral';
    return 'neutral';
  }

  /* Resolved per control: a proposal that only speaks about brightness must not
     silently discard another layer's warmth. */
  function resolve(proposals, neutralKelvin) {
    const ordered = proposals.slice().sort((a, b) => rankOf(b.layer) - rankOf(a.layer));
    const fallback = { layer: 'baseSchedule', label: 'Neutral' };

    let temperature = null, temperatureFrom = fallback;
    let dimming = null, dimmingFrom = fallback;

    for (const p of ordered) {
      if (temperature === null && p.target.kelvin != null) {
        temperature = p.target.kelvin;
        temperatureFrom = { layer: p.layer, label: p.label };
      }
      if (dimming === null && p.target.dimming != null) {
        dimming = p.target.dimming;
        dimmingFrom = { layer: p.layer, label: p.label };
      }
      if (temperature !== null && dimming !== null) break;
    }

    const dominant = ordered.length
      ? { layer: ordered[0].layer, label: ordered[0].label }
      : fallback;

    const target = {
      kelvin: temperature == null ? neutralKelvin : temperature,
      dimming: dimming == null ? 1 : dimming,
    };

    return {
      target,
      temperatureFrom,
      dimmingFrom,
      dominant,
      explanation: explain(target, temperatureFrom, dimmingFrom),
    };
  }

  /* The answer to "why does my screen look like this?". It has to read like a
     sentence a person would say, which is why it is prose and not a code. */
  function explain(target, temperatureFrom, dimmingFrom) {
    if (temperatureFrom.layer === 'emergencyRestore') {
      return 'Your display is back to its normal output because you chose Restore.';
    }
    if (temperatureFrom.layer === 'userPause') {
      return 'Daylight is paused, so your display is at its normal output.';
    }
    const warmth = describeWarmth(target.kelvin);
    let s;
    switch (temperatureFrom.layer) {
      case 'manualOverride':
        s = `Your display is ${warmth} because you set it manually.`; break;
      case 'activityRule':
        s = `Your display is ${warmth} because “${temperatureFrom.label}” is active for this app.`; break;
      case 'workspaceProfile':
        s = `Your display is ${warmth} because you are set up at ${temperatureFrom.label}.`; break;
      case 'baseSchedule':
        s = `Your display is ${warmth}, following ${temperatureFrom.label}.`; break;
      default:
        s = `Your display is ${warmth}.`;
    }
    if (target.dimming < 0.995 && dimmingFrom.layer !== temperatureFrom.layer) {
      s += ` Dimming comes from “${dimmingFrom.label}”.`;
    }
    return s;
  }

  return { LAYERS, rankOf, resolve, explain, describeWarmth };
}));
