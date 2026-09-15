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

test("dense overlaps preserve every step in individual execution lanes", () => {
  const events = normalizeEvents([
    ...Array.from({ length: 255 }, (_, id) => step(id, 10, 20, id % 2 ? "linker" : "swiftCompilation")),
    step(256, 900, 50, "linker"),
  ]);
  const layout = densityLayout(events, { start: 0, span: 1000 }, 480);
  assert.equal(layout.events.length, 256);
  assert.equal(layout.lanes, 255);
  assert.equal(layout.events[0].rowHeight, 26);
  assert.equal(layout.events[1].lane, 1);
  assert.equal(layout.events.at(-1).lane, 0);
  assert.ok(layout.events.every((e) => e.y + e.rowHeight <= 480));
  assert.ok(layout.events.every((e) => e.title));
});

test("zooming into a sparse interval restores readable full-height lanes", () => {
  const events = normalizeEvents([step(1, 0, 500), step(2, 800, 50)]);
  const layout = densityLayout(events, { start: 800, span: 50 }, 480);
  assert.deepEqual(
    layout.events.map((e) => e.event_id),
    [2],
  );
  assert.equal(layout.events[0].rowHeight, 26);
});

test("repeated zooms do not corrupt lane positions", () => {
  const events = normalizeEvents(Array.from({ length: 1000 }, (_, id) => step(id, id * 10, 1000)));
  const before = densityLayout(events, { start: 0, span: 10000 }, 480).events.map((e) => e.y);
  densityLayout(events, { start: 5000, span: 10 }, 320);
  const after = densityLayout(events, { start: 0, span: 10000 }, 480).events.map((e) => e.y);
  assert.deepEqual(after, before);
});
