import fs from "node:fs";
import assert from "node:assert/strict";

const [directory] = process.argv.slice(2);
assert(directory, "usage: summarize.mjs OUTPUT_DIR");
const read = (name) => fs.readFileSync(`${directory}/${name}`, "utf8");
const lines = (name) =>
  fs.existsSync(`${directory}/${name}`)
    ? read(name).trim().split("\n").filter(Boolean).map(JSON.parse)
    : [];
const result = JSON.parse(read("result.json"));
const samples = lines("metrics.jsonl"),
  resources = lines("resources.jsonl"),
  proxy = lines("proxy.jsonl");
const metric = (text, name) => {
  const line = text.split("\n").find((l) => l.startsWith(`${name} `));
  return line ? Number(line.slice(name.length + 1)) : null;
};
const metrics = [
  "kura_process_resident_anon_bytes",
  "kura_jemalloc_allocated_bytes",
  "kura_jemalloc_resident_bytes",
  "kura_memory_pressure_state",
  "kura_backfill_applied_bytes_total_total",
];
const measured = resources.filter((sample) =>
  ["before", "handover", "settled"].includes(sample.phase),
);
const stat = (text, key) =>
  Number(text.match(new RegExp("^" + key + " ([0-9]+)", "m"))?.[1] ?? NaN);
function resourceSummary(i) {
  if (!measured.length)
    return { unavailable: true, preparationSamples: resources.length };
  const first = measured[0].replicas[i],
    last = measured.at(-1).replicas[i];
  const disk = (row) => Number(row.disk.split(/\s/)[0]) * 1024;
  return {
    sampleStart: measured[0].time,
    sampleEnd: measured.at(-1).time,
    cpuSeconds:
      (stat(last.cpu, "usage_usec") - stat(first.cpu, "usage_usec")) / 1e6,
    throttledSeconds:
      (stat(last.cpu, "throttled_usec") - stat(first.cpu, "throttled_usec")) /
      1e6,
    diskBytesBefore: disk(first),
    diskBytesAfter: disk(last),
    diskBytesPeak: Math.max(...measured.map((r) => disk(r.replicas[i]))),
    anonymousBytesPeak: Math.max(
      ...measured.map((r) => stat(r.replicas[i].memory, "anon")),
    ),
    fileBytesPeak: Math.max(
      ...measured.map((r) => stat(r.replicas[i].memory, "file")),
    ),
    preparationSamples: resources.length - measured.length,
  };
}
const summary = {
  profile: result.profile,
  scenario: result.scenario,
  classification: result.classification ?? "unclassified",
  handoverMs: result.handoverMs,
  deadlineMs: 300000,
  shape: result.shape,
  error: result.error,
  sourceResumed: result.sourceResumed,
  persistentChannelChecks: result.persistentChannelChecks,
  requestTimeouts: result.requestTimeouts,
  repairRevisits: result.repairRevisits,
  replicas: [0, 1].map((i) => ({
    name: i === 0 ? "source" : "target",
    metrics: Object.fromEntries(
      metrics.map((name) => {
        const values = samples
          .map((sample) => metric(sample.metrics[i], name))
          .filter((v) => v !== null);
        return [
          name,
          values.length
            ? {
                first: values[0],
                last: values.at(-1),
                peak: Math.max(...values),
                delta: values.at(-1) - values[0],
              }
            : { unavailable: true },
        ];
      }),
    ),
    resources: resourceSummary(i),
  })),
  peerResponses: {
    bodyBytes: proxy
      .filter((r) => /backfill\/(artifacts\/|bodies)/.test(r.route))
      .reduce((sum, r) => sum + r.bytes, 0),
    count: proxy.length,
    bytes: proxy.reduce((sum, r) => sum + r.bytes, 0),
    incomplete: proxy.filter((r) => !r.completed).length,
  },
  cleanup: fs.existsSync(`${directory}/cleanup.json`)
    ? JSON.parse(read("cleanup.json"))
    : "not recorded",
  reclamation: fs.existsSync(`${directory}/reclamation.json`)
    ? JSON.parse(read("reclamation.json"))
    : "not recorded",
};
const repair =
  summary.replicas[1].metrics.kura_backfill_applied_bytes_total_total;
summary.repair = {
  minimumTransferSecondsAtConfiguredCap:
    result.shape?.missingBytes === undefined
      ? null
      : result.shape.missingBytes / 62500000,
  appliedBytes: repair.unavailable ? null : repair.delta,
  amplificationOverInitiallyMissingBytes:
    !result.shape?.missingBytes || repair.unavailable
      ? null
      : repair.delta / result.shape.missingBytes,
  deadlineHeadroomMs: result.barrier ? 300000 - result.handoverMs : null,
};
fs.writeFileSync(`${directory}/summary.json`, JSON.stringify(summary, null, 2));
console.log(JSON.stringify(summary, null, 2));
