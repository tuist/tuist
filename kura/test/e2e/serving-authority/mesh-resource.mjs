import fs from "node:fs";
import assert from "node:assert/strict";
import { setTimeout as sleep } from "node:timers/promises";
import { fixture, handover } from "./fixture.mjs";

const [image, mode, output] = process.argv.slice(2);
if (!image || !["legacy", "active"].includes(mode) || !output)
  throw new Error("usage: mesh-resource.mjs IMAGE legacy|active OUTPUT_DIR");
fs.mkdirSync(output, { recursive: true });
const f = await fixture(image, mode, output);
const { urls, snapshot, metric } = f;
let sampling = false,
  collector,
  collectorError;
try {
  const body = Buffer.alloc(1024 * 1024, 71),
    stats = { writes: 0, reads: 0, readBytes: 0 };
  const keyURL = (i, key) =>
    `${urls[i]}/api/cache/cas/${key}?tenant_id=default&namespace_id=mesh-resource`;
  async function put(key) {
    const r = await fetch(keyURL(0, key), {
      method: "POST",
      body,
      signal: AbortSignal.timeout(30000),
    });
    await r.arrayBuffer();
    assert.equal(r.status, 204);
    stats.writes++;
  }
  async function get(i, key) {
    const r = await fetch(keyURL(i, key), {
      signal: AbortSignal.timeout(30000),
    });
    const b = Buffer.from(await r.arrayBuffer());
    assert.equal(r.status, 200);
    assert(b.equals(body));
    stats.reads++;
    stats.readBytes += b.length;
  }
  for (let i = 0; i < 128; i++) await put(`seed-${i}`);
  // A standby has no public serving authority. Its applied feed cursor is
  // observed instead; retained bytes are read publicly after named handover.
  await sleep(5000);
  const before = snapshot(),
    samples = [];
  sampling = true;
  collector = (async () => {
    while (sampling) {
      samples.push({
        time: Date.now(),
        metrics: await Promise.all([0, 1].map(metric)),
      });
      await sleep(2000);
    }
  })().catch((error) => {
    collectorError = error;
  });
  const start = Date.now();
  await Promise.all(
    [0, 1, 2, 3].map(async (worker) => {
      for (let i = 0; i < 240; i++) {
        await sleep(Math.max(0, start + i * 500 - Date.now()));
        await put(`load-${worker}-${i}`);
        await get(0, `seed-${(i + worker) % 128}`);
      }
    }),
  );
  const loadEnd = snapshot(),
    loadEnded = Date.now();
  await sleep(20000);
  const handoverStart = Date.now();
  if (mode === "active") assert(await handover(f), "retained barrier missing");
  for (let i = 0; i < 128; i++) await get(1, `seed-${i}`);
  for (let worker = 0; worker < 4; worker++)
    for (let i = 0; i < 240; i++) await get(1, `load-${worker}-${i}`);
  const handoverEnd = snapshot();
  await sleep(20000);
  sampling = false;
  await collector;
  assert.equal(collectorError, undefined, "resource collector failed");
  fs.writeFileSync(
    `${output}/result.json`,
    JSON.stringify(
      {
        image,
        mode,
        stats,
        before,
        loadEnd,
        handoverEnd,
        loadSeconds: (loadEnded - start) / 1000,
        handoverAndVerificationSeconds:
          (Date.now() - handoverStart - 20000) / 1000,
        samples,
      },
      null,
      2,
    ),
  );
  console.log(
    JSON.stringify({
      image,
      mode,
      stats,
      loadSeconds: (loadEnded - start) / 1000,
    }),
  );
} finally {
  sampling = false;
  if (collector) await collector;
  f.close();
}
