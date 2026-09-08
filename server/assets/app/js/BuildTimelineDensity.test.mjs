import test from "node:test";
import assert from "node:assert/strict";
import { densityLayout } from "./BuildTimelineDensity.mjs";
import { normalizeEvents } from "./BuildTimelineModel.mjs";
const step = (id, start, duration, category = "swiftCompilation") => ({
  event_id: id,
  start_ms: start,
  duration_ms: duration,
  category,
  status: "success",
  title: "Compile",
  target: "App",
  project: "Workspace",
});

test("dense overlap uses bounded readable groups without losing late activity", () => {
  const events = normalizeEvents([
    ...Array.from({ length: 2000 }, (_, id) => step(id, 10, 20)),
    step(2001, 900, 50, "linker"),
  ]);
  const layout = densityLayout(events, { start: 0, span: 1000 }, 480);
  assert.equal(layout.grouped, true);
  assert.ok(layout.events.length <= 768);
  assert.ok(layout.height <= 480);
  assert.ok(layout.events.some((e) => e.kind === "compile" && e.count === 2000));
  assert.ok(layout.events.some((e) => e.kind === "link" && e.start_ms >= 890));
  assert.ok(!layout.events.some((e) => e.start_ms > 100 && e.start_ms < 800));
});
test("zooming into a sparse interval returns individual inspectable steps", () => {
  const events = normalizeEvents([step(1, 0, 500), step(2, 800, 50)]);
  const layout = densityLayout(events, { start: 800, span: 50 }, 480);
  assert.equal(layout.grouped, false);
  assert.deepEqual(
    layout.events.map((e) => e.event_id),
    [2],
  );
});
test("server aggregates retain counts and failure classification", () => {
  const events = normalizeEvents([
    { ...step("failure:0", 0, 10, "failure"), aggregate: true, count: 42, status: "failure" },
  ]);
  const layout = densityLayout(events, { start: 0, span: 1280 }, 480);
  assert.equal(layout.events.length, 1);
  assert.equal(layout.events[0].count, 42);
  assert.equal(layout.events[0].kind, "failure");
});

test("panning does not reinterpret existing server bucket counts", () => {
  const events = normalizeEvents([{ ...step("compile:0", 100, 10), aggregate: true, count: 42 }]);
  const layout = densityLayout(events, { start: 105, span: 11 }, 480);
  assert.equal(layout.events.length, 1);
  assert.equal(layout.events[0].count, 42);
  assert.equal(layout.events[0].start_ms, 100);
});
