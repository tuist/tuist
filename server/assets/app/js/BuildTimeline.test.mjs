import test from "node:test";
import assert from "node:assert/strict";
import { registerHooks } from "node:module";

// Noora is an esbuild alias in production; these tests exercise the hook's
// scheduling and transport without mounting Noora's DOM controls.
const loader = registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "noora")
      return {
        url: "data:text/javascript,export function bindScrollIndicator() {}",
        shortCircuit: true,
      };
    return nextResolve(specifier, context);
  },
});
const { default: hook } = await import("./BuildTimeline.js");
loader.deregister();

function fixture() {
  const parts = new Map();
  const attributes = new Map();
  return {
    ...hook,
    range: { start: 100_000, span: 10_000 },
    abort: new AbortController(),
    maxSpan: 900_000,
    duration: 900_000,
    filtered: [],
    search: "",
    allEvents: [],
    stepsReady: true,
    metrics: { samples: [{}] },
    cancelFocus() {},
    hideTooltip() {},
    chart: {
      setAttribute: (key, value) => attributes.set(key, value),
      getAttribute: (key) => attributes.get(key),
    },
    scrollport: { clientHeight: 480 },
    part(key) {
      if (!parts.has(key)) parts.set(key, {});
      return parts.get(key);
    },
  };
}

function surface(left, width, rulerTop = 0) {
  const line = { style: {} };
  const label = { style: {}, offsetWidth: 80 };
  return {
    canvas: { getBoundingClientRect: () => ({ left, width }) },
    ruler: { offsetTop: rulerTop },
    cursor: { hidden: true, querySelector: (selector) => (selector.includes("cursor-line") ? line : label) },
    selection: { hidden: true, style: {}, querySelector: () => label },
    line,
    label,
  };
}

test("metric and step cursors share a time across different plot widths and column origins", () => {
  const view = fixture();
  view.surfaces = [surface(50, 1024, 82), surface(50, 424), surface(500, 524)];
  view.cursorSource = view.surfaces[2].canvas;
  view.cursorX = 512 + 500 * 0.25;
  let reading;
  view.updateMetricValues = (time) => (reading = time);
  view.updateCursor();
  assert.equal(reading, 102_500);
  assert.deepEqual(
    view.surfaces.map((s) => s.line.style.left),
    ["262px", "112px", "137px"],
  );
  assert.equal(new Set(view.surfaces.map((s) => s.label.textContent)).size, 1);
  assert.equal(view.surfaces[0].label.style.top, "87px");
  assert.equal(view.surfaces[1].label.style.top, "5px");
  view.hideCursor();
  assert.ok(view.surfaces.every((s) => s.cursor.hidden));
  assert.equal(reading, null);
});

test("drag focus highlights the same interval on every independently sized plot", () => {
  const view = fixture();
  view.surfaces = [surface(50, 1024, 82), surface(50, 424), surface(500, 524)];
  view.updateMetricValues = () => {};
  view.previewFocus({ left: 0.25, width: 0.5, span: 5000 });
  assert.deepEqual(
    view.surfaces.map((s) => s.selection.style.width),
    ["500px", "200px", "250px"],
  );
  assert.deepEqual(
    view.surfaces.map((s) => s.selection.style.left),
    ["262px", "112px", "137px"],
  );
  assert.equal(view.surfaces[0].selection.style.top, "82px");
  view.previewFocus(null);
  assert.ok(view.surfaces.every((s) => s.selection.hidden));
  assert.equal(view.focusing, false);
});

test("a burst of cached zoom events performs one layout and paint, with no range requests", (t) => {
  const frames = [];
  globalThis.requestAnimationFrame = (callback) => {
    frames.push(callback);
    return frames.length;
  };
  t.after(() => delete globalThis.requestAnimationFrame);
  const view = fixture();
  let paints = 0,
    scrollUpdates = 0,
    queries = 0;
  view.draw = () => paints++;
  view.syncScroll = () => scrollUpdates++;
  view.pushEvent = () => queries++;
  for (let i = 0; i < 100; i++) view.zoom(i % 2 ? 1.01 : 1 / 1.01);
  assert.equal(frames.length, 1);
  assert.equal(queries, 0);
  assert.equal(scrollUpdates, 0);
  frames.shift()();
  assert.equal(paints, 1);
  assert.equal(scrollUpdates, 1);
});

