import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";
import { knownLazyCounters } from "./metric-schema.mjs";

const source = fs.readFileSync(new URL("../../../src/metrics.rs", import.meta.url), "utf8");
test("only source-verified registered lazy Counter families qualify", () => {
  assert.deepEqual(knownLazyCounters(source), ["kura_memory_pressure_transitions_total_total", "kura_artifact_egress_bytes_total_total", "kura_segment_refresh_bytes_total_total"]);
  assert.throws(() => knownLazyCounters(source.replace('"kura_memory_pressure_transitions_total"', '"renamed_counter"')), /unqualified lazy counter/);
  assert.throws(() => knownLazyCounters(source.replaceAll("Family::<SegmentRefreshLabels, Counter>", "Family::<SegmentRefreshLabels, Gauge>")), /unqualified lazy counter/);
});
