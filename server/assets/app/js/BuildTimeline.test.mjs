import test from "node:test";
import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import { TimelinePrefetch } from "./BuildTimelinePrefetch.mjs";
import { TimelineCache } from "./BuildTimelineCache.mjs";

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
  const cache = new TimelineCache();
  cache.add({ start: 0, span: 300_000 }, []);
  return {
    ...hook,
    range: { start: 100_000, span: 10_000 },
    cache,
    prefetch: new TimelinePrefetch(),
    abort: new AbortController(),
    maxSpan: 120_000,
    duration: 900_000,
    filtered: [],
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
  view.requestRange = () => queries++;
  for (let i = 0; i < 100; i++) view.zoom(i % 2 ? 1.01 : 1 / 1.01);
  assert.equal(frames.length, 1);
  assert.equal(queries, 0);
  assert.equal(scrollUpdates, 0);
  frames.shift()();
  assert.equal(paints, 1);
  assert.equal(scrollUpdates, 1);
});

test("zoom out clamps around its anchor and requests missing neighboring data", () => {
  const view = fixture();
  view.scheduleDraw = () => {};
  let queries = 0;
  view.requestRange = () => queries++;
  view.zoom(100);
  assert.equal(view.range.span, 120_000);
  assert.equal(view.range.start, 45_000);
  assert.equal(queries, 0);
  view.setRange(850_000, 30_000);
  assert.equal(queries, 1);
  assert.equal(view.chart.getAttribute("aria-busy"), "true");
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

test("scrolling prefetches before reaching uncached time without marking loaded work busy", () => {
  const view = fixture();
  view.scheduleDraw = () => {};
  let queries = 0;
  view.requestRange = () => queries++;
  view.setRange(275_000, 10_000);
  assert.equal(queries, 0);
  view.setRange(280_000, 10_000);
  assert.equal(queries, 1);
  assert.equal(view.chart.getAttribute("aria-busy"), "false");
});

test("continuous scrolling accepts in-flight responses and then fetches the current viewport", () => {
  const view = fixture();
  view.scheduleDraw = () => {};
  const requests = [];
  view.pushEvent = (_name, request) => {
    requests.push(request);
    return Promise.resolve({});
  };
  view.requestRange = () => view.loadRange();
  view.setRange(290_000, 10_000);
  const first = requests[0].request_id;
  for (let start = 310_000; start < 450_000; start += 1000) view.setRange(start, 10_000);
  assert.equal(requests.length, 1);
  assert.equal(view.rangeRequest, first);
  view.receiveRange({
    request_id: first,
    timeline: {
      events: [],
      range: { start: 290_000, span: 10_000 },
      loaded_range: { start: 230_000, span: 130_000 },
    },
  });
  assert.equal(requests.length, 2);
  assert.equal(requests[1].start, 449_000);
  assert.ok(view.cache.contains({ start: 250_000, span: 100_000 }));
  view.receiveRange({
    request_id: requests[1].request_id,
    timeline: {
      events: [],
      range: { start: 449_000, span: 10_000 },
      loaded_range: { start: 389_000, span: 130_000 },
    },
  });
  assert.equal(view.chart.getAttribute("aria-busy"), "false");
  assert.equal(requests.length, 2);
});

test("filter changes reject old in-flight data", () => {
  const view = fixture();
  view.scheduleDraw = () => {};
  view.requestRange = () => {};
  view.select = () => {};
  view.control = () => ({ value: "new target" });
  view.initialRange = { ...view.range };
  const stale = view.rangeRequest;
  view.filter();
  view.receiveRange({
    request_id: stale,
    timeline: { events: [{ event_id: 99 }], loaded_range: { start: 0, span: 900_000 } },
  });
  assert.equal(view.cache.events.length, 0);
  assert.equal(view.resetRange, true);
});

test("wide zoom retains headroom after prefetch rather than reloading on every small scroll", () => {
  const view = fixture();
  view.cache = new TimelineCache();
  view.cache.add({ start: 100_000, span: 240_000 }, []);
  view.scheduleDraw = () => {};
  let queries = 0;
  view.requestRange = () => queries++;
  for (let start = 160_000; start < 190_000; start += 1000) view.setRange(start, 120_000);
  assert.equal(queries, 0);
  view.setRange(191_000, 120_000);
  assert.equal(queries, 1);
});

test("fast scrolling shifts the actual preload request ahead before visible data runs out", () => {
  const view = fixture();
  view.scheduleDraw = () => {};
  const requests = [];
  view.pushEvent = (_name, request) => {
    requests.push(request);
    return Promise.resolve({});
  };
  view.requestRange = () => view.loadRange();
  view.prefetch.pan(265_000, 285_000);
  view.setRange(285_000, 10_000);
  assert.equal(view.chart.getAttribute("aria-busy"), "false");
  assert.equal(requests.length, 1);
  assert.equal(requests[0].start, 345_000);
  assert.equal(requests[0].start - 60_000, view.range.start);
});
