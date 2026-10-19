import fs from "node:fs";
import http2 from "node:http2";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { setTimeout as sleep } from "node:timers/promises";
import { fixture, handover } from "./fixture.mjs";
import { request } from "./protocol.mjs";

const [image, output] = process.argv.slice(2);
assert(image && output, "usage: segmented-handover.mjs IMAGE OUTPUT_DIR");
const count = Number(process.env.KURA_E2E_SEGMENT_RECORDS ?? 512);
assert([512, 2048].includes(count), "record count must be 512 or 2048");
const fullRing = count === 2048;
const repairOld = process.env.KURA_E2E_RETAINED_RECENCY === "1";
const repairChurn = process.env.KURA_E2E_REPAIR_CHURN === "1";
const prepare = process.env.KURA_E2E_LIVE_PREPARATION === "1";
const liveChurn = process.env.KURA_E2E_LIVE_WRITE_CHURN === "1";
assert(
  !liveChurn || (fullRing && prepare),
  "live churn requires full-ring preparation",
);
assert(
  !repairOld || fullRing,
  "recency repair requires the full-ring workload",
);
assert(
  !repairChurn || (fullRing && !repairOld),
  "repair churn requires its own full-ring workload",
);
const f = await fixture(image, "active", output);
const retained = [];
const preparationSessions = [];
const preparationKey = "live-preparation";
const preparationQuery = "?tenant_id=default&namespace_id=segmented-handover";
const preparationWrite = (i) =>
  request(
    preparationSessions[i],
    `/api/cache/keyvalue${preparationQuery}`,
    "PUT",
    JSON.stringify({
      cas_id: preparationKey,
      entries: [{ value: preparationKey }],
    }),
  );
const body = Buffer.alloc(2 * 1024 * 1024, 73);
const url = (replica, index) =>
  `${f.urls[replica]}/api/cache/cas/retained-${index}?tenant_id=default&namespace_id=segmented-handover`;
