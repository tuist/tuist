import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("./cache-globe.js", import.meta.url), "utf8").replace(
  "export const CacheGlobe =",
  "globalThis.hook =",
);

function fixture(lang = "en") {
  const rendered = {};
  const events = [];
  const listeners = new Map();
  const cells = new Map();
  const strip = { style: { setProperty: (name, value) => (strip[name] = value) } };
  let now = 0;
  let wallTime = Date.parse("2026-10-05T12:00:00Z");
  const status = { dataset: {}, querySelectorAll: () => [] };
  const context = {
    Intl,
    Date: class extends Date {
      static now() {
        return wallTime + now;
      }
    },
    AbortController,
    performance: { now: () => now },
    setInterval: () => 0,
    matchMedia: () => ({ matches: false, addEventListener() {} }),
    document: { documentElement: { lang } },
    CustomEvent: class {
      constructor(type, options) {
        this.type = type;
        this.detail = options.detail;
      }
    },
  };
  runInNewContext(source, context);
  const hook = Object.assign(Object.create(context.hook), {
    snapshot: {
      downloads: 1200,
      bytes: 1024,
      recent_downloads: 12,
      updated_at: "2026-10-05T12:00:00Z",
      observed_at: "2026-10-05T11:59:00Z",
      status: "available",
      playback_delay_seconds: 300,
      regions: [
        { id: "us-west", location: [45.52, -122.99], downloads: 1000, recent_downloads: 0 },
        { id: "eu-west", location: [48.86, 2.35], downloads: 200, recent_downloads: 12 },
      ],
      origins: [],
    },
    el: {
      dataset: {},
      querySelector: (selector) => {
        if (selector === "#globe-status") return status;
        if (selector.startsWith('[data-region="')) {
          const id = selector.match(/data-region="([^"]+)"/)[1];
          if (!cells.has(id))
            cells.set(id, { id, style: { setProperty: (name, value) => (cells.get(id)[name] = value) } });
          return { dataset: {}, querySelector: () => cells.get(id) };
        }
        return { addEventListener() {} };
      },
    },
    globe: {
      dataset: {},
      addEventListener: (type, listener) => listeners.set(type, listener),
      dispatchEvent: (event) => {
        events.push(event);
        listeners.get(event.type)?.(event);
      },
    },
    sync() {},
    setReel(element, value) {
      if (element.id) rendered[element.id] = value;
    },
    renderDigits(value) {
      rendered.counter = value;
    },
    renderBreakdown() {},
    updateStatus() {},
    updateMotion() {},
  });
  const querySelector = hook.el.querySelector;
  hook.el.querySelector = (selector) => {
    if (selector === '[data-part="globe"]') return hook.globe;
    if (selector === '[data-part="regions"]') return strip;
    return querySelector(selector);
  };
  return {
    hook,
    rendered,
    events,
    cells,
    strip,
    status,
    advanceClock: (milliseconds) => (now += milliseconds),
    setWallClock: (date) => (wallTime = Date.parse(date)),
  };
}

function enableIllustration(hook) {
  hook.el.dataset.illustrativeArcs = "true";
  hook.updateStatus = Object.getPrototypeOf(hook).updateStatus;
}

test("opted-in live pages animate a bounded illustrative baseline without inventing metrics or reported origins", () => {
  const { hook, events, rendered } = fixture();
  enableIllustration(hook);
  const snapshot = JSON.stringify(hook.snapshot);
  hook.updateSnapshot();
  const origins = latestOrigins(events);
  assert.equal(origins.length, 27);
  assert.ok(origins.every((origin) => origin.illustrative && origin.region === "eu-west"));
  assert.ok(Math.abs(origins.reduce((sum, origin) => sum + origin.rate, 0) - 3) < 1e-9);
  assert.ok(origins.some((origin) => origin.lon < -100));
  assert.ok(origins.some((origin) => origin.lon > 100));
  assert.equal(JSON.stringify(hook.snapshot), snapshot);
  assert.equal(hook.data.origins.length, 0);
  assert.equal(rendered["us-west"], "1,000");
  assert.equal(rendered["eu-west"], "200");
  assert.deepEqual(JSON.parse(hook.globe.dataset.origins), JSON.parse(JSON.stringify(origins)));
});

