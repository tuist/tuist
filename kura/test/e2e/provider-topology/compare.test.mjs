import assert from "node:assert/strict";
import test from "node:test";
import { compare as compareSummaries } from "./compare.mjs";

function compare(runs) {
  return compareSummaries(runs.map((run, index) => {
    const position = index % 4;
    const before = position === 0 || position === 3;
    return { label: `${before ? "before" : "after"}-${Math.floor(index / 4) * 2 + (position < 2 ? 1 : 2)}`,
      imageId: "sha256:" + (before ? "a" : "b").repeat(64), metricsSourceSHA256: "c".repeat(64),
      receiptGeneration: 2, imageIdProvenance: "result", ...run };
  }));
}

function run(cpu = 5) {
  return {
    work: { seedProbeAttempts: 192, seedProbeBytes: 192 * 1024 ** 2, puts: 320, gets: 1728, readBytes: 1728 * 1024 ** 2, handshakes: 1280, retainedObjects: 960, loadDurationMs: 64000 },
    clientWriteBytes: 320 * 1024 ** 2, clientEgressBytes: 1920 * 1024 ** 2, peerAppliedBytes: 640 * 1024 ** 2,
    anonymous: { peakBytes: 500, cooldownBytes: 200 }, allocated: { peakBytes: 300, cooldownBytes: 100 },
    resident: { peakBytes: 400, cooldownBytes: 150 },
    transientPeakBytes: 20, transientPeakFraction: 0.1, pressureTransitions: 0, maxPressureTier: 0, capacitySheds: 0, diskBytes: 1024 ** 3, diskAllocatedBytes: 1024 ** 3,
    segmentRefreshBytes: 0, metricsBodyBytes: 1024 ** 2, cpuSecondsPerClientGiB: cpu, networkTransmitBytes: 1024 ** 3,
    networkReceiveBytes: 1024 ** 3,
  };
}

test("ABBA comparison preserves raw values, normalization and baseline spread", () => {
  const result = compare([run(5), run(9), run(11), run(7)]);
  assert.deepEqual(result.axes.cpuSecondsPerClientGiB, {
    baseline: [5, 7], candidate: [9, 11], delta: 4, baselineSpread: 2,
    percent: 100 * 4 / 6, pooledIncreaseBeyondBaselineSpread: true, increaseBeyondBaselineSpread: true,
    blocks: [{ baseline: [5, 7], candidate: [9, 11], delta: 4, baselineSpread: 2, increaseBeyondBaselineSpread: true }],
    positiveBlocks: 1, negativeBlocks: 0,
  });
  assert.equal(result.axes.allocatedDiskBytesPerWriteGiB.delta, 0);
  assert.equal(result.axes.capacitySheds.percent, null);
});

test("convergence retries remain a measured cost rather than an outcome filter", () => {
  const runs = [run(), run(), run(), run()];
  for (const [index, attempts] of [196, 197, 196, 197].entries()) {
    runs[index].work.seedProbeAttempts = attempts;
    runs[index].work.seedProbeBytes = 192 * 1024 ** 2 + (attempts - 192) * 32;
  }
  const result = compare(runs);
  assert.deepEqual(result.setupProbeWork.baseline, [[196, 201326720], [197, 201326752]]);
  assert.deepEqual(result.setupProbeWork.candidate, [[197, 201326752], [196, 201326720]]);
  runs[1].work.seedProbeAttempts++;
  runs[1].work.seedProbeBytes += 32;
  assert.equal(compare(runs).axes.seedConvergenceRetries.delta, 0.5);
  delete runs[1].work.seedProbeBytes;
  assert.throws(() => compare(runs), /setup probe work is missing/);
});

test("variant identity/order and per-block flags survive wider pooled ranges", () => {
  const runs = [run(100), run(110), run(110), run(100), run(1000), run(1000), run(3000), run(3000)];
  const result = compare(runs);
  assert.equal(result.axes.cpuSecondsPerClientGiB.pooledIncreaseBeyondBaselineSpread, false);
  assert.equal(result.axes.cpuSecondsPerClientGiB.increaseBeyondBaselineSpread, true);
  assert.equal(result.axes.cpuSecondsPerClientGiB.positiveBlocks, 1);
  const wrongOrder = run(); wrongOrder.label = "after-1";
  assert.throws(() => compare([wrongOrder, run(), run(), run()]), /ABBA order/);
  const wrongImage = run(); wrongImage.imageId = "sha256:" + "e".repeat(64);
  assert.throws(() => compare([run(), run(), run(), wrongImage]), /identity differs/);
});

test("same-image controls and mixed receipt generations cannot qualify unnoticed", () => {
  const runs = [run(), run(), run(), run()];
  runs[1].imageId = "sha256:" + "a".repeat(64);
  runs[2].imageId = runs[1].imageId;
  assert.throws(() => compare(runs), /different release images/);
  delete runs[1].imageId; delete runs[2].imageId;
  runs[1].receiptGeneration = "legacy_unversioned";
  assert.throws(() => compare(runs), /mixed or missing receipt/);
});

test("smaller changes remain visible inside baseline variation", () => {
  const result = compare([run(5), run(6), run(7), run(7)]);
  assert.equal(result.axes.cpuSecondsPerClientGiB.delta, 0.5);
  assert.equal(result.axes.cpuSecondsPerClientGiB.increaseBeyondBaselineSpread, false);
});

test("missing metrics, unequal work, nonfinite values and wrong order count refuse", () => {
  assert.throws(() => compare([run(), run()]), /four-run ABBA/);
  const repeated = compare(Array.from({ length: 12 }, () => run()));
  assert.equal(repeated.axes.peakAnonymousBytes.baseline.length, 6);
  assert.equal(repeated.axes.peakAnonymousBytes.candidate.length, 6);
  const unequal = run(); unequal.work.handshakes--;
  assert.throws(() => compare([run(), unequal, run(), run()]), /work differs/);
  const extraReads = run(); extraReads.clientEgressBytes++;
  assert.throws(() => compare([run(), extraReads, run(), run()]), /work differs/);
  const missingScrapes = run(); delete missingScrapes.metricsBodyBytes;
  assert.throws(() => compare([run(), missingScrapes, run(), run()]), /missing or invalid/);
  const missing = run(); delete missing.work.retainedObjects;
  assert.throws(() => compare([run(), missing, run(), run()]), /work is missing/);
  const metric = run(); delete metric.anonymous.cooldownBytes;
  assert.throws(() => compare([run(), metric, run(), run()]), /missing or invalid/);
  assert.throws(() => compare([run(), run(Infinity), run(), run()]), /missing or invalid/);
});
