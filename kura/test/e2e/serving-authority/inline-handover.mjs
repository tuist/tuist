import fs from "node:fs";
import assert from "node:assert/strict";
import { setTimeout as sleep } from "node:timers/promises";
import { fixture, handover } from "./fixture.mjs";

const [image, output] = process.argv.slice(2);
assert(image && output, "usage: inline-handover.mjs IMAGE OUTPUT_DIR");
const f = await fixture(image, "active", output, { backfillBatchBytes: 1024 });
const value = "retained-inline-metadata-".repeat(256);
const query = "?tenant_id=default&namespace_id=inline-handover";
const count = Number(process.env.KURA_E2E_INLINE_RECORDS ?? 64);
assert(Number.isInteger(count) && count > 0 && count <= 2048);
const samples = [];
let collecting = true;
const collector = (async () => {
  while (collecting) {
    samples.push({
      time: Date.now(),
      metrics: await Promise.all([0, 1].map(f.metric)),
    });
    await sleep(2000);
  }
})();
const result = { image, count, before: f.snapshot() };
try {
  const start = Date.now();
  for (let i = 0; i < count; i++) {
    const response = await fetch(`${f.urls[0]}/api/cache/keyvalue${query}`, {
      method: "PUT",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ cas_id: `inline-${i}`, entries: [{ value }] }),
      signal: AbortSignal.timeout(10000),
    });
    assert.equal(response.status, 204);
    if (process.env.KURA_E2E_INLINE_INTERVAL_MS)
      await sleep(Number(process.env.KURA_E2E_INLINE_INTERVAL_MS));
  }
  result.loadSeconds = (Date.now() - start) / 1000;
  result.loadEnd = f.snapshot();
  await sleep(10000);
  result.settled = f.snapshot();
  const barrier = await handover(f, { deadlineMs: 30000 });
  assert(
    barrier,
    "individual inline metadata did not satisfy retained-corpus verification",
  );
  for (let i = 0; i < count; i++) {
    const response = await fetch(
      `${f.urls[1]}/api/cache/keyvalue/inline-${i}${query}`,
    );
    assert.equal(response.status, 200);
    assert.equal((await response.json()).entries[0].value, value);
  }
  result.individualInlineHandover = true;
  result.barrier = barrier;
  console.log(JSON.stringify({ individualInlineHandover: true, count }));
} catch (error) {
  result.error = error.message;
  throw error;
} finally {
  collecting = false;
  await collector;
  result.after = f.snapshot();
  result.samples = samples;
  fs.writeFileSync(`${output}/result.json`, JSON.stringify(result, null, 2));
  f.close();
}
