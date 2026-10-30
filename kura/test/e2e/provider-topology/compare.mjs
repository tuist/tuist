#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";

export function compare(runs) {
  if (![4, 8, 12].includes(runs.length)) throw Error("one to three complete four-run ABBA blocks are required");
  runs.forEach((run, index) => {
    const position = index % 4;
    const variant = position === 0 || position === 3 ? "before" : "after";
    const ordinal = Math.floor(index / 4) * 2 + (position < 2 ? 1 : 2);
    if (run.label !== `${variant}-${ordinal}`) throw Error("summary labels must follow complete ABBA order");
    if (!/^sha256:[a-f0-9]{64}$/.test(run.imageId || "") || !/^[a-f0-9]{64}$/.test(run.metricsSourceSHA256 || "")) throw Error("missing image or source identity");
  });
  const receiptShape = run => [run.receiptGeneration, run.imageIdProvenance,
    run.work.seedProbeFailuresByStatus !== undefined,
    Object.entries(run.phaseMemory ?? {}).map(([name, phase]) => [name, phase.status !== "not_recorded"])];
  if (runs.some(run => ![2, "legacy_unversioned"].includes(run.receiptGeneration) || !["result", "parent_build_receipt"].includes(run.imageIdProvenance)
    || JSON.stringify(receiptShape(run)) !== JSON.stringify(receiptShape(runs[0])))) throw Error("mixed or missing receipt generations/provenance");
  if (runs[0].imageId === runs[1].imageId) throw Error("baseline and candidate must identify different release images");
  const work = runs.map(run => [run.work.puts, run.work.gets, run.work.readBytes, run.work.handshakes, run.work.retainedObjects, run.clientWriteBytes, run.peerAppliedBytes, run.clientEgressBytes]);
  if (work.some(value => value.some(number => !Number.isFinite(number) || number < 0))) throw Error("completed work is missing or invalid");
  if (work.some(value => JSON.stringify(value) !== JSON.stringify(work[0]))) throw Error("completed work differs");
  const probes = runs.map(run => [run.work.seedProbeAttempts, run.work.seedProbeBytes]);
  if (probes.some(([attempts, bytes]) => !Number.isFinite(attempts) || !Number.isInteger(attempts) || attempts < 192 || !Number.isInteger(bytes) || bytes < 192 * 1024 ** 2)) throw Error("setup probe work is missing or invalid");
  const baselineValues = values => values.filter((_, index) => index % 4 === 0 || index % 4 === 3);
  const candidateValues = values => values.filter((_, index) => index % 4 === 1 || index % 4 === 2);
  const identity = run => [run.imageId, run.metricsSourceSHA256];
  for (const group of [baselineValues(runs), candidateValues(runs)]) {
    if (group.some(run => JSON.stringify(identity(run)) !== JSON.stringify(identity(group[0])))) throw Error("variant image/source identity differs across runs");
  }
  const baselineProbes = baselineValues(probes);
  const candidateProbes = candidateValues(probes);
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
    seedConvergenceRetries: run => run.work.seedProbeAttempts - 192,
    seedConvergenceFailureBytes: run => run.work.seedProbeBytes - 192 * 1024 ** 2,
    metricsBodyBytesPerClientGiB: run => run.metricsBodyBytes / ((run.clientWriteBytes + run.clientEgressBytes) / gib),
    networkTransmitMinusMetricsBodyBytesPerClientGiB: run => (run.networkTransmitBytes - run.metricsBodyBytes) / ((run.clientWriteBytes + run.clientEgressBytes) / gib),
  };
  const result = {};
  for (const [axis, select] of Object.entries(axes)) {
    const values = runs.map(select);
    if (values.some(value => !Number.isFinite(value) || value < 0)) throw Error(`missing or invalid ${axis}`);
    const baseline = baselineValues(values);
    const candidate = candidateValues(values);
    const mean = values => values.reduce((sum, value) => sum + value, 0) / values.length;
    const delta = mean(candidate) - mean(baseline);
    const baselineSpread = Math.max(...baseline) - Math.min(...baseline);
    const blocks = [];
    for (let index = 0; index < values.length; index += 4) {
      const baseline = [values[index], values[index + 3]];
      const candidate = [values[index + 1], values[index + 2]];
      const delta = mean(candidate) - mean(baseline);
      const baselineSpread = Math.abs(baseline[0] - baseline[1]);
      blocks.push({ baseline, candidate, delta, baselineSpread, increaseBeyondBaselineSpread: delta > baselineSpread });
    }
    result[axis] = {
      baseline, candidate, delta, baselineSpread, blocks,
      positiveBlocks: blocks.filter(block => block.delta > 0).length,
      negativeBlocks: blocks.filter(block => block.delta < 0).length,
      percent: mean(baseline) ? 100 * delta / mean(baseline) : null,
      pooledIncreaseBeyondBaselineSpread: delta > baselineSpread,
      increaseBeyondBaselineSpread: delta > baselineSpread || blocks.some(block => block.increaseBeyondBaselineSpread),
    };
  }
  return {
    scope: "single-host Linux private-peer fixture; not fleet capacity or deployed native-client qualification",
    interpretation: "Positive deltas outside baseline spread require review. Completion is not an automatic budget waiver.",
    completedWork: work[0],
    identities: { baseline: identity(runs[0]), candidate: identity(runs[1]) },
    phaseMemoryByRun: runs.map(run => ({ label: run.label, phaseMemory: run.phaseMemory ?? null })),
    phaseInterpretation: "Raw data only. Phase edges are approximate to one two-second scrape; the anonymous-memory gauge can additionally be about one second stale. Unknown or unsampled windows are not zero.",
    spreadInterpretation: "Pooled ranges grow with repetitions, not statistical confidence. A pooled OR any per-block increase beyond its spread stays flagged; all blocks and sign counts are shown.",
    setupProbeWork: {
      baseline: baselineProbes, candidate: candidateProbes,
      statuses: runs.map(run => run.work.seedProbeFailuresByStatus ?? null),
      interpretation: "Retries are a measured convergence axis, not an equality filter. All failed-probe CPU and traffic remain included. Null status detail means not recorded.",
      metricsAccounting: "Both raw transmit and transmit minus stored metrics body bytes are shown. HTTP/TCP/IP overhead remains included; body subtraction is not full wire-overhead attribution.",
    },
    axes: result,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const directories = process.argv.slice(2);
  console.log(JSON.stringify(compare(directories.map(directory => JSON.parse(fs.readFileSync(path.join(directory, "summary.json"), "utf8")))), null, 2));
}