let churn;
let churnError;
let churning = true;
async function writeDuringPreparation() {
  for (let written = 0; churning; written++) {
    const index = (written * 17) % count;
    const bytes = Buffer.alloc(body.length, 73);
    bytes.writeUInt32BE(index);
    const response = await fetch(url(0, index), {
      method: "POST",
      body: bytes,
      signal: AbortSignal.timeout(30000),
    });
    await response.arrayBuffer();
    if (response.status === 503) {
      const authority = (await f.report(0)).serving_authority;
      assert(
        ["Quiescing", "Revoking"].includes(authority.observed?.phase),
        "live writes may stop only when cutover quiesces the source",
      );
      return;
    }
    assert.equal(response.status, 204);
    result.liveBodyWrites = written + 1;
    await sleep(50);
  }
}
const samples = [];
let collecting = true;
let collectorError;
const collector = (async () => {
  while (collecting) {
    samples.push({
      time: Date.now(),
      metrics: await Promise.all([0, 1].map(f.metric)),
    });
    await sleep(2000);
  }
})().catch((error) => {
  collectorError = error;
});
const result = {
  image,
  count,
  bytes: count * body.length,
  before: f.snapshot(),
};
try {
  const start = Date.now();
  for (let i = 0; i < count; i++) {
    body.writeUInt32BE(i);
    const response = await fetch(url(0, i), {
      method: "POST",
      body,
      signal: AbortSignal.timeout(30000),
    });
    await response.arrayBuffer();
    assert.equal(response.status, 204);
    await sleep(50);
  }
  result.loadSeconds = (Date.now() - start) / 1000;
  result.loadEnd = f.snapshot();
  await sleep(10000);
  result.settled = f.snapshot();
  result.beforeHandoverMetrics = await Promise.all([0, 1].map(f.metric));
  if (repairChurn) {
    for (const replica of [0, 1])
      assert.equal(
        (await f.report(replica)).backfill_ring_fullness_percent,
        100,
      );
    // Diverge only the standby with old destination-only bodies. The source's
    // ordinary recency policy must leave these outside its already-full ring.
    await promisify(execFile)(
      "docker",
      [
        "--context",
        "default",
        "exec",
        `${f.prefix}-api`,
        "node",
        "--input-type=module",
        "-e",
        `
      for (let i = 0; i < 512; i++) {
        const r = await fetch(${JSON.stringify(`http://${f.names[1]}:7443/_internal/replicate/artifact?producer=gradle&inline=false&namespace_id=segmented-handover&content_type=application%2Foctet-stream&version_ms=1&key=destination-only-`)} + i,
          {method: 'PUT', body: Buffer.alloc(2 * 1024 * 1024, 91), signal: AbortSignal.timeout(30000)});
        await r.arrayBuffer(); if (r.status !== 204) throw Error('seed status ' + r.status);
      }
    `,
      ],
      { timeout: 120000, maxBuffer: 1024 * 1024 },
    );
    await sleep(10000);
    const id = createHash("sha256")
      .update("gradle\0default\0segmented-handover\0destination-only-511")
      .digest("hex");
    for (const replica of [0, 1]) {
      const status = Number(
        f
          .docker(
            "exec",
            f.names[replica],
            "curl",
            "-sS",
            "--max-time",
            "30",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            `http://127.0.0.1:7443/_internal/backfill/artifacts/${id}`,
          )
          .trim(),
      );
      assert.equal(
        status,
        replica === 0 ? 404 : 200,
        "destination-only seed must not change the source corpus",
      );
    }
    result.divergentStandbyBytes = 512 * body.length;
  }
  if (repairOld) {
    for (const replica of [0, 1])
      assert.equal(
        (await f.report(replica)).backfill_ring_fullness_percent,
        100,
      );
    // Insert an old version through the existing peer protocol, as if the
    // primary had retained a hot object whose original version never changed.
    // Ordinary replication must skip it on the already-full standby.
    const recordId = createHash("sha256")
      .update("gradle\0default\0segmented-handover\0old-missing")
      .digest("hex");
    const injected = f.docker(
      "exec",
      `${f.prefix}-api`,
      "node",
      "--input-type=module",
      "-e",
      `const r = await fetch(${JSON.stringify(`http://${f.names[0]}:7443/_internal/replicate/artifact?producer=gradle&inline=false&namespace_id=segmented-handover&key=old-missing&content_type=application%2Foctet-stream&version_ms=1`)}, {method: 'PUT', body: Buffer.alloc(2 * 1024 * 1024, 91), signal: AbortSignal.timeout(30000)}); console.log(r.status); await r.arrayBuffer();`,
    );
    assert.equal(Number(injected.trim()), 204);
    await sleep(10000);
    const status = (replica) =>
      Number(
        f
          .docker(
            "exec",
            f.names[replica],
            "curl",
            "-sS",
            "--max-time",
            "30",
            "-o",
            "/dev/null",
            "-w",
            "%{http_code}",
            `http://127.0.0.1:7443/_internal/backfill/artifacts/${recordId}`,
          )
          .trim(),
      );
    assert.equal(status(0), 200, "source must retain the injected old record");
    assert.equal(
      status(1),
      404,
      "fixture must reproduce the missing old record",
    );
    result.oldRecordMissingBeforeRepair = true;
  }
  if (prepare) {
    // Seeding may outlive normal connection aging. Establish the channels for
    // this transition now, prove writes while Serving, and never replace them.
    for (const address of f.urls) {
      const session = http2.connect(address);
      session.on("error", () => {});
      preparationSessions.push(session);
    }
    assert.equal((await preparationWrite(0)).status, 204);
  }
  const startHandover = Date.now();
  result.barrier = await handover(f, {
    deadlineMs: 300000,
    prepare: prepare
      ? async () => {
          if (liveChurn && !churn)
            churn = writeDuringPreparation().catch((error) => {
              churnError = error;
            });
          assert.equal(churnError, undefined);
          for (const replica of [0, 1]) {
            assert.equal(
              (await preparationWrite(replica)).status,
              replica === 0 ? 204 : 503,
            );
          }
          result.preparationWriteChecks =
            (result.preparationWriteChecks ?? 0) + 1;
        }
      : undefined,
    beforePromotion: fullRing
      ? async (barrier) => {
          if (churn) await churn;
          assert.equal(churnError, undefined);
          for (let i = 0; i < count; i++) {
            const response = await fetch(url(0, i), {
              signal: AbortSignal.timeout(30000),
            });
            const bytes = Buffer.from(await response.arrayBuffer());
            if (response.status === 404) continue;
            assert.equal(response.status, 200);
            body.writeUInt32BE(i);
            assert(bytes.equals(body));
            retained.push(i);
          }
          assert(
            retained.length > 0 && retained.length < count,
            "full ring must retain a nonempty partial corpus",
          );
          assert.equal(
            barrier.records,
            retained.length + (repairOld ? 1 : 0) + (prepare ? 1 : 0),
          );
          if (prepare) {
            const read = await request(
              preparationSessions[0],
              `/api/cache/keyvalue/${preparationKey}${preparationQuery}`,
            );
            assert.equal(read.status, 200);
            assert.equal(
              JSON.parse(read.body).entries[0].value,
              preparationKey,
            );
          }
          result.heldRetainedReads = retained.length;
          fs.writeFileSync(
            `${output}/frozen-corpus.json`,
            JSON.stringify(retained),
          );
        }
      : undefined,
  });
  result.handoverSeconds = (Date.now() - startHandover) / 1000;
  result.afterHandoverMetrics = await Promise.all([0, 1].map(f.metric));
  assert(result.barrier, "segmented retained corpus did not satisfy handover");
  if (repairChurn) {
    const events = f
      .logs(f.names[1])
      .split("\n")
      .flatMap((line) => {
        try {
          return [JSON.parse(line)];
        } catch {
          return [];
        }
      });
    result.repairRevisits = events.filter((event) =>
      [
        "kura.handover.repair_revisit",
        "kura.handover.preparation_revisit",
      ].includes(event["event.name"]),
    ).length;
    assert(
      result.repairRevisits > 0,
      "fixture must exercise repair eviction and a second walk",
    );
  }
  if (repairOld) {
    const response = await fetch(
      `${f.urls[1]}/api/cache/gradle/old-missing?tenant_id=default&namespace_id=segmented-handover`,
      { signal: AbortSignal.timeout(30000) },
    );
    assert.equal(response.status, 200);
    assert(
      Buffer.from(await response.arrayBuffer()).equals(
        Buffer.alloc(2 * 1024 * 1024, 91),
      ),
    );
    result.oldRecordRepaired = true;
  }
  const expected = fullRing
    ? retained.slice(-1)
    : Array.from({ length: count }, (_, i) => i);
  for (const i of expected) {
    const response = await fetch(url(1, i), {
      signal: AbortSignal.timeout(30000),
    });
    assert.equal(response.status, 200, `promoted destination record ${i}`);
    body.writeUInt32BE(i);
    assert(Buffer.from(await response.arrayBuffer()).equals(body));
  }
  result.retainedReads = expected.length;
  if (prepare) {
    const read = await request(
      preparationSessions[1],
      `/api/cache/keyvalue/${preparationKey}${preparationQuery}`,
    );
    assert.equal(read.status, 200);
    assert.equal(JSON.parse(read.body).entries[0].value, preparationKey);
    assert.equal((await preparationWrite(0)).status, 503);
    assert.equal((await preparationWrite(1)).status, 204);
    result.originalPreparationChannelsVerified = true;
  }
  await sleep(20000);
  assert.equal(collectorError, undefined, "resource collection failed");
  console.log(
    JSON.stringify({ segmentedHandover: true, count, bytes: result.bytes }),
  );
} catch (error) {
  result.error = error.message;
  throw error;
} finally {
  churning = false;
  if (churn) await churn;
  preparationSessions.forEach((session) => session.destroy());
  collecting = false;
  await collector;
  try {
    result.after = f.snapshot();
    result.samples = samples;
    fs.writeFileSync(`${output}/result.json`, JSON.stringify(result, null, 2));
  } finally {
    f.close();
  }
}
