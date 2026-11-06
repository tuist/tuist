import fs from "node:fs";
import path from "node:path";
import { lazyCounterNames } from "./metric-schema.mjs";

// Compare every sample, rather than hiding peaks behind the cooldown snapshot.
for (const directory of process.argv.slice(2)) {
  const result = JSON.parse(fs.readFileSync(path.join(directory, "result.json")));
  if (result.schemaVersion !== undefined && result.schemaVersion !== 2) throw Error("unsupported receipt generation");
  if (result.schemaVersion === 2 && ["seedProbeSuccesses", "seedProbeSuccessBytes", "seedProbeFailuresByStatus", "loadStartSample", "loadEndSample", "retentionStartSample", "retentionEndSample"].some(key => !Object.hasOwn(result.stats, key))) throw Error("incomplete current receipt generation");
  let metricsBodyBytes = 0;
  const samples = Array.from({ length: result.samples }, (_, index) =>
    [4291, 4292, 4293].map((port) => {
      const metrics = new Map();
      const types = new Map();
      const text = fs.readFileSync(path.join(directory, `${index}-${port}.prom`), "utf8");
      // Sample zero precedes the interface-counter baseline; do not subtract it.
      if (index > 0) metricsBodyBytes += Buffer.byteLength(text, "utf8");
      for (const line of text.split("\n")) {
        const type = line.match(/^# TYPE (\w+) (\w+)$/);
        if (type) types.set(type[1], type[2]);
        if (!line || line.startsWith("#")) continue;
        const match = line.match(/^(\w+)(?:\{.*\})? ([\d.e+-]+)$/);
        if (match) metrics.set(match[1], (metrics.get(match[1]) || 0) + Number(match[2]));
      }
      for (const required of ["kura_process_resident_anon_bytes", "kura_jemalloc_allocated_bytes", "kura_jemalloc_resident_bytes", "kura_memory_pressure_state", "kura_memory_transient_reserved_bytes", "kura_memory_transient_capacity_bytes", "kura_memory_pressure_transitions_total_total", "kura_capacity_sheds_total_total", "kura_artifact_write_bytes_total_total", "kura_artifact_egress_bytes_total_total", "kura_backfill_applied_bytes_total_total", "kura_segment_refresh_bytes_total_total"]) {
        const sourceVerifiedEmptyFamily = lazyCounterNames.includes(required)
          && /^[a-f0-9]{64}$/.test(result.metricsSourceSHA256 || "")
          && result.knownLazyCounters?.includes(required);
        const counter = required.endsWith("_total_total");
        const declared = types.get(counter ? required.slice(0, -6) : required);
        if (declared !== undefined && declared !== (counter ? "counter" : "gauge")) throw Error(`wrong type for ${required}`);
        if (!metrics.has(required) && sourceVerifiedEmptyFamily) metrics.set(required, 0);
        if (!metrics.has(required)) throw Error(`missing ${required} at ${index}/${port}`);
      }
      return metrics;
    }),
  );
  const total = (sample, name) => sample.reduce((sum, node) => sum + (node.get(name) || 0), 0);
  const peak = (name) => Math.max(...samples.map((sample) => total(sample, name)));
  const delta = (name) => total(samples.at(-1), name) - total(samples[0], name);
  const memory = (name) => ({
    peakBytes: peak(name),
    cooldownBytes: total(samples.at(-1), name),
  });
  const phase = (begin, end) => {
    if (begin === undefined || end === undefined) return { status: "not_recorded", measurements: null };
    if (![begin, end].every(Number.isInteger) || begin < 0 || end < begin || end > samples.length) throw Error("invalid phase boundaries");
    if (begin === end) return { status: "not_sampled", sampleRange: [begin, end], measurements: null };
    const window = samples.slice(begin, end);
    const max = name => Math.max(...window.map(sample => total(sample, name)));
    return {
      status: "sampled", sampleRange: [begin, end], anonymousPeakBytes: max("kura_process_resident_anon_bytes"),
      allocatedPeakBytes: max("kura_jemalloc_allocated_bytes"), residentPeakBytes: max("kura_jemalloc_resident_bytes"),
      perNodeAnonymousPeakBytes: [0, 1, 2].map(node => Math.max(...window.map(sample => sample[node].get("kura_process_resident_anon_bytes")))),
    };
  };
  const cpuSeconds = (nodes) => nodes.reduce((sum, node) => {
    const [stat, frequency] = node.processCpu.trim().split("\n");
    const fields = stat.slice(stat.lastIndexOf(")") + 2).split(" ");
    return sum + (Number(fields[11]) + Number(fields[12])) / Number(frequency);
  }, 0);
  const interfaceBytes = (nodes, field) => nodes.reduce((sum, node) => {
    const line = node.net.split("\n").find((entry) => entry.includes("eth0:"));
    if (!line) throw Error("missing eth0 counters");
    return sum + Number(line.split(":")[1].trim().split(/\s+/)[field]);
  }, 0);
  const diskBytes = (nodes, field) => nodes.reduce((sum, node) => sum + Number(node[field].split(/\s+/)[0]), 0);
  const cpu = cpuSeconds(result.after) - cpuSeconds(result.before);
  const writes = delta("kura_artifact_write_bytes_total_total");
  const reads = delta("kura_artifact_egress_bytes_total_total");
  const replicated = delta("kura_backfill_applied_bytes_total_total");
  if (result.stats.failures.length || result.stats.handshakes !== 1280 || result.stats.retainedObjects !== 960
      || result.stats.puts !== 320 || result.stats.gets !== 1728 || result.stats.readBytes !== 1728 * 1024 ** 2
      || !Number.isInteger(result.stats.seedProbeAttempts) || result.stats.seedProbeAttempts < 192
      || !Number.isInteger(result.stats.seedProbeBytes) || result.stats.seedProbeBytes < 192 * 1024 ** 2
      || (result.stats.seedProbeSuccesses !== undefined && result.stats.seedProbeSuccesses !== 192)
      || (result.stats.seedProbeSuccessBytes !== undefined && result.stats.seedProbeSuccessBytes !== 192 * 1024 ** 2)
      || (result.stats.seedProbeFailuresByStatus !== undefined && (Object.values(result.stats.seedProbeFailuresByStatus).some(n => !Number.isInteger(n) || n < 0)
        || Object.values(result.stats.seedProbeFailuresByStatus).reduce((sum, n) => sum + n, 0) !== result.stats.seedProbeAttempts - 192))
      || reads !== 1920 * 1024 ** 2 || writes !== 320 * 1024 ** 2 || replicated !== writes * 2) {
    throw Error(`incomplete work or replication: ${directory}`);
  }
  const transientCapacityBytes = total(samples.at(-1), "kura_memory_transient_capacity_bytes");
  if (!(transientCapacityBytes > 0)) throw Error("missing positive transient capacity");
  const transientPeakFraction = Math.max(...samples.flatMap(sample => sample.map(node => {
    const reserved = node.get("kura_memory_transient_reserved_bytes");
    const capacity = node.get("kura_memory_transient_capacity_bytes");
    if (!capacity && reserved) throw Error("reservation without measured capacity");
    return capacity ? reserved / capacity : 0;
  })));
  const label = result.label ?? path.basename(directory);
  const variant = label.startsWith("before-") ? "baseline" : "candidate";
  const parentImageReceipt = path.join(path.dirname(directory), `${variant}-image-id.txt`);
  const imageId = result.imageId ?? (fs.existsSync(parentImageReceipt) ? fs.readFileSync(parentImageReceipt, "utf8").trim() : null);
  const summary = {
    directory, label, imageId, metricsSourceSHA256: result.metricsSourceSHA256,
    imageIdProvenance: result.imageId ? "result" : (imageId ? "parent_build_receipt" : "not_recorded"),
    receiptGeneration: result.schemaVersion ?? "legacy_unversioned",
    work: result.stats,
    metricsBodyBytes,
    phaseMemory: {
      seed: phase(0, result.stats.loadStartSample),
      load: phase(result.stats.loadStartSample, result.stats.loadEndSample),
      firstCooldown: phase(result.stats.loadEndSample, result.stats.retentionStartSample),
      retention: phase(result.stats.retentionStartSample, result.stats.retentionEndSample),
      finalCooldown: phase(result.stats.retentionEndSample, samples.length),
    },
    cpuSeconds: cpu,
    cpuSecondsPerClientGiB: cpu / ((writes + reads) / 1024 ** 3),
    anonymous: memory("kura_process_resident_anon_bytes"),
    allocated: memory("kura_jemalloc_allocated_bytes"),
    resident: memory("kura_jemalloc_resident_bytes"),
    maxPressureTier: Math.max(...samples.flatMap((sample) => sample.map((node) => node.get("kura_memory_pressure_state") || 0))),
    capacitySheds: delta("kura_capacity_sheds_total_total"),
    pressureTransitions: delta("kura_memory_pressure_transitions_total_total"),
    transientCapacityBytes,
    transientPeakFraction,
    transientPeakBytes: peak("kura_memory_transient_reserved_bytes"),
    diskBytes: diskBytes(result.after, "disk"),
    diskAllocatedBytes: diskBytes(result.after, "diskAllocated"),
    segmentRefreshBytes: delta("kura_segment_refresh_bytes_total_total"),
    clientWriteBytes: writes,
    clientEgressBytes: reads,
    peerAppliedBytes: replicated,
    networkTransmitBytes: interfaceBytes(result.after, 8) - interfaceBytes(result.before, 8),
    networkReceiveBytes: interfaceBytes(result.after, 0) - interfaceBytes(result.before, 0),
  };
  fs.writeFileSync(path.join(directory, "summary.json"), JSON.stringify(summary, null, 2) + "\n");
  console.log(JSON.stringify(summary, null, 2));
}
