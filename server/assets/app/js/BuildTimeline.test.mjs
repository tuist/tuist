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
    loadedRange: { start: 70_000, span: 70_000 },
    maxSpan: 30_000,
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
  assert.equal(view.range.span, 30_000);
  assert.equal(view.range.start, 90_000);
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