test("illustrative arcs supplement sparse playback without changing its timing, rate or serving region", () => {
  const { hook, events } = fixture();
  enableIllustration(hook);
  hook.snapshot.origins = playbackWindows;
  hook.updateSnapshot();
  const origins = latestOrigins(events);
  const reported = origins.filter((origin) => !origin.illustrative);
  assert.equal(reported.length, 1);
  assert.equal(reported[0].rate, 1);
  assert.equal(reported[0].region, "eu-west");
  assert.ok(Math.abs(origins.reduce((sum, origin) => sum + origin.rate, 0) - 3) < 1e-9);

  hook.snapshot.origins = [{ ...playbackWindows[0], downloads: 600 }];
  hook.updateSnapshot();
  assert.equal(latestOrigins(events).length, 1);
  assert.equal(latestOrigins(events)[0].rate, 10);
  assert.equal(latestOrigins(events)[0].illustrative, undefined);
});

test("illustration distributes a fixed total across recently serving regions, never idle ones", () => {
  const { hook, events } = fixture();
  enableIllustration(hook);
  hook.snapshot.regions[0].recent_downloads = 24;
  hook.updateSnapshot();
  const origins = latestOrigins(events);
  assert.equal(origins.length, 54);
  for (const [region, rate] of [
    ["us-west", 2],
    ["eu-west", 1],
  ]) {
    const routes = origins.filter((origin) => origin.region === region);
    assert.ok(Math.abs(routes.reduce((sum, origin) => sum + origin.rate, 0) - rate) < 1e-9);
    const destination = hook.snapshot.regions.find((entry) => entry.id === region).location;
    assert.ok(routes.every((origin) => origin.to.lat === destination[0] && origin.to.lon === destination[1]));
  }
});

test("illustration stops for offline, stale, unavailable, waiting and quiet snapshots", () => {
  const { hook, events } = fixture();
  enableIllustration(hook);
  hook.updateSnapshot();
  hook.disconnected();
  assert.equal(latestOrigins(events).length, 0);
  hook.reconnected();
  assert.equal(latestOrigins(events).length, 27);
  for (const change of [
    { status: "unavailable" },
    { observed_at: null },
    { updated_at: "2026-10-05T11:56:00Z" },
    { regions: hook.snapshot.regions.map((region) => ({ ...region, recent_downloads: 0 })) },
  ]) {
    const before = hook.snapshot;
    hook.snapshot = { ...before, ...change };
    hook.updateSnapshot();
    assert.equal(latestOrigins(events).length, 0);
    hook.snapshot = before;
    hook.updateSnapshot();
  }
});

test("illustrative updates are stable between snapshots, and opt-in never changes demo behavior", () => {
  const { hook, events } = fixture();
  enableIllustration(hook);
  hook.updateSnapshot();
  events.length = 0;
  hook.updateSnapshot();
  assert.equal(events.length, 0);
  hook.demo = true;
  hook.updateSnapshot();
  assert.ok(latestOrigins(events).every((origin) => !origin.illustrative));
});

test("mounted illustration seeds the canvas immediately and stays stable through counter ticks and LiveView patches", () => {
  const { hook, events, rendered, advanceClock } = fixture();
  enableIllustration(hook);
  hook.sync = Object.getPrototypeOf(hook).sync;
  hook.el.dataset.snapshot = JSON.stringify(hook.snapshot);
  hook.mounted();
  assert.equal(latestOrigins(events).length, 27);
  assert.equal(JSON.parse(hook.globe.dataset.origins).length, 27);
  assert.equal(rendered.counter, 1200);
  events.length = 0;
  advanceClock(60000);
  hook.advance();
  assert.equal(events.length, 0);
  assert.equal(rendered.counter, 1202);
  hook.updated();
  assert.equal(events.length, 0);
  assert.equal(rendered.counter, 1202);
  assert.equal(hook.snapshot.origins.length, 0);
});

