import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { compare } from "./compare.mjs";
import { knownLazyCounters } from "./metric-schema.mjs";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("./summarize.mjs", import.meta.url));
function fixture(run) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "kura-resource-summary-"));
  try {
    const host = { processCpu: "1 (kura) " + ["S", ...Array(10).fill("0"), "100", "50"].join(" ") + "\n100\n", disk: "100 /data", diskAllocated: "4096 /data", net: "eth0: 100 0 0 0 0 0 0 0 200 0 0 0 0 0 0 0" };
    const result = { schemaVersion: 2, label: "before-1", imageId: "sha256:" + "a".repeat(64), samples: 2, before: [host, host, host], after: [host, host, { ...host, net: "eth0: 100 0 0 0 0 0 0 0 1048576 0 0 0 0 0 0 0" }], stats: { loadStartSample: 1, loadEndSample: 2, retentionStartSample: 2, retentionEndSample: 2, seedProbeSuccesses: 192, seedProbeSuccessBytes: 192 * 1024 ** 2, seedProbeFailuresByStatus: {}, seedProbeAttempts: 192, seedProbeBytes: 192 * 1024 ** 2, failures: [], handshakes: 1280, retainedObjects: 960, puts: 320, gets: 1728, readBytes: 1728 * 1024 ** 2, loadDurationMs: 64000 } };
    const source = fs.readFileSync(new URL("../../../src/metrics.rs", import.meta.url), "utf8");
    result.knownLazyCounters = knownLazyCounters(source);
    result.metricsSourceSHA256 = createHash("sha256").update(source).digest("hex");
    fs.writeFileSync(path.join(directory, "result.json"), JSON.stringify(result));
    for (const index of [0, 1]) for (const port of [4291, 4292, 4293]) {
      const metrics = [
        "kura_process_resident_anon_bytes 100", "kura_jemalloc_allocated_bytes 50",
        "kura_jemalloc_resident_bytes 80", "kura_memory_pressure_state 0",
        "kura_memory_transient_reserved_bytes 0", "kura_memory_transient_capacity_bytes 100",
        "# TYPE kura_memory_pressure_transitions_total counter", "kura_capacity_sheds_total_total 0",
        `kura_artifact_write_bytes_total_total ${index && port === 4291 ? 320 * 1024 ** 2 : 0}`,
        `kura_artifact_egress_bytes_total_total ${index && port === 4291 ? 1920 * 1024 ** 2 : 0}`,
        `kura_backfill_applied_bytes_total_total ${index && port !== 4291 ? 320 * 1024 ** 2 : 0}`,
        // An exported empty counter family is known zero, not a missing metric.
        "# TYPE kura_segment_refresh_bytes_total counter",
      ];
      fs.writeFileSync(path.join(directory, `${index}-${port}.prom`), metrics.join("\n") + "\n");
    }
    run(directory);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
}

test("summaries retain simultaneous memory and declared empty counters", () => fixture(directory => {
  execFileSync(process.execPath, [script, directory]);
  const result = JSON.parse(fs.readFileSync(path.join(directory, "summary.json"), "utf8"));
  assert.equal(result.anonymous.peakBytes, 300);
  assert.equal(result.anonymous.cooldownBytes, 300);
  assert.equal(result.segmentRefreshBytes, 0);
  const bodyBytes = fs.readdirSync(directory).filter(file => file.endsWith(".prom") && !file.startsWith("0-")).reduce((sum, file) => sum + fs.statSync(path.join(directory, file)).size, 0);
  assert.equal(result.metricsBodyBytes, bodyBytes);
  assert.equal(result.phaseMemory.seed.anonymousPeakBytes, 300);
  assert.deepEqual(result.phaseMemory.load.perNodeAnonymousPeakBytes, [100, 100, 100]);
  assert.equal(result.phaseMemory.retention.status, "not_sampled");
  assert.equal(result.phaseMemory.retention.measurements, null);
  const runs = ["before-1", "after-1", "after-2", "before-2"].map(label => ({ ...result, label, imageId: "sha256:" + (label.startsWith("before-") ? "a" : "b").repeat(64) }));
  assert.equal(compare(runs).axes.peakAnonymousBytes.delta, 0);
}));

