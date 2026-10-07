import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("./dither-globe.js", import.meta.url), "utf8")
  .replace('import { onThemeChange } from "../lib/theme.js";', "")
  .replace("export const DitherGlobe =", "globalThis.hook =");
const context = {};
runInNewContext(source, context);

const origin = { lat: 51.17, lon: 10.45, to: { lat: 48.86, lon: 2.35 }, region: "eu-west", rate: 1 };

function arcFixture(illustrative = false) {
  const arrivals = [];
  const hook = Object.assign(Object.create(context.hook), {
    origins: context.originsFrom([{ ...origin, illustrative }]),
    arcs: [],
    markers: [],
    reduced: false,
    opts: { arcRate: 12, arcMax: 60, arcLife: 1.6, arcBusy: 0 },
    markerShade: [120, 80, 255],
    rotation: () => [1, 0, 0, 0, 1, 0, 0, 0, 1],
    ctx: {
      createLinearGradient: () => ({ addColorStop() {} }),
      beginPath() {},
      moveTo() {},
      lineTo() {},
      stroke() {},
      arc() {},
      fill() {},
    },
    canvas: { dispatchEvent: (event) => arrivals.push(event) },
  });
  hook.origins[0].acc = 1;
  return { hook, arrivals };
}

context.CustomEvent = class {
  constructor(type, options) {
    this.type = type;
    this.detail = options.detail;
  }
};

test("illustrative and reported routes never merge their rates or emission progress", () => {
  const routes = context.originsFrom([origin, { ...origin, illustrative: true, rate: 2 }]);
  assert.equal(routes.length, 2);
  routes[0].acc = 0.75;
  routes[1].acc = 0.25;
  const updated = context.originsFrom([origin, { ...origin, illustrative: true, rate: 3 }], routes);
  assert.equal(updated[0].rate, 1);
  assert.equal(updated[0].acc, 0.75);
  assert.equal(updated[1].rate, 3);
  assert.equal(updated[1].acc, 0.25);
  assert.equal(updated[1].illustrative, true);
});

for (const illustrative of [false, true]) {
  test(`${illustrative ? "illustrative" : "reported"} arcs animate, but only reported arcs dispatch arrivals`, () => {
    const { hook, arrivals } = arcFixture(illustrative);
    hook.renderArcs(100, 100, 100, 0.1);
    assert.equal(hook.arcs.length, 1);
    assert.equal(hook.arcs[0].illustrative, illustrative);
    assert.equal(hook.arcs[0].weight, illustrative ? 0 : 1);
    hook.origins = [];
    hook.renderArcs(100, 100, 100, 1.9);
    assert.equal(hook.arcs[0].landed, true);
    assert.equal(arrivals.length, illustrative ? 0 : 1);
    if (!illustrative) assert.equal(arrivals[0].detail.weight, 1);
    hook.renderArcs(100, 100, 100, 2);
    assert.equal(hook.arcs.length, 0);
  });
}

test("illustrative arcs do not launch on static repaints or under reduced motion", () => {
  const { hook } = arcFixture(true);
  hook.renderArcs(100, 100, 100, 0);
  assert.equal(hook.arcs.length, 0);
  hook.reduced = true;
  hook.renderArcs(100, 100, 100, 0.1);
  assert.equal(hook.arcs.length, 0);
});

test("a single active region produces visible illustrative strokes from every quarter-turn of the globe", () => {
  const controllerContext = {};
  const controllerSource = readFileSync(new URL("./cache-globe.js", import.meta.url), "utf8").replace(
    "export const CacheGlobe =",
    "globalThis.hook =",
  );
  runInNewContext(controllerSource, controllerContext);
  const controller = Object.assign(Object.create(controllerContext.hook), {
    data: { regions: [{ id: "us-west", location: [45.52, -122.99], recent_downloads: 12 }] },
  });
  for (const spin of [0, Math.PI / 2, Math.PI, (Math.PI * 3) / 2]) {
    const { hook, arrivals } = arcFixture(true);
    hook.origins = context.originsFrom(controller.illustrativeOrigins(3));
    hook.origins.forEach((route, index) => {
      route.acc = (index * 0.618) % 1;
    });
    const cos = Math.cos(spin);
    const sin = Math.sin(spin);
    hook.rotation = () => [cos, 0, sin, 0, 1, 0, -sin, 0, cos];
    let strokes = 0;
    hook.ctx.stroke = () => strokes++;
    for (let frame = 0; frame < 50; frame++) hook.renderArcs(300, 400, 400, 0.1);
    assert.ok(strokes > 0, `No visible strokes at spin ${spin}`);
    assert.ok(hook.arcs.length <= hook.opts.arcMax);
    assert.equal(arrivals.length, 0);
  }
});

test("origins present before canvas mounting are parsed without waiting for another update", () => {
  const origins = context.parseOrigins(JSON.stringify([origin]));
  assert.equal(origins.length, 1);
  assert.equal(origins[0].rate, 1);
  assert.equal(origins[0].region, "eu-west");
  assert.equal(context.parseOrigins(undefined).length, 0);
  assert.equal(context.parseOrigins("invalid").length, 0);
});

test("repeated origin updates preserve emission progress, including zero phase and changed rates", () => {
  const previous = context.originsFrom([origin]);
  previous[0].acc = 0.75;
  const updated = context.originsFrom([{ ...origin, rate: 2 }], previous);
  assert.equal(updated[0].acc, 0.75);
  assert.equal(updated[0].rate, 2);
  updated[0].acc = 0;
  assert.equal(context.originsFrom([origin], updated)[0].acc, 0);
});

test("overlapping windows for the same route share an emitter with their combined rate", () => {
  const origins = context.originsFrom([origin, { ...origin, rate: 2 }]);
  assert.equal(origins.length, 1);
  assert.equal(origins[0].rate, 3);
  origins[0].acc = 0.9;
  const updated = context.originsFrom([origin, origin], origins);
  assert.equal(updated[0].rate, 2);
  assert.equal(updated[0].acc, 0.9);
  const afterWindowEnds = context.originsFrom([origin], updated);
  assert.equal(afterWindowEnds[0].rate, 1);
  assert.equal(afterWindowEnds[0].acc, 0.9);
});

test("distinct serving regions stay distinct, and removed or invalid routes emit nothing", () => {
  const origins = context.originsFrom([origin, { ...origin, region: "eu-east", to: { lat: 52.23, lon: 21.01 } }]);
  assert.equal(origins.length, 2);
  origins[0].acc = 0.7;
  const remaining = context.originsFrom([origin], origins);
  assert.equal(remaining.length, 1);
  assert.equal(remaining[0].acc, 0.7);
  assert.equal(context.originsFrom([], remaining).length, 0);
  assert.equal(
    context.originsFrom(
      [
        { ...origin, rate: 0 },
        { ...origin, lat: NaN },
      ],
      remaining,
    ).length,
    0,
  );
});
