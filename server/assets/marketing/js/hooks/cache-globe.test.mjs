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
  const context = {
    Intl,
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
      regions: [
        { id: "us-west", location: [45.52, -122.99], downloads: 1000, recent_downloads: 0 },
        { id: "eu-west", location: [48.86, 2.35], downloads: 200, recent_downloads: 12 },
      ],
      origins: [],
    },
    el: {
      dataset: {},
      querySelector: (selector) => {
        if (selector.startsWith('[data-region="')) {
          const id = selector.match(/data-region="([^"]+)"/)[1];
          if (!cells.has(id))
            cells.set(id, { id, style: { setProperty: (name, value) => (cells.get(id)[name] = value) } });
          return { querySelector: () => cells.get(id) };
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
  return { hook, rendered, events, cells, strip, advanceClock: (milliseconds) => (now += milliseconds) };
}

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

test("arrivals advance daily regional totals, snapshots resync them, and unavailable regions ignore arrivals", () => {
  const { hook, rendered, strip } = fixture();
  hook.el.dataset.snapshot = JSON.stringify(hook.snapshot);
  hook.mounted();
  const arrive = (weight) =>
    hook.globe.dispatchEvent({ type: "dither-globe:arrival", detail: { region: "us-west", weight } });
  arrive(5);
  assert.equal(rendered["us-west"], "1,005");

  hook.snapshot.regions[0].downloads = 999999;
  hook.updateSnapshot();
  assert.equal(strip["--count-length"], "7");
  arrive(1);
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

test("activity markers and arc rates still use the five-minute window", () => {
  const { hook, events } = fixture();
  hook.snapshot.origins = [{ location: [52.52, 13.4], region: "eu-west", recent_downloads: 12 }];
  hook.updateSnapshot();
  hook.active = true;
  hook.pushMarkers();

  const markers = events.find((event) => event.type === "dither-globe:markers").detail.markers;
  assert.equal(markers.find((marker) => marker.id === "us-west").active, false);
  assert.equal(markers.find((marker) => marker.id === "eu-west").active, true);
  const origins = events.find((event) => event.type === "dither-globe:origins").detail.origins;
  assert.equal(origins[0].rate, 12 / 300);

  events.length = 0;
  hook.active = false;
  hook.pushMarkers();
  assert.equal(events.find((event) => event.type === "dither-globe:origins").detail.origins.length, 0);
});