test("zoom out clamps around its anchor without requesting data", () => {
  const view = fixture();
  view.scheduleDraw = () => {};
  let queries = 0;
  view.pushEvent = () => queries++;
  view.zoom(100);
  assert.equal(view.range.span, 900_000);
  assert.equal(view.range.start, 0);
  assert.equal(queries, 0);
  view.setRange(850_000, 30_000);
  assert.equal(queries, 0);
});

test("redrawing at unchanged dimensions reuses canvas storage and resets its transform", (t) => {
  globalThis.window = { devicePixelRatio: 2 };
  t.after(() => delete globalThis.window);
  let allocations = 0;
  const transforms = [];
  const canvas = {
    get width() {
      return 2000;
    },
    set width(_) {
      allocations++;
    },
    get height() {
      return 960;
    },
    set height(_) {
      allocations++;
    },
    style: {},
    getContext: () => ({ setTransform: (...args) => transforms.push(args) }),
  };
  const view = fixture();
  view.scrollport.clientWidth = 1000;
  view.fonts = { body: "12px sans-serif" };
  view.context(canvas, 480);
  view.context(canvas, 480);
  assert.equal(allocations, 0);
  assert.deepEqual(transforms, [
    [2, 0, 0, 2, 0, 0],
    [2, 0, 0, 2, 0, 0],
  ]);
});

test("full-build metadata remains cached when zooming in and returning to maximum zoom or Home", () => {
  const view = fixture();
  view.range = view.initialRange = { start: 0, span: view.duration };
  view.scheduleDraw = () => {};
  view.pushEvent = () => assert.fail("full-build metadata is already cached");
  view.zoom(0.01);
  assert.equal(view.range.span, 9000);
  view.zoom(1000);
  assert.deepEqual(view.range, { start: 0, span: 900_000 });
  view.setRange(800_000, 5000);
  view.keydown({ key: "Home", preventDefault() {} });
  assert.deepEqual(view.range, { start: 0, span: 900_000 });
});

test("search reuses initial metadata without network requests and preserves the visible range", () => {
  const view = fixture();
  view.allEvents = [
    { event_id: 1, title: "Compile A.swift", target: "App", project: "Workspace", start_ms: 0, end: 1 },
    { event_id: 2, title: "Link", target: "Core", project: "Frameworks", start_ms: 800_000, end: 800_001 },
  ];
  view.select = () => {};
  view.scheduleDraw = () => {};
  view.pushEvent = () => assert.fail("search must not download metadata again");
  const range = { ...view.range };
  for (const [query, ids] of [
    ["A", [1, 2]],
    ["CORE", [2]],
    ["nothing", []],
    ["", [1, 2]],
  ]) {
    view.control = () => ({ value: query });
    view.filter();
    assert.deepEqual(
      view.events.map((e) => e.event_id),
      ids,
    );
    assert.deepEqual(view.range, range);
    view.setRange(0, view.duration);
    view.range = { ...range };
  }
});

test("initialization failure cleans up and hides partially mounted content", async (t) => {
  t.mock.method(globalThis, "fetch", async () => ({ ok: true, json: async () => ({ events: [] }) }));
  const parts = new Map(
    [
      "timeline-content",
      "summary",
      "payload-loading",
      "payload-error",
      "workspace",
      "empty",
      "step-count",
      "target-count",
    ].map((p) => [p, { hidden: false }]),
  );
  let cleaned = false;
  const view = {
    ...hook,
    el: { dataset: { version: "1" }, querySelector: (s) => parts.get(s.match(/"(.*?)"/)[1]) },
    pushEvent: () => Promise.resolve({ timeline: { events: [] } }),
    initialize() {
      throw new Error("binding failed");
    },
    destroyed() {
      cleaned = true;
      this.abort.abort();
    },
  };
  view.mounted();
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(cleaned, true);
  assert.equal(parts.get("timeline-content").hidden, true);
  assert.equal(parts.get("summary").hidden, true);
  assert.equal(parts.get("payload-error").hidden, false);
});

