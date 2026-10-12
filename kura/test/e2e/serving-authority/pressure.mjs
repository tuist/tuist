import assert from "node:assert/strict";
import fs from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";
import { fixture, handover } from "./fixture.mjs";

const [image, output] = process.argv.slice(2);
if (!image || !output) throw new Error("usage: pressure.mjs IMAGE OUTPUT_DIR");
// Reuses the quota-pressure fixture's bounded tmpfs. No host filesystem is filled.
const f = await fixture(image, "active", output, { limitedTarget: true });
const { urls, names, docker, report, grant, metric, snapshot } = f;
const body = Buffer.alloc(8 * 1024 * 1024, 73),
  retained = [];
const url = (i, key) =>
  `${urls[i]}/api/cache/cas/pressure-${key}?tenant_id=default&namespace_id=pressure`;
let collecting = true,
  collector,
  collectorError,
  targetRestarting = false;
const samples = [];
try {
  docker(
    "exec",
    names[1],
    "dd",
    "if=/dev/zero",
    "of=/data/metadata-pressure",
    "bs=1M",
    "count=1280",
    "status=none",
  );
  const before = snapshot();
  collector = (async () => {
    while (collecting) {
      samples.push({
        time: Date.now(),
        metrics: await Promise.all(
          [0, 1].map(async (i) => {
            try {
              return await metric(i);
            } catch (error) {
              if (i === 1 && targetRestarting) return null;
              throw error;
            }
          }),
        ),
      });
      await sleep(2000);
    }
  })().catch((error) => {
    collectorError = error;
  });
  for (let i = 0; i < 512; i++) {
    body.writeUInt32BE(i);
    const r = await fetch(url(0, i), {
      method: "POST",
      body,
      signal: AbortSignal.timeout(30000),
    });
    await r.arrayBuffer();
    assert.equal(r.status, 204);
    if ((i + 1) % 64 === 0)
      console.log(
        JSON.stringify({ writes: i + 1, bytes: (i + 1) * body.length }),
      );
  }
  await sleep(10000);
  const pressureMetrics = await metric(1),
    pressureState = snapshot();
  const reclaimed = Number(
    pressureMetrics.match(
      /kura_disk_pressure_reclaimed_bytes_total_total[^\n]* ([0-9]+)/,
    )?.[1] ?? 0,
  );
  assert(reclaimed > 0, "fixture did not exercise disk-pressure reclamation");
  const incomplete = await handover(f, {
    id: "capacity-incomplete",
    deadlineMs: 20000,
  });
  assert.equal(
    incomplete,
    null,
    "incomplete retained corpus was incorrectly promoted",
  );
  assert.equal((await report(0)).serving_authority.epoch, 1);
  assert.equal((await report(1)).serving_authority.valid, false);
  console.log(JSON.stringify({ incompleteHandoverRejected: true, reclaimed }));
  grant({ epoch: 1, holder: f.identities[0], phase: "Serving", renew: true });
  await sleep(2000);
  assert(
    (await report(0)).serving_authority.valid,
    "source not restored after abort",
  );
  const write = await fetch(url(0, "after-abort"), {
    method: "POST",
    body,
    signal: AbortSignal.timeout(30000),
  });
  await write.arrayBuffer();
  assert.equal(write.status, 204);
  // Capture what the source actually retains; capacity churn is allowed to miss
  // older cache entries, but a handover must preserve every retained record.
  for (let i = 0; i < 512; i++) {
    const r = await fetch(url(0, i), { signal: AbortSignal.timeout(30000) });
    const data = Buffer.from(await r.arrayBuffer());
    if (r.status === 404) continue;
    assert.equal(r.status, 200);
    body.writeUInt32BE(i);
    assert(data.equals(body));
    retained.push(i);
  }
  docker("exec", names[1], "rm", "/data/metadata-pressure");
  targetRestarting = true;
  docker("restart", names[1]);
  let ready = false;
  for (let i = 0; i < 90; i++) {
    try {
      const r = await report(1);
      ready = r.ready && r.backfill_initial_cycle === "complete";
      if (ready) {
        f.identities[1] = r.serving_authority.identity;
        break;
      }
    } catch {}
    await sleep(1000);
  }
  targetRestarting = false;
  assert(ready, "replacement did not complete bootstrap");
  const receipt = await handover(f, { id: "capacity-restored" });
  assert(receipt, "complete corpus did not hand over after pressure removal");
  for (const i of retained) {
    const r = await fetch(url(1, i), { signal: AbortSignal.timeout(30000) });
    const data = Buffer.from(await r.arrayBuffer());
    assert.equal(r.status, 200);
    body.writeUInt32BE(i);
    assert(data.equals(body));
  }
  const resumedWrite = await fetch(url(1, "after-abort"), {
    signal: AbortSignal.timeout(30000),
  });
  assert.equal(resumedWrite.status, 200);
  body.writeUInt32BE(511);
  assert(Buffer.from(await resumedWrite.arrayBuffer()).equals(body));
  const after = snapshot();
  await sleep(20000);
  collecting = false;
  await collector;
  assert.equal(
    collectorError,
    undefined,
    "unexpected resource collector failure",
  );
  const result = {
    reclaimed,
    retainedRecords: retained.length,
    incompleteHandoverRejected: true,
    sourceResumedAfterAbort: true,
    receipt,
    before,
    pressureState,
    after,
    samples,
  };
  fs.writeFileSync(`${output}/result.json`, JSON.stringify(result, null, 2));
  console.log(
    JSON.stringify({
      reclaimed,
      retainedRecords: retained.length,
      incompleteHandoverRejected: true,
      sourceResumedAfterAbort: true,
      completedEpoch: 2,
    }),
  );
} finally {
  collecting = false;
  if (collector) await collector.catch(() => {});
  f.close();
}
