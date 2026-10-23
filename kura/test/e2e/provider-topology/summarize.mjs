import fs from "node:fs";
import path from "node:path";

// Compare every sample, rather than hiding peaks behind the cooldown snapshot.
for (const directory of process.argv.slice(2)) {
  const result = JSON.parse(fs.readFileSync(path.join(directory, "result.json")));
  const samples = Array.from({ length: result.samples }, (_, index) =>
    [4291, 4292, 4293].map((port) => {
      const metrics = new Map();
      const counters = new Set();
      for (const line of fs.readFileSync(path.join(directory, `${index}-${port}.prom`), "utf8").split("\n")) {
        const type = line.match(/^# TYPE (\w+) counter$/);
        if (type) counters.add(type[1] + "_total");
        if (!line || line.startsWith("#")) continue;
        const match = line.match(/^(\w+)(?:\{.*\})? ([\d.e+-]+)$/);
        if (match) metrics.set(match[1], (metrics.get(match[1]) || 0) + Number(match[2]));
      }
      for (const required of ["kura_process_resident_anon_bytes", "kura_jemalloc_allocated_bytes", "kura_jemalloc_resident_bytes", "kura_memory_pressure_state", "kura_memory_transient_reserved_bytes", "kura_memory_transient_capacity_bytes", "kura_memory_pressure_transitions_total_total", "kura_capacity_sheds_total_total", "kura_artifact_write_bytes_total_total", "kura_artifact_egress_bytes_total_total", "kura_backfill_applied_bytes_total_total", "kura_segment_refresh_bytes_total_total"]) {
        if (!metrics.has(required) && counters.has(required)) metrics.set(required, 0);
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
  if (result.stats.failures.length || result.stats.handshakes !== 1280 || result.stats.retainedObjects !== 960 || writes !== 320 * 1024 ** 2 || replicated !== writes * 2) {
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
  const summary = {
    directory,
    work: result.stats,
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
