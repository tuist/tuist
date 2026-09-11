import test from "node:test";
import assert from "node:assert/strict";
import { TimelineMetrics } from "./BuildTimelineMetrics.mjs";

test("prefers normalized Bazel percentages while retaining the native cores fallback", () => {
  const sample = { offset_ms: 0, duration_ms: 1000, cpu_usage_cores: 6 };
  const normalized = new TimelineMetrics([{ ...sample, cpu_usage_percent: 50 }]);
  assert.equal(normalized.tracks[0].max, 100);
  assert.equal(normalized.label(normalized.tracks[0], 500), "50 %");
  const native = new TimelineMetrics([sample]);
  assert.equal(native.label(native.tracks[0], 500), "6 cores");
});

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

test("uses a real pre-build sample to cover zero without extrapolating", () => {
  const model = new TimelineMetrics([
    { offset_ms: -200, cpu_usage_percent: 20 },
    { offset_ms: 800, cpu_usage_percent: 40 },
  ]);
  assert.deepEqual(
    model.visible({ start: 0, span: 800 }).map((s) => s.offset_ms),
    [-200, 800],
  );
  assert.equal(model.sampleAt(0).cpu_usage_percent, 20);
  assert.equal(model.sampleAt(-201), null);
  assert.equal(model.sampleAt(801), null);
});

test("Bazel CPU counters retain core units and memory scales to recorded usage", () => {
  const model = new TimelineMetrics([{ offset_ms: 0, cpu_usage_cores: 6.5, memory_used_bytes: 16e9 }]);
  assert.equal(model.tracks[0].unit, "cores");
  assert.equal(model.tracks[0].max, 6.5);
  assert.equal(model.label(model.tracks[0], 0), "6.5 cores");
  assert.equal(model.tracks[1].max, 16e9);
  assert.equal(model.sampleAt(-1), null);
});

test("a sub-second Bazel build renders its counter bucket as a segment and supports hover throughout", () => {
  const model = new TimelineMetrics([{ offset_ms: 8, duration_ms: 395, cpu_usage_cores: 1.8 }]);
  assert.equal(model.sampleAt(7), null);
  assert.equal(model.label(model.tracks[0], 200), "1.8 cores");
  assert.equal(model.label(model.tracks[0], 403), "1.8 cores");
  assert.equal(model.sampleAt(404), null);

  const lines = [];
  let from;
  const ctx = new Proxy(
    {},
    {
      get: (_, key) => {
        if (key === "moveTo")
          return (...point) => {
            from = point;
          };
        if (key === "lineTo")
          return (...point) => {
            lines.push([from, point]);
          };
        return () => {};
      },
    },
  );
  model.draw(ctx, 427, 120, model.tracks[0], { start: 0, span: 403 }, {});
  assert.deepEqual(lines.at(-1), [
    [20, 3],
    [415, 3],
  ]);

  lines.length = 0;
  model.draw(ctx, 224, 120, model.tracks[0], { start: 100, span: 200 }, {});
  assert.deepEqual(lines.at(-1), [
    [-80, 3],
    [315, 3],
  ]);
});

test("Bazel buckets keep discrete values, preserve missing intervals, and do not extend the final bucket", () => {
  const model = new TimelineMetrics([
    { offset_ms: 8, duration_ms: 1000, cpu_usage_cores: 1 },
    { offset_ms: 1008, duration_ms: 1000, cpu_usage_cores: 2 },
    { offset_ms: 3008, duration_ms: 395, cpu_usage_cores: 3 },
  ]);
  assert.equal(model.sampleAt(1007).cpu_usage_cores, 1);
  assert.equal(model.sampleAt(1008).cpu_usage_cores, 2);
  assert.equal(model.sampleAt(2500), null);
  assert.equal(model.sampleAt(3403).cpu_usage_cores, 3);
  assert.equal(model.sampleAt(3404), null);
  assert.deepEqual(
    model.visible({ start: 2200, span: 200 }).map((s) => s.offset_ms),
    [1008, 3008],
  );
});

test("native counter segments connect across floating-point rounding but preserve collection gaps", () => {
  const model = new TimelineMetrics([
    { offset_ms: 0, duration_ms: 250.1234, cpu_usage_cores: 1 },
    { offset_ms: 250.1235, duration_ms: 250, cpu_usage_cores: 2 },
    { offset_ms: 750.1235, duration_ms: 250, cpu_usage_cores: 3 },
  ]);
  const lines = [];
  let from;
  const ctx = new Proxy(
    {},
    {
      get: (_, key) => {
        if (key === "moveTo")
          return (...point) => {
            from = point;
          };
        if (key === "lineTo")
          return (...point) => {
            lines.push([from, point]);
            from = point;
          };
        return () => {};
      },
    },
  );
  model.draw(ctx, 1024, 120, model.tracks[0], { start: 0, span: 1000 }, {});
  const transitions = lines.filter(([start, end]) => start[0] === end[0] && start[1] !== end[1]);
  assert.equal(transitions.length, 1);
  assert.ok(Math.abs(transitions[0][0][0] - 262.1235) < 1e-9);
  assert.equal(model.label(model.tracks[0], 600), "—");
});