test("regional rows show daily downloads even when recent activity is zero", () => {
  const { hook, rendered } = fixture();
  hook.updateSnapshot();
  assert.equal(rendered["us-west"], "1,000");
  assert.equal(rendered["eu-west"], "200");

  hook.snapshot.regions[0].downloads = 1100;
  hook.updateSnapshot();
  assert.equal(rendered["us-west"], "1,100");
});

test("regional rows distinguish unavailable totals from measured zero", () => {
  const { hook, rendered } = fixture();
  hook.snapshot.regions[0].downloads = 0;
  hook.updateSnapshot();
  assert.equal(rendered["us-west"], "0");

  hook.snapshot.downloads = null;
  hook.updateSnapshot();
  assert.equal(rendered["us-west"], "—");
  assert.equal(rendered["eu-west"], "—");
});

test("regional rows retain complete large localized totals and share the longest character count for sizing", () => {
  const { hook, rendered, cells, strip } = fixture();
  hook.snapshot.regions[0].downloads = 12345678;
  hook.updateSnapshot();
  assert.equal(rendered["us-west"], "12,345,678");
  assert.equal(strip["--count-length"], "10");
  assert.equal(cells.get("us-west")["--count-length"], undefined);
  assert.equal(cells.get("eu-west")["--count-length"], undefined);

  hook.snapshot.downloads = null;
  hook.updateSnapshot();
  assert.equal(strip["--count-length"], "1");
});

for (const lang of ["de", "fr", "ar"]) {
  test(`regional sizing includes the complete ${lang} localized total`, () => {
    const { hook, rendered, strip } = fixture(lang);
    hook.snapshot.regions[0].downloads = 12345678;
    hook.updateSnapshot();
    const text = new Intl.NumberFormat(lang).format(12345678);
    assert.equal(rendered["us-west"], text);
    assert.equal(strip["--count-length"], String(text.length));
  });
}

test("LiveView updates restore shared sizing when the region strip's inline style is replaced", () => {
  const { hook, rendered, strip } = fixture();
  hook.snapshot.regions[0].downloads = 12345678;
  hook.el.dataset.snapshot = JSON.stringify(hook.snapshot);
  hook.updateSnapshot();
  delete strip["--count-length"];
  hook.updated();
  assert.equal(rendered["us-west"], "12,345,678");
  assert.equal(strip["--count-length"], "10");
});

test("demo regions show weighted daily totals rather than recent counts", () => {
  const { hook, rendered } = fixture();
  hook.demo = true;
  hook.snapshot.regions = ["us-west", "us-central", "us-east", "sa-west", "eu-west", "eu-east", "ap-southeast"].map(
    (id) => ({ id, location: [0, 0] }),
  );
  hook.updateSnapshot();
  assert.equal(rendered["eu-west"], "444,912");
  assert.equal(hook.regionLive["eu-west"], Math.round((1482903 + 137) * 0.3));
  assert.notEqual(hook.regionLive["eu-west"], Math.round(13720 * 0.3));
});

