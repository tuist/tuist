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
    w: 800,
    h: 800,
    opts: { arcRate: 12, arcMax: 60, arcLife: 1.6, arcBusy: 0 },
    markerShade: [120, 80, 255],
    rotation: () => [1, 0, 0, 0, 1, 0, 0, 0, 1],
    ctx: {
      createLinearGradient: () => ({ addColorStop() {} }),
      save() {},
      restore() {},
      transform() {},
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

function illustrativeRoutes(regions) {
  const controllerContext = {};
  const controllerSource = readFileSync(new URL("./cache-globe.js", import.meta.url), "utf8").replace(
    "export const CacheGlobe =",
    "globalThis.hook =",
  );
  runInNewContext(controllerSource, controllerContext);
  const controller = Object.assign(Object.create(controllerContext.hook), { data: { regions } });
  return context.originsFrom(controller.illustrativeOrigins(3));
}

test("illustrative arcs and heads stay inside the canvas across rotation and resizing", () => {
  const { hook } = arcFixture(true);
  hook.origins = illustrativeRoutes([
    { id: "us-west", location: [45.52, -122.99], recent_downloads: 12 },
    { id: "us-central", location: [41.88, -87.63], recent_downloads: 12 },
    { id: "us-east", location: [38.75, -77.67], recent_downloads: 12 },
    { id: "sa-west", location: [-33.45, -70.67], recent_downloads: 12 },
    { id: "eu-west", location: [48.86, 2.35], recent_downloads: 12 },
    { id: "eu-east", location: [52.23, 21.01], recent_downloads: 12 },
    { id: "ap-southeast", location: [1.35, 103.82], recent_downloads: 12 },
  ]);
  hook.origins.forEach((route) => {
    route.acc = 1;
  });
  hook.opts.arcMax = 200;
  hook.opts.tiltX = 0.12;
  hook.opts.tiltZ = -0.26;
  hook.drag = [1, 0, 0, 0, 1, 0, 0, 0, 1];
  hook.spin = 0;
  delete hook.rotation;
  hook.w = 844;
  hook.h = 856;
  hook.renderArcs(422 * 0.86, 422, 428, 0.01);
  assert.equal(hook.arcs.length, 189);
  hook.origins = [];
  for (const [w, h, offsetX, offsetY] of [
    [844, 856, 0, 0],
    [320, 480, 0, 0],
    [1200, 600, 25, -20],
    [300, 280, 0, 0],
  ]) {
    hook.w = w;
    hook.h = h;
    const rad = (Math.min(w, h) / 2) * 0.86;
    const checkPoint = (x, y, radius = hook.ctx.lineWidth / 2) => {
      assert.ok(x - radius >= 0 && x + radius <= w, `Horizontal clipping at ${w}x${h}: ${x} ± ${radius}`);
      assert.ok(y - radius >= 0 && y + radius <= h, `Vertical clipping at ${w}x${h}: ${y} ± ${radius}`);
    };
    hook.ctx.moveTo = checkPoint;
    hook.ctx.lineTo = checkPoint;
    hook.ctx.arc = checkPoint;
    for (const progress of [0.5, 1]) {
      hook.arcs.forEach((arc) => {
        arc.age = arc.life * progress;
        arc.landed = progress === 1;
      });
      for (let step = 0; step < 72; step++) {
        hook.spin = (step * Math.PI) / 36;
        hook.renderArcs(rad, w / 2 + offsetX, h / 2 + offsetY, 0);
      }
    }
  }
});

test("reported arc geometry is unchanged by decorative canvas fitting", () => {
  const { hook } = arcFixture(false);
  hook.w = 200;
  hook.h = 200;
  hook.renderArcs(86, 100, 100, 0.01);
  const arc = hook.arcs[0];
  arc.age = arc.life / 2;
  hook.origins = [];
  let head;
  hook.ctx.arc = (x, y) => {
    head = [x, y];
  };
  hook.renderArcs(86, 100, 100, 0);
  const point = context.slerp(arc.from, arc.to, 0.5);
  assert.ok(arc.bow > (100 - Math.max(1.2, 86 * 0.008) - 1) / 86 - 1);
  assert.equal(head[0], 100 + point[0] * (1 + arc.bow) * 86);
  assert.equal(head[1], 100 - point[1] * (1 + arc.bow) * 86);
});

test("illustrative routes have no persistent origin dots while reported origin dots retain their limb fade", () => {
  for (const count of [1, 2, 7]) {
    const { hook } = arcFixture(true);
    const routes = illustrativeRoutes(
      Array.from({ length: count }, (_, index) => ({
        id: `region-${index}`,
        location: [48.86, 2.35],
        recent_downloads: 12,
      })),
    );
    assert.equal(routes.length, 27 * count);
    hook.origins = context.originsFrom([
      origin,
      ...Array.from({ length: count }, (_, index) => ({
        ...origin,
        region: `region-${index}`,
        illustrative: true,
      })),
    ]);
    hook.origins.push(...routes);
    let dots = 0;
    let opacity;
    hook.ctx.fill = () => {
      dots++;
      opacity = hook.ctx.globalAlpha;
    };
    const cos = Math.cos(1.09);
    const sin = Math.sin(1.09);
    hook.rotation = () => [cos, 0, sin, 0, 1, 0, -sin, 0, cos];
    const surface = hook.surface(hook.rotation(), hook.origins[0].point, 300, 400, 400);
    assert.ok(surface.limb > 0 && surface.limb < 1);
    hook.renderOrigins(300, 400, 400);
    assert.equal(dots, 1);
    assert.equal(opacity, 0.85 * surface.limb);
  }
});

test("a single active region produces visible illustrative strokes from every quarter-turn of the globe", () => {
  for (const spin of [0, Math.PI / 2, Math.PI, (Math.PI * 3) / 2]) {
    const { hook, arrivals } = arcFixture(true);
    hook.origins = illustrativeRoutes([{ id: "us-west", location: [45.52, -122.99], recent_downloads: 12 }]);
    hook.origins.forEach((route, index) => {
      route.acc = (index * 0.618) % 1;
    });
    hook.w = 844;
    hook.h = 856;
    hook.opts.tiltX = 0.12;
    hook.opts.tiltZ = -0.26;
    hook.drag = [1, 0, 0, 0, 1, 0, 0, 0, 1];
    hook.spin = spin;
    delete hook.rotation;
    let strokes = 0;
    hook.ctx.stroke = () => strokes++;
    for (let frame = 0; frame < 50; frame++) hook.renderArcs(422 * 0.86, 422, 428, 0.1);
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

// Last: it builds the module's land mask, which later origin parsing reuses.
test("origins on ocean texels move to the nearest drawn land within three degrees", () => {
  const MW = 1440;
  const MH = 720;
  // Land only between 0°–10° E and 0°–10° N.
  const data = new Uint8ClampedArray(MW * MH * 4);
  for (let y = 320; y < 360; y++) for (let x = 720; x < 760; x++) data[(y * MW + x) * 4 + 3] = 255;
  context.Path2D = class {
    moveTo() {}
    lineTo() {}
    closePath() {}
  };
  context.document = { createElement: () => ({ getContext: () => ({ fill() {}, getImageData: () => ({ data }) }) }) };
  context.atob = (encoded) => Buffer.from(encoded, "base64").toString("latin1");
  const toLonLat = ([x, y, z]) => [(Math.atan2(x, z) * 180) / Math.PI, (Math.asin(y) * 180) / Math.PI];

  assert.deepEqual(context.landPoint(5, 5), context.ll2xyz(5, 5));
  const [lon, lat] = toLonLat(context.landPoint(-1, 5));
  assert.ok(Math.abs(lon - 0.125) < 1e-9 && Math.abs(lat - 4.875) < 1e-9, `snapped to ${lon}, ${lat}`);
  assert.deepEqual(context.landPoint(-10, 5), context.ll2xyz(-10, 5));
  assert.equal(context.landPoint(-1, 5), context.landPoint(-1, 5));

  const [route] = context.originsFrom([{ lat: 5, lon: -1, to: { lat: 5, lon: 5 }, region: "eu-west", rate: 1 }]);
  assert.deepEqual(route.point, context.landPoint(-1, 5));
  assert.deepEqual(route.to, context.ll2xyz(5, 5));
});
