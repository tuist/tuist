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