test("estimated live arrivals never advance measured regional totals, including across a digit boundary", () => {
  const { hook, rendered, strip } = fixture();
  hook.el.dataset.snapshot = JSON.stringify(hook.snapshot);
  hook.mounted();
  const arrive = (weight) =>
    hook.globe.dispatchEvent({ type: "dither-globe:arrival", detail: { region: "us-west", weight } });
  arrive(5);
  assert.equal(rendered["us-west"], "1,000");

  hook.snapshot.regions[0].downloads = 999999;
  hook.updateSnapshot();
  assert.equal(strip["--count-length"], "7");
  arrive(1);
  assert.equal(rendered["us-west"], "999,999");
  assert.equal(strip["--count-length"], "7");
  hook.snapshot.regions[0].downloads = 1000000;
  hook.updateSnapshot();
  assert.equal(rendered["us-west"], "1,000,000");
  assert.equal(strip["--count-length"], "9");

  hook.snapshot.regions[0].downloads = 1010;
  hook.updateSnapshot();
  assert.equal(rendered["us-west"], "1,010");
  assert.equal(strip["--count-length"], "5");

  hook.snapshot.downloads = null;
  hook.updateSnapshot();
  arrive(5);
  assert.equal(rendered["us-west"], "—");
});

test("a new UTC day resets regional totals and the main counter while same-day snapshots cannot rewind it", () => {
  const { hook, rendered, advanceClock } = fixture();
  hook.sync = Object.getPrototypeOf(hook).sync;
  hook.snapshot.updated_at = "2026-10-05T23:59:00Z";
  hook.updateSnapshot();
  advanceClock(60000);
  hook.advance();
  assert.equal(rendered.counter, 1202);

  hook.snapshot.downloads = 1200;
  hook.snapshot.updated_at = "2026-10-05T23:59:30Z";
  hook.updateSnapshot();
  assert.equal(rendered.counter, 1202);

  hook.snapshot = {
    ...hook.snapshot,
    updated_at: "2026-10-06T00:00:30Z",
    downloads: 0,
    recent_downloads: 0,
    regions: hook.snapshot.regions.map((region) => ({ ...region, downloads: 0, recent_downloads: 0 })),
  };
  hook.updateSnapshot();
  assert.equal(rendered.counter, 0);
  assert.equal(rendered["us-west"], "0");
  assert.equal(rendered["eu-west"], "0");
  assert.equal(hook.live.rate, 0);
});

test("activity markers use recent counts while live arcs replay the selected reporting window", () => {
  const { hook, events } = fixture();
  hook.snapshot.origins = [
    {
      location: [52.52, 13.4],
      region: "eu-west",
      downloads: 12,
      window_start: "2026-10-05T11:55:00Z",
      window_seconds: 60,
    },
  ];
  hook.updateSnapshot();
  hook.active = true;
  hook.pushMarkers();

  const markers = events.find((event) => event.type === "dither-globe:markers").detail.markers;
  assert.equal(markers.find((marker) => marker.id === "us-west").active, false);
  assert.equal(markers.find((marker) => marker.id === "eu-west").active, true);
  const origins = events.find((event) => event.type === "dither-globe:origins").detail.origins;
  assert.equal(origins[0].rate, 12 / 60);
  assert.equal(JSON.parse(hook.globe.dataset.origins)[0].rate, 12 / 60);

  events.length = 0;
  hook.active = false;
  hook.pushMarkers();
  assert.equal(events.find((event) => event.type === "dither-globe:origins").detail.origins.length, 0);
});

const playbackWindows = [
  {
    location: [52.52, 13.4],
    region: "eu-west",
    downloads: 60,
    window_start: "2026-10-05T11:55:00Z",
    window_seconds: 60,
  },
  {
    location: [52.52, 13.4],
    region: "eu-west",
    downloads: 120,
    window_start: "2026-10-05T11:56:00Z",
    window_seconds: 60,
  },
];

function latestOrigins(events) {
  return events.findLast((event) => event.type === "dither-globe:origins").detail.origins;
}

test("delayed playback emits steadily between batch updates and transitions once at window boundaries", () => {
  const { hook, events, advanceClock } = fixture();
  hook.sync = Object.getPrototypeOf(hook).sync;
  hook.active = true;
  hook.snapshot.origins = playbackWindows;
  hook.updateSnapshot();
  assert.equal(latestOrigins(events)[0].rate, 1);

  advanceClock(30000);
  hook.advance();
  assert.equal(latestOrigins(events)[0].rate, 1);
  hook.updateSnapshot();
  assert.equal(latestOrigins(events)[0].rate, 1);
  advanceClock(29999);
  hook.advance();
  assert.equal(latestOrigins(events)[0].rate, 1);
  advanceClock(1);
  hook.advance();
  assert.equal(latestOrigins(events)[0].rate, 2);
  advanceClock(60000);
  hook.advance();
  assert.equal(latestOrigins(events).length, 0);
});

