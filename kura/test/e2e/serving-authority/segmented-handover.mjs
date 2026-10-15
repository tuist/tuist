import fs from "node:fs";
import assert from "node:assert/strict";
import { setTimeout as sleep } from "node:timers/promises";
import { fixture, handover } from "./fixture.mjs";

const [image, output] = process.argv.slice(2);
assert(image && output, "usage: segmented-handover.mjs IMAGE OUTPUT_DIR");
const count = Number(process.env.KURA_E2E_SEGMENT_RECORDS ?? 512);
assert([512, 2048].includes(count), "record count must be 512 or 2048");
const f = await fixture(image, "active", output);
const fullRing = count === 2048;
const retained = [];
const body = Buffer.alloc(2 * 1024 * 1024, 73);
const url = (replica, index) =>
  `${f.urls[replica]}/api/cache/cas/retained-${index}?tenant_id=default&namespace_id=segmented-handover`;
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
  const startHandover = Date.now();
  result.barrier = await handover(f, {
    deadlineMs: 300000,
    beforePromotion: fullRing
      ? async (barrier) => {
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
          assert.equal(barrier.records, retained.length);
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
  await sleep(20000);
  assert.equal(collectorError, undefined, "resource collection failed");
  console.log(
    JSON.stringify({ segmentedHandover: true, count, bytes: result.bytes }),
  );
} catch (error) {
  result.error = error.message;
  throw error;
} finally {
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
