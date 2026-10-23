import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { compare } from "./compare.mjs";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("./summarize.mjs", import.meta.url));
function fixture(run) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "kura-resource-summary-"));
  try {
    const host = { processCpu: "1 (kura) " + ["S", ...Array(10).fill("0"), "100", "50"].join(" ") + "\n100\n", disk: "100 /data", diskAllocated: "4096 /data", net: "eth0: 100 0 0 0 0 0 0 0 200 0 0 0 0 0 0 0" };
    const result = { samples: 2, before: [host, host, host], after: [host, host, host], stats: { failures: [], handshakes: 1280, retainedObjects: 960, puts: 320, gets: 1728, readBytes: 1728 * 1024 ** 2, loadDurationMs: 64000 } };
    fs.writeFileSync(path.join(directory, "result.json"), JSON.stringify(result));
    for (const index of [0, 1]) for (const port of [4291, 4292, 4293]) {
      const metrics = [
        "kura_process_resident_anon_bytes 100", "kura_jemalloc_allocated_bytes 50",
        "kura_jemalloc_resident_bytes 80", "kura_memory_pressure_state 0",
        "kura_memory_transient_reserved_bytes 0", "kura_memory_transient_capacity_bytes 100",
        "# TYPE kura_memory_pressure_transitions_total counter", "kura_capacity_sheds_total_total 0",
        `kura_artifact_write_bytes_total_total ${index && port === 4291 ? 320 * 1024 ** 2 : 0}`,
        "kura_artifact_egress_bytes_total_total 100",
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
  assert.equal(compare([result, result, result, result]).axes.peakAnonymousBytes.delta, 0);
}));

test("unknown metrics cannot silently become zero", () => fixture(directory => {
  const filename = path.join(directory, "0-4291.prom");
  fs.writeFileSync(filename, fs.readFileSync(filename, "utf8").replace("# TYPE kura_segment_refresh_bytes_total counter\n", ""));
  const result = spawnSync(process.execPath, [script, directory], { encoding: "utf8" });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /missing kura_segment_refresh_bytes/);
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