test("future windows, real gaps, malformed windows and unknown serving regions do not invent activity", () => {
  const { hook, events, advanceClock } = fixture();
  hook.active = true;
  hook.snapshot.origins = [
    playbackWindows[1],
    { ...playbackWindows[0], window_seconds: 0 },
    { ...playbackWindows[0], window_start: "invalid" },
    { ...playbackWindows[0], region: "private" },
  ];
  hook.updateSnapshot();
  hook.pushMarkers();
  assert.equal(latestOrigins(events).length, 0);
  advanceClock(60000);
  hook.pushMarkers();
  assert.equal(latestOrigins(events).length, 1);
  advanceClock(60000);
  hook.pushMarkers();
  assert.equal(latestOrigins(events).length, 0);
});

test("playback remains anchored to reported timestamps across UTC midnight and resynchronization", () => {
  const { hook, events, advanceClock } = fixture();
  hook.active = true;
  hook.snapshot.origins = [{ ...playbackWindows[0], window_start: "2026-10-05T23:59:00Z" }];
  advanceClock((12 * 60 * 60 + 240) * 1000);
  hook.snapshot.updated_at = "2026-10-06T00:04:00Z";
  hook.updateSnapshot();
  hook.pushMarkers();
  assert.equal(latestOrigins(events)[0].rate, 1);
  advanceClock(30000);
  hook.updateSnapshot();
  hook.pushMarkers();
  assert.equal(latestOrigins(events)[0].rate, 1);
  advanceClock(30000);
  hook.pushMarkers();
  assert.equal(latestOrigins(events).length, 0);
});

test("buffered playback waits for windows that arrive late in the flush/refresh/poll pipeline, then plays their full duration", () => {
  const { hook, events, advanceClock } = fixture();
  // The 11:55 window closed at 11:56 but did not reach this browser until
  // 11:58:30. A two-minute delay would already have skipped it completely.
  hook.el.dataset.serverNow = "2026-10-05T11:58:30Z";
  hook.syncClock();
  hook.active = true;
  hook.snapshot.origins = playbackWindows;
  hook.updateSnapshot();
  hook.pushMarkers();
  assert.equal(latestOrigins(events).length, 0);
  advanceClock(89999);
  hook.pushMarkers();
  assert.equal(latestOrigins(events).length, 0);
  advanceClock(1);
  hook.pushMarkers();
  assert.equal(latestOrigins(events)[0].rate, 1);
  advanceClock(59999);
  hook.pushMarkers();
  assert.equal(latestOrigins(events)[0].rate, 1);
  advanceClock(1);
  hook.pushMarkers();
  assert.equal(latestOrigins(events)[0].rate, 2);
});

test("long windows use their longer closing-time buffer and remain playable after recent measured activity becomes idle", () => {
  const { hook, events, status, advanceClock } = fixture();
  hook.updateStatus = Object.getPrototypeOf(hook).updateStatus;
  hook.snapshot.observed_at = "2026-10-05T11:56:00Z";
  hook.snapshot.origins = [
    {
      ...playbackWindows[0],
      window_start: "2026-10-05T11:51:00Z",
      window_seconds: 300,
      playback_delay_seconds: 540,
    },
  ];
  hook.updateSnapshot();
  assert.equal(latestOrigins(events)[0].rate, 60 / 300);
  advanceClock(120000);
  hook.snapshot.updated_at = "2026-10-05T12:02:00Z";
  hook.updateSnapshot();
  assert.equal(status.dataset.state, "live");
  assert.equal(latestOrigins(events)[0].rate, 60 / 300);
  advanceClock(180000);
  hook.snapshot.updated_at = "2026-10-05T12:05:00Z";
  hook.updateSnapshot();
  assert.equal(status.dataset.state, "idle");
  assert.equal(latestOrigins(events).length, 0);
});