test("unknown metrics cannot silently become zero", () => fixture(directory => {
  const filename = path.join(directory, "0-4291.prom");
  fs.writeFileSync(filename, fs.readFileSync(filename, "utf8").replace("kura_jemalloc_allocated_bytes 50\n", ""));
  const result = spawnSync(process.execPath, [script, directory], { encoding: "utf8" });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /missing kura_jemalloc_allocated_bytes/);
}));

test("source-verified lazy families can be empty without weakening unknown metrics", () => fixture(directory => {
  const source = fs.readFileSync(new URL("../../../src/metrics.rs", import.meta.url), "utf8");
  const filename = path.join(directory, "result.json");
  const result = JSON.parse(fs.readFileSync(filename, "utf8"));
  result.knownLazyCounters = knownLazyCounters(source);
  result.metricsSourceSHA256 = createHash("sha256").update(source).digest("hex");
  fs.writeFileSync(filename, JSON.stringify(result));
  for (const file of fs.readdirSync(directory).filter(file => file.endsWith(".prom"))) {
    const name = path.join(directory, file);
    let text = fs.readFileSync(name, "utf8").replace(/^# TYPE kura_(?:memory_pressure_transitions|artifact_egress_bytes|segment_refresh_bytes)_total counter\n/gm, "");
    if (file.startsWith("0-")) text = text.replace(/^kura_artifact_egress_bytes_total_total .*\n/gm, "");
    fs.writeFileSync(name, text);
  }
  execFileSync(process.execPath, [script, directory]);
  const summary = JSON.parse(fs.readFileSync(path.join(directory, "summary.json"), "utf8"));
  assert.equal(summary.pressureTransitions, 0);
  assert.equal(summary.segmentRefreshBytes, 0);
  const metricFile = path.join(directory, "0-4291.prom");
  fs.writeFileSync(metricFile, fs.readFileSync(metricFile, "utf8").replace("kura_jemalloc_allocated_bytes 50\n", ""));
  const failed = spawnSync(process.execPath, [script, directory], { encoding: "utf8" });
  assert.notEqual(failed.status, 0);
  assert.match(failed.stderr, /missing kura_jemalloc_allocated_bytes/);
}));

test("incorrect probe successes, status accounting or phase boundaries refuse", () => fixture(directory => {
  const filename = path.join(directory, "result.json");
  const result = JSON.parse(fs.readFileSync(filename, "utf8"));
  result.stats.seedProbeSuccesses--;
  fs.writeFileSync(filename, JSON.stringify(result));
  assert.notEqual(spawnSync(process.execPath, [script, directory]).status, 0);
  result.stats.seedProbeSuccesses++;
  result.stats.seedProbeFailuresByStatus[404] = 1;
  fs.writeFileSync(filename, JSON.stringify(result));
  assert.notEqual(spawnSync(process.execPath, [script, directory]).status, 0);
  result.stats.seedProbeFailuresByStatus = {};
  result.stats.loadStartSample = -1;
  fs.writeFileSync(filename, JSON.stringify(result));
  assert.notEqual(spawnSync(process.execPath, [script, directory]).status, 0);
}));

test("a TYPE declaration cannot zero an unqualified counter or change metric kind", () => fixture(directory => {
  const filename = path.join(directory, "0-4291.prom");
  const original = fs.readFileSync(filename, "utf8");
  fs.writeFileSync(filename, original.replace("kura_capacity_sheds_total_total 0", "# TYPE kura_capacity_sheds_total counter"));
  let child = spawnSync(process.execPath, [script, directory], { encoding: "utf8" });
  assert.notEqual(child.status, 0);
  assert.match(child.stderr, /missing kura_capacity_sheds/);
  fs.writeFileSync(filename, original.replace("kura_memory_pressure_transitions_total counter", "kura_memory_pressure_transitions_total gauge"));
  child = spawnSync(process.execPath, [script, directory], { encoding: "utf8" });
  assert.notEqual(child.status, 0);
  assert.match(child.stderr, /wrong type/);
}));

test("incomplete handshake or retained-corpus work refuses", () => fixture(directory => {
  const filename = path.join(directory, "result.json");
  const result = JSON.parse(fs.readFileSync(filename, "utf8"));
  result.stats.retainedObjects--;
  fs.writeFileSync(filename, JSON.stringify(result));
  const child = spawnSync(process.execPath, [script, directory], { encoding: "utf8" });
  assert.notEqual(child.status, 0);
  assert.match(child.stderr, /incomplete work or replication/);
}));
