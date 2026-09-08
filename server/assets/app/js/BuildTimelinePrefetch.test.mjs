import test from "node:test";
import assert from "node:assert/strict";
import { TimelinePrefetch } from "./BuildTimelinePrefetch.mjs";

const range = { start: 300_000, span: 40_000 };

test("fast scrolling predicts farther ahead while keeping the visible interval in the response", () => {
  const prediction = new TimelinePrefetch(() => 100);
  prediction.pan(280_000, 300_000);
  const plan = prediction.plan(range, 900_000);
  assert.equal(plan.needed.start + plan.needed.span, 430_000);
  assert.equal(plan.request.start, 360_000);
  assert.ok(plan.request.start - 60_000 <= range.start);
  assert.ok(plan.request.start + plan.request.span + 60_000 >= range.start + range.span);
});

test("direction reversals immediately preload behind the viewport", () => {
  let now = 100;
  const prediction = new TimelinePrefetch(() => now);
  prediction.pan(290_000, 300_000);
  now += 16;
  prediction.pan(300_000, 290_000);
  assert.equal(prediction.plan(range, 900_000).request.start, 240_000);
});

test("slower responses increase prefetch lead and idle motion expires", () => {
  let now = 100;
  const prediction = new TimelinePrefetch(() => now);
  prediction.pan(297_000, 300_000);
  const fast = prediction.plan(range, 900_000);
  prediction.received(1000);
  const slow = prediction.plan(range, 900_000);
  assert.ok(slow.needed.span > fast.needed.span);
  now += 501;
  assert.equal(prediction.plan(range, 900_000).request.start, range.start);
});

test("predicted ranges stop at the beginning and end of the build", () => {
  const prediction = new TimelinePrefetch(() => 100);
  prediction.pan(800_000, 860_000);
  assert.deepEqual(prediction.plan({ start: 860_000, span: 40_000 }, 900_000).request, {
    start: 860_000,
    span: 40_000,
  });
  prediction.pan(40_000, 0);
  assert.deepEqual(prediction.plan({ start: 0, span: 40_000 }, 900_000).request, { start: 0, span: 40_000 });
});
