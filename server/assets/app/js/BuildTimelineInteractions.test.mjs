import test from "node:test";
import assert from "node:assert/strict";
import { debounce, hitInLane, nextStep } from "./BuildTimelineInteractions.mjs";
import { normalizeEvents } from "./BuildTimelineModel.mjs";

test("search and log requests coalesce rapid changes and cancel on teardown", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const abort = new AbortController();
  const calls = [];
  const request = debounce((value) => calls.push(value), 150, abort.signal);
  request(1);
  t.mock.timers.tick(100);
  request(2);
  t.mock.timers.tick(149);
  assert.deepEqual(calls, []);
  t.mock.timers.tick(1);
  assert.deepEqual(calls, [2]);
  request(3);
  abort.abort();
  t.mock.timers.tick(200);
  request(4);
  t.mock.timers.tick(200);
  assert.deepEqual(calls, [2]);
});

test("lane hit testing finds intervals and gaps with logarithmic reads", () => {
  let reads = 0;
  const rects = new Proxy(
    Array.from({ length: 50_000 }, (_, id) => ({ event: id, left: id * 4, right: id * 4 + 2, top: 10, bottom: 30 })),
    {
      get(target, key) {
        if (/^\d+$/.test(String(key))) reads++;
        return target[key];
      },
    },
  );
  assert.equal(hitInLane(rects, 199_997, 20), 49_999);
  assert.ok(reads < 20);
  assert.equal(hitInLane(rects, 199_999, 20), undefined);
  assert.equal(hitInLane(rects, 199_997, 35), undefined);
  assert.equal(hitInLane(undefined, 0, 20), undefined);
});

test("keyboard navigation stays directional when the selection is off screen", () => {
  const events = [1, 2, 3, 4].map((id) => ({ event_id: id }));
  const selected = events[1];
  assert.equal(nextStep(events, selected, "ArrowLeft"), events[0]);
  assert.equal(nextStep(events, selected, "ArrowRight"), events[2]);
  assert.equal(nextStep(events, selected, "End"), events[3]);
  assert.equal(nextStep(events, events[0], "ArrowLeft"), events[0]);
  assert.equal(nextStep(events, events[3], "ArrowRight"), events[3]);
});

test("search text is normalized once alongside event metadata", () => {
  const [event] = normalizeEvents([
    { title: "Compile APP.swift", target: "App", project: "Workspace", start_ms: 0, duration_ms: 1 },
  ]);
  assert.equal(event.searchText, "compile app.swift app workspace");
});