test("empty messages distinguish absent records, searches and unfiltered gaps", (t) => {
  const frames = [];
  globalThis.requestAnimationFrame = (callback) => {
    frames.push(callback);
    return frames.length;
  };
  t.after(() => delete globalThis.requestAnimationFrame);
  const event = {
    event_id: 1,
    start_ms: 0,
    duration_ms: 1,
    end: 1,
    title: "Compile",
    target: "App",
    project: "Workspace",
  };
  for (const [events, search, noRecords, noMatches] of [
    [[], "", true, false],
    [[], "Compile", true, false],
    [[event], "", false, false],
    [[event], "missing", false, true],
  ]) {
    const view = fixture();
    view.allEvents = events;
    view.filtered = search ? [] : events;
    view.search = search;
    view.syncScroll = () => {};
    view.draw = () => {};
    view.relayout();
    frames.shift()();
    assert.equal(!view.part("no-recorded-steps").hidden, noRecords);
    assert.equal(!view.part("no-matches").hidden, noMatches);
  }
});

function loadingFixture() {
  const parts = new Map();
  const part = (name) => {
    if (!parts.has(name)) parts.set(name, { hidden: true });
    return parts.get(name);
  };
  return {
    ...hook,
    el: { dataset: { version: "1", url: "/build/timeline.json" }, querySelector: (s) => part(s.match(/"(.*?)"/)[1]) },
    part,
    pushEvent: async () => ({ timeline: { duration: 100, machine_metrics: [{}] } }),
    initialize(timeline) {
      this.metricPayload = timeline;
      this.part("machine-metrics").hidden = false;
    },
    receiveSteps(timeline) {
      this.receivedSteps = timeline;
    },
    destroyed() {
      this.abort.abort();
    },
  };
}

test("metrics initialize while the independent metadata download is still pending", async (t) => {
  let resolve;
  const pending = new Promise((done) => {
    resolve = done;
  });
  const view = loadingFixture();
  t.mock.method(globalThis, "fetch", (url, options) => {
    assert.equal(url, "/build/timeline.json");
    assert.equal(options.credentials, "same-origin");
    assert.equal(options.redirect, "error");
    assert.equal(options.signal, view.abort.signal);
    return pending;
  });
  const loading = view.mounted();
  await new Promise((done) => setImmediate(done));
  assert.equal(view.part("machine-metrics").hidden, false);
  assert.equal(view.part("payload-loading").hidden, false);
  assert.equal(view.receivedSteps, undefined);
  resolve({ ok: true, json: async () => ({ events: [{ event_id: 1 }] }) });
  await loading;
  assert.deepEqual(view.receivedSteps.events, [{ event_id: 1 }]);
});

test("a failed metadata download preserves already loaded machine metrics", async (t) => {
  t.mock.method(globalThis, "fetch", async () => ({ ok: false }));
  const view = loadingFixture();
  await view.mounted();
  assert.equal(view.part("machine-metrics").hidden, false);
  assert.equal(view.part("payload-error").hidden, false);
  assert.equal(view.part("payload-loading").hidden, true);
  assert.equal(view.abort.signal.aborted, false);
});

test("leaving a timeline aborts its download and ignores a late response", async (t) => {
  let resolve;
  t.mock.method(
    globalThis,
    "fetch",
    () =>
      new Promise((done) => {
        resolve = done;
      }),
  );
  const view = loadingFixture();
  const loading = view.mounted();
  await new Promise((done) => setImmediate(done));
  view.destroyed();
  resolve({ ok: true, json: async () => ({ events: [{ event_id: 1 }] }) });
  await loading;
  assert.equal(view.receivedSteps, undefined);
});

test("receiving steps preserves a range selected on metrics while loading", () => {
  const view = fixture();
  const stats = new Map();
  view.el = {
    querySelector(s) {
      if (!stats.has(s)) stats.set(s, {});
      return stats.get(s);
    },
  };
  view.filter = () => {};
  const range = { ...view.range };
  view.receiveSteps({ events: [], duration: view.duration, total_count: 0, target_count: 0 });
  assert.deepEqual(view.range, range);
  assert.equal(view.stepsReady, true);
  assert.equal(view.part("workspace").hidden, false);
  assert.equal(view.part("empty").hidden, true);
  view.metrics.samples = [];
  view.receiveSteps({ events: [], duration: view.duration, total_count: 0, target_count: 0 });
  assert.equal(view.part("workspace").hidden, true);
  assert.equal(view.part("empty").hidden, false);
});
