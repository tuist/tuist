#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

export function compare(runs) {
  if (runs.length !== 4) throw Error("four ABBA summaries are required");
  const work = runs.map(run => [run.work.puts, run.work.gets, run.work.readBytes, run.work.handshakes, run.work.retainedObjects, run.clientWriteBytes, run.peerAppliedBytes, run.work.seedProbeAttempts, run.work.seedProbeBytes, run.clientEgressBytes]);
  if (work.some(value => value.some(number => !Number.isFinite(number) || number < 0))) throw Error("completed work is missing or invalid");
  if (work.some(value => JSON.stringify(value) !== JSON.stringify(work[0]))) throw Error("completed work differs");
  const gib = 1024 ** 3;
  const axes = {
    peakAnonymousBytes: run => run.anonymous.peakBytes,
    cooldownAnonymousBytes: run => run.anonymous.cooldownBytes,
    peakAllocatedBytes: run => run.allocated.peakBytes,
    cooldownAllocatedBytes: run => run.allocated.cooldownBytes,
    peakResidentBytes: run => run.resident.peakBytes,
    cooldownResidentBytes: run => run.resident.cooldownBytes,
    transientPeakBytes: run => run.transientPeakBytes,
    maxPressure: run => run.maxPressureTier,
    pressureTransitions: run => run.pressureTransitions,
    transientPeakFraction: run => run.transientPeakFraction,
    capacitySheds: run => run.capacitySheds,
    logicalDiskBytesPerWriteGiB: run => run.diskBytes / (run.clientWriteBytes / gib),
    allocatedDiskBytesPerWriteGiB: run => run.diskAllocatedBytes / (run.clientWriteBytes / gib),
    refreshBytesPerWriteGiB: run => run.segmentRefreshBytes / (run.clientWriteBytes / gib),
    cpuSecondsPerClientGiB: run => run.cpuSecondsPerClientGiB,
    networkTransmitBytesPerClientGiB: run => run.networkTransmitBytes / ((run.clientWriteBytes + run.clientEgressBytes) / gib),
    networkReceiveBytesPerClientGiB: run => run.networkReceiveBytes / ((run.clientWriteBytes + run.clientEgressBytes) / gib),
    loadDurationMs: run => run.work.loadDurationMs,
  };
  const result = {};
  for (const [axis, select] of Object.entries(axes)) {
    const values = runs.map(select);
    if (values.some(value => !Number.isFinite(value) || value < 0)) throw Error(`missing or invalid ${axis}`);
    const baseline = [values[0], values[3]];
    const candidate = [values[1], values[2]];
    const mean = values => (values[0] + values[1]) / 2;
    const delta = mean(candidate) - mean(baseline);
    const baselineSpread = Math.abs(baseline[0] - baseline[1]);
    result[axis] = {
      baseline, candidate, delta, baselineSpread,
      percent: mean(baseline) ? 100 * delta / mean(baseline) : null,
      increaseBeyondBaselineSpread: delta > baselineSpread,
    };
  }
  return {
    scope: "single-host Linux private-peer fixture; not fleet capacity or deployed native-client qualification",
    interpretation: "Positive deltas outside baseline spread require review. Completion is not an automatic budget waiver.",
    completedWork: work[0], axes: result,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const directories = process.argv.slice(2);
  console.log(JSON.stringify(compare(directories.map(directory => JSON.parse(fs.readFileSync(path.join(directory, "summary.json"), "utf8")))), null, 2));
}
