import test from "node:test";
import assert from "node:assert/strict";
import { TimelineCache } from "./BuildTimelineCache.mjs";

test("overlapping windows cover both directions and deduplicate steps", () => {
  const cache = new TimelineCache();
  const a = { event_id: 1, start_ms: 10 },
    b = { event_id: 2, start_ms: 80 };
  cache.add({ start: 0, span: 100 }, [a, b]);
  cache.add({ start: 70, span: 100 }, [b]);
  assert.ok(cache.contains({ start: 5, span: 160 }));
  assert.deepEqual(cache.events, [a, b]);
});

test("reports unloaded intervals separately from known empty gaps", () => {
  const cache = new TimelineCache();
  cache.add({ start: 10, span: 20 }, []);
  cache.add({ start: 50, span: 20 }, []);
  assert.ok(cache.contains({ start: 10, span: 20 }));
  assert.deepEqual(cache.missing({ start: 0, span: 80 }), [
    { start: 0, span: 10 },
    { start: 30, span: 20 },
    { start: 70, span: 10 },
  ]);
});

test("retains a bounded number of windows and releases evicted metadata", () => {
  const cache = new TimelineCache(2);
  for (let i = 0; i < 3; i++) cache.add({ start: i * 100, span: 100 }, [{ event_id: i, start_ms: i * 100 }]);
  assert.equal(cache.windows.length, 2);
  assert.deepEqual(
    cache.events.map((e) => e.event_id),
    [1, 2],
  );
  assert.equal(cache.contains({ start: 0, span: 100 }), false);
});

test("floating point rounding at a cached boundary does not trigger repeated prefetches", () => {
  const cache = new TimelineCache();
  cache.add({ start: 12345.678, span: 120000 }, []);
  assert.ok(cache.contains({ start: 12345.678, span: 120000.000000001 }));
  assert.equal(cache.contains({ start: 12345.678, span: 120001 }), false);
});
