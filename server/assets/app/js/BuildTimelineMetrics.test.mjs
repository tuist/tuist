import test from "node:test";
import assert from "node:assert/strict";
import { TimelineMetrics } from "./BuildTimelineMetrics.mjs";

test("uses the recorded build offset, excludes legacy timestamps, and sorts duplicate samples", () => {
  const model = new TimelineMetrics([
    { timestamp: 100, cpu_usage_percent: 80 },
    { offset_ms: 1500, cpu_usage_percent: 20 },
    { offset_ms: 500 },
    { offset_ms: 1500, cpu_usage_percent: 30 },
  ]);
  assert.deepEqual(
    model.samples.map((s) => s.offset_ms),
    [500, 1500],
  );
  assert.equal(model.sampleAt(1500).cpu_usage_percent, 30);
  assert.equal(model.sampleAt(0), null);
  assert.equal(model.sampleAt(2000), null);
});

test("culls samples but retains boundary neighbors for consistent zoom and pan", () => {
  const model = new TimelineMetrics(Array.from({ length: 1000 }, (_, i) => ({ offset_ms: i * 1000 })));
  assert.deepEqual(
    model.visible({ start: 4500, span: 2000 }).map((s) => s.offset_ms),
    [4000, 5000, 6000, 7000],
  );
});

test("does not show values inside collection gaps or convert missing values to zero", () => {
  const model = new TimelineMetrics(
    [0, 1000, 2000, 10000, 11000].map((offset_ms) => ({ offset_ms, cpu_usage_percent: 0 })),
  );
  assert.equal(model.sampleAt(6000), null);
  assert.equal(model.label(model.tracks[0], 6000), "—");
  assert.equal(model.label(model.tracks[0], 1000), "0 %");
  assert.equal(model.label(model.tracks[1], 1000), "—");
});

test("keeps a stable machine-wide scale and uses recorded per-second I/O without differentiating again", () => {
  const model = new TimelineMetrics([
    {
      offset_ms: 0,
      memory_total_bytes: 32e9,
      memory_used_bytes: 16e9,
      network_bytes_in: 1048576,
      network_bytes_out: 2097152,
    },
  ]);
  assert.equal(model.tracks[1].max, 32e9);
  assert.equal(model.label(model.tracks[1], 0), "16 GB");
  assert.equal(model.label(model.tracks[2], 0), "In 1 MiB/s · Out 2 MiB/s");
});
