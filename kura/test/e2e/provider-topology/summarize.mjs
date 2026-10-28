import fs from "node:fs";
import path from "node:path";

// Compare every sample, rather than hiding peaks behind the cooldown snapshot.
for (const directory of process.argv.slice(2)) {
  const result = JSON.parse(fs.readFileSync(path.join(directory, "result.json")));
  const samples = Array.from({ length: result.samples }, (_, index) =>
    [4291, 4292, 4293].map((port) => {
      const metrics = new Map();
      for (const line of fs.readFileSync(path.join(directory, `${index}-${port}.prom`), "utf8").split("\n")) {
        if (!line || line.startsWith("#")) continue;
        const match = line.match(/^(\w+)(?:\{.*\})? ([\d.e+-]+)$/);
        if (match) metrics.set(match[1], (metrics.get(match[1]) || 0) + Number(match[2]));
      }
      for (const required of ["kura_process_resident_anon_bytes", "kura_jemalloc_allocated_bytes", "kura_memory_pressure_state", "kura_backfill_applied_bytes_total_total"]) {
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
  const transmitBytes = (nodes) => nodes.reduce((sum, node) => {
    const line = node.net.split("\n").find((entry) => entry.includes("eth0:"));
    if (!line) throw Error("missing eth0 counters");
    return sum + Number(line.split(":")[1].trim().split(/\s+/)[8]);
  }, 0);
  const diskBytes = (nodes) => nodes.reduce((sum, node) => sum + Number(node.disk.split(/\s+/)[0]), 0);
  const cpu = cpuSeconds(result.after) - cpuSeconds(result.before);
  const writes = delta("kura_artifact_write_bytes_total_total");
  const reads = delta("kura_artifact_egress_bytes_total_total");
  const replicated = delta("kura_backfill_applied_bytes_total_total");
  if (result.stats.failures.length || writes !== 320 * 1024 ** 2 || replicated !== writes * 2) {
    throw Error(`incomplete work or replication: ${directory}`);
  }
  console.log(JSON.stringify({
    directory,
    work: result.stats,
    cpuSeconds: cpu,
    cpuSecondsPerClientGiB: cpu / ((writes + reads) / 1024 ** 3),
    anonymous: memory("kura_process_resident_anon_bytes"),
    allocated: memory("kura_jemalloc_allocated_bytes"),
    resident: memory("kura_jemalloc_resident_bytes"),
    maxPressureTier: Math.max(...samples.flatMap((sample) => sample.map((node) => node.get("kura_memory_pressure_state") || 0))),
    capacitySheds: delta("kura_capacity_sheds_total_total"),
    transientPeakBytes: peak("kura_memory_transient_reserved_bytes"),
    diskBytes: diskBytes(result.after),
    segmentRefreshBytes: delta("kura_segment_refresh_bytes_total_total"),
    clientWriteBytes: writes,
    clientEgressBytes: reads,
    peerAppliedBytes: replicated,
    networkTransmitBytes: transmitBytes(result.after) - transmitBytes(result.before),
  }, null, 2));
}
