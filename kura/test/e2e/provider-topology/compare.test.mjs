import assert from "node:assert/strict";
import test from "node:test";
import { compare } from "./compare.mjs";

function run(cpu = 5) {
  return {
    work: { seedProbeAttempts: 192, seedProbeBytes: 192 * 1024 ** 2, puts: 320, gets: 1728, readBytes: 1728 * 1024 ** 2, handshakes: 1280, retainedObjects: 960, loadDurationMs: 64000 },
    clientWriteBytes: 320 * 1024 ** 2, clientEgressBytes: 1920 * 1024 ** 2, peerAppliedBytes: 640 * 1024 ** 2,
    anonymous: { peakBytes: 500, cooldownBytes: 200 }, allocated: { peakBytes: 300, cooldownBytes: 100 },
    resident: { peakBytes: 400, cooldownBytes: 150 },
    transientPeakBytes: 20, transientPeakFraction: 0.1, pressureTransitions: 0, maxPressureTier: 0, capacitySheds: 0, diskBytes: 1024 ** 3, diskAllocatedBytes: 1024 ** 3,
    segmentRefreshBytes: 0, cpuSecondsPerClientGiB: cpu, networkTransmitBytes: 1024 ** 3,
    networkReceiveBytes: 1024 ** 3,
  };
}

test("ABBA comparison preserves raw values, normalization and baseline spread", () => {
  const result = compare([run(5), run(9), run(11), run(7)]);
  assert.deepEqual(result.axes.cpuSecondsPerClientGiB, {
    baseline: [5, 7], candidate: [9, 11], delta: 4, baselineSpread: 2,
    percent: 100 * 4 / 6, increaseBeyondBaselineSpread: true,
  });
  assert.equal(result.axes.allocatedDiskBytesPerWriteGiB.delta, 0);
  assert.equal(result.axes.capacitySheds.percent, null);
});

test("smaller changes remain visible inside baseline variation", () => {
  const result = compare([run(5), run(6), run(7), run(7)]);
  assert.equal(result.axes.cpuSecondsPerClientGiB.delta, 0.5);
  assert.equal(result.axes.cpuSecondsPerClientGiB.increaseBeyondBaselineSpread, false);
});

test("missing metrics, unequal work, nonfinite values and wrong order count refuse", () => {
  assert.throws(() => compare([run(), run()]), /four ABBA/);
  const unequal = run(); unequal.work.handshakes--;
  assert.throws(() => compare([run(), unequal, run(), run()]), /work differs/);
  const extraReads = run(); extraReads.clientEgressBytes++;
  assert.throws(() => compare([run(), extraReads, run(), run()]), /work differs/);
  const extraProbes = run(); extraProbes.work.seedProbeAttempts++;
  assert.throws(() => compare([run(), extraProbes, run(), run()]), /work differs/);
  const missing = run(); delete missing.work.retainedObjects;
  assert.throws(() => compare([run(), missing, run(), run()]), /work is missing/);
  const metric = run(); delete metric.anonymous.cooldownBytes;
  assert.throws(() => compare([run(), metric, run(), run()]), /missing or invalid/);
  assert.throws(() => compare([run(), run(Infinity), run(), run()]), /missing or invalid/);
});