test("unchanged playback ticks do not repaint a held canvas or reset its emitters", () => {
  const { hook, events, advanceClock } = fixture();
  hook.active = true;
  hook.snapshot.origins = playbackWindows;
  hook.updateSnapshot();
  hook.pushMarkers();
  events.length = 0;
  hook.pushMarkers();
  assert.equal(events.length, 0);
  advanceClock(60000);
  hook.pushMarkers();
  assert.equal(events.length, 1);
  assert.equal(events[0].type, "dither-globe:origins");
  assert.equal(events[0].detail.origins[0].rate, 2);
});

test("demo arrivals still advance illustrative regional totals", () => {
  const { hook, rendered } = fixture();
  hook.el.dataset.demo = "true";
  hook.el.dataset.snapshot = JSON.stringify(hook.snapshot);
  hook.mounted();
  const before = hook.regionLive["us-west"];
  hook.globe.dispatchEvent({ type: "dither-globe:arrival", detail: { region: "us-west", weight: 5 } });
  assert.equal(hook.regionLive["us-west"], before + 5);
  assert.equal(rendered["us-west"], new Intl.NumberFormat("en").format(before + 5));
});

test("server-anchored playback ignores kiosk wall-clock skew and later clock adjustments", () => {
  const { hook, events, advanceClock, setWallClock } = fixture();
  hook.el.dataset.serverNow = "2026-10-05T12:00:00Z";
  hook.syncClock();
  hook.active = true;
  hook.snapshot.origins = playbackWindows;
  setWallClock("2026-10-06T12:00:00Z");
  hook.updateSnapshot();
  hook.pushMarkers();
  assert.equal(latestOrigins(events)[0].rate, 1);
  advanceClock(60000);
  setWallClock("2020-01-01T00:00:00Z");
  hook.pushMarkers();
  assert.equal(latestOrigins(events)[0].rate, 2);
  hook.syncClock();
  assert.equal(hook.serverNow(), Date.parse("2026-10-05T12:01:00Z"));
  hook.el.dataset.serverNow = "2026-10-05T12:01:30Z";
  hook.syncClock();
  assert.equal(hook.serverNow(), Date.parse("2026-10-05T12:01:30Z"));
});

test("offline, unavailable, waiting, stale and idle states stop replay, while reconnecting restores the current window", () => {
  const { hook, events, status, setWallClock } = fixture();
  hook.el.dataset.serverNow = "2026-10-05T12:00:00Z";
  hook.syncClock();
  setWallClock("2030-01-01T00:00:00Z");
  hook.updateStatus = Object.getPrototypeOf(hook).updateStatus;
  hook.snapshot.origins = playbackWindows;
  hook.updateSnapshot();
  assert.equal(status.dataset.state, "live");
  assert.equal(latestOrigins(events)[0].rate, 1);
  hook.disconnected();
  assert.equal(status.dataset.state, "offline");
  assert.equal(latestOrigins(events).length, 0);
  hook.reconnected();
  assert.equal(latestOrigins(events)[0].rate, 1);
  for (const [change, state] of [
    [{ status: "unavailable" }, "unavailable"],
    [{ observed_at: null }, "waiting"],
    [{ updated_at: "2026-10-05T11:56:00Z" }, "stale"],
    [{ observed_at: "2026-10-05T11:54:00Z", origins: [] }, "idle"],
  ]) {
    const before = hook.snapshot;
    hook.snapshot = { ...before, ...change };
    hook.updateSnapshot();
    assert.equal(status.dataset.state, state);
    assert.equal(latestOrigins(events).length, 0);
    hook.snapshot = before;
  }
});
