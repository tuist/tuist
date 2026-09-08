import test from "node:test";
import assert from "node:assert/strict";
import { registerHooks } from "node:module";
import { TimelinePrefetch } from "./BuildTimelinePrefetch.mjs";
import { TimelineCache } from "./BuildTimelineCache.mjs";
import { TimelineMetrics } from "./BuildTimelineMetrics.mjs";

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
    maxSpan: 900_000,
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
  assert.equal(view.range.span, 900_000);
  assert.equal(view.range.start, 0);
  assert.equal(queries, 1);
  view.setRange(850_000, 30_000);
  assert.equal(queries, 2);
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

test("full-build metadata remains cached when zooming in and returning to maximum zoom or Home", () => {
  const view = fixture();
  view.range = view.initialRange = { start: 0, span: view.duration };
  view.cache.add(view.range, []);
  view.scheduleDraw = () => {};
  view.requestRange = () => assert.fail("full-build metadata is already cached");
  view.zoom(0.01);
  assert.equal(view.range.span, 9000);
  view.zoom(1000);
  assert.deepEqual(view.range, { start: 0, span: 900_000 });
  view.setRange(800_000, 5000);
  view.keydown({ key: "Home", preventDefault() {} });
  assert.deepEqual(view.range, { start: 0, span: 900_000 });
  assert.equal(view.chart.getAttribute("aria-busy"), "false");
});

test("metric hover uses the zoomed time range and shows the recorded sample with both directions", () => {
  const view = fixture();
  view.metrics = new TimelineMetrics([
    { offset_ms: 104_000, network_bytes_in: 1048576, network_bytes_out: 2097152 },
    { offset_ms: 105_000, network_bytes_in: 3145728, network_bytes_out: 0 },
  ]);
  const title = {},
    values = {};
  const tooltip = view.part("tooltip");
  tooltip.querySelector = (selector) => (selector === "strong" ? title : values);
  view.hideTooltip = hook.hideTooltip;
  let positioned = false;
  view.positionTooltip = () => (positioned = true);
  view.hoverMetric({
    clientX: 412,
    pointerType: "mouse",
    currentTarget: {
      dataset: { metricCanvas: "network" },
      getBoundingClientRect: () => ({ left: 100, width: 624 }),
      closest: () => ({ querySelector: () => ({ textContent: "Network" }) }),
    },
  });
  assert.equal(tooltip.hidden, false);
  assert.equal(title.textContent, "Network · 105 s 000 ms");
  assert.equal(values.textContent, "In 3 MiB/s · Out 0 MiB/s");
  assert.equal(positioned, true);
});

test("metric hover hides stale values in collection gaps, missing fields, and during touch or drag", () => {
  const view = fixture();
  view.hideTooltip = hook.hideTooltip;
  view.range = { start: 0, span: 10_000 };
  view.metrics = new TimelineMetrics([
    { offset_ms: 0, cpu_usage_percent: 50 },
    { offset_ms: 1000, cpu_usage_percent: 60 },
    { offset_ms: 2000 },
    { offset_ms: 10_000, cpu_usage_percent: 70 },
  ]);
  const pointer = {
    clientX: 512,
    pointerType: "mouse",
    currentTarget: {
      dataset: { metricCanvas: "cpu" },
      getBoundingClientRect: () => ({ left: 0, width: 1024 }),
    },
  };
  for (const state of [
    { x: 512, type: "mouse", focusing: false },
    { x: 212, type: "mouse", focusing: false },
    { x: 112, type: "touch", focusing: false },
    { x: 112, type: "mouse", focusing: true },
  ]) {
    view.part("tooltip").hidden = false;
    view.focusing = state.focusing;
    view.hoverMetric({ ...pointer, clientX: state.x, pointerType: state.type });
    assert.equal(view.part("tooltip").hidden, true);
  }
});
