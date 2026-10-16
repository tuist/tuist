import test from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  profile,
  bodyChunks,
  bodyHash,
  classify,
  missingShape,
  fragmentationReady,
} from "./profile.mjs";

test("production recipe preserves observed count, bytes and large-body tail", () => {
  const p = profile("production");
  assert.equal(p.sizes.length, 151943);
  assert.equal(
    p.sizes.reduce((sum, size) => sum + size, 0),
    44885777151,
  );
  assert.equal(p.actions, 77017);
  assert.equal(p.sizes.filter((size) => size === 814310767).length, 3);
  assert.deepEqual(p.sizes.slice(0, 3), [814310767, 814310767, 814310767]);
  assert.equal(p.capacity, 57804891095);
  assert.deepEqual(p.sizes, profile("production").sizes);
  assert.throws(() => profile("prodution"));
});

test("fragmentation calibration measures retained holes and rejects an oversized or small-body-only deficit", () => {
  const records = [0, 1, 2].map((n) => ({
    record_id: String(n),
    size: 814310767,
  }));
  records.push({ record_id: "small", size: 1000 });
  const shape = missingShape(records, new Set(["small"]));
  assert.deepEqual(shape, {
    missingBlobs: 3,
    missingBytes: 2442932301,
    missingLargeBlobs: 3,
  });
  assert(fragmentationReady(shape));
  assert(!fragmentationReady(missingShape(records, new Set(["0", "small"]))));
  assert(!fragmentationReady({ ...shape, missingLargeBlobs: 0 }));
  assert(!fragmentationReady({ ...shape, missingBytes: 5172665170 }));
});

test("streamed bodies have exact ragged lengths and stable distinct digests", () => {
  for (const size of [16, 65535, 65536, 65537, 1000003]) {
    const chunks = [...bodyChunks("one", size)];
    assert(chunks.every((chunk) => chunk.length <= 65536));
    const body = Buffer.concat(chunks);
    assert.equal(body.length, size);
    assert.equal(
      createHash("sha256").update(body).digest("hex"),
      bodyHash("one", size),
    );
    assert.notEqual(bodyHash("one", size), bodyHash("two", size));
  }
});

const log = (event) =>
  [1, 2].map(() => JSON.stringify({ "event.name": event })).join("\n");
const source = log("kura.handover.failed"),
  target = log("kura.handover.repair_revisit");
const failure = () => ({
  profile: "production",
  setupVerified: true,
  sourceResumed: true,
  handoverMs: 300500,
  requestTimeouts: 2,
  shape: { missingBytes: 2.5e9 },
});
test("expected failure requires convergence churn, actual request timeouts and safe abort", () => {
  assert.equal(classify(failure(), source, target), "repair-timeout");
  for (const override of [
    { profile: "smoke" },
    { error: "disk full" },
    { setupVerified: false },
    { sourceResumed: false },
    { barrier: {} },
    { handoverMs: 1000 },
    { requestTimeouts: 0 },
    { shape: { missingBytes: 18.5e9 } },
    { shape: { missingBytes: 0 } },
  ])
    assert.equal(
      classify({ ...failure(), ...override }, source, target),
      "not-reproduced",
    );
  assert.equal(classify(failure(), "", target), "not-reproduced");
  assert.equal(classify(failure(), source, ""), "not-reproduced");
  assert.equal(
    classify(failure(), "unparseable", "unparseable"),
    "not-reproduced",
  );
});

test("staging CLI refuses other environments before running kubectl", async () => {
  const { spawnSync } = await import("node:child_process");
  const run = spawnSync(
    process.execPath,
    [
      new URL("staging.mjs", import.meta.url).pathname,
      "--context",
      "production",
      "--namespace",
      "kura",
    ],
    { encoding: "utf8", env: { PATH: "/nonexistent" } },
  );
  assert.equal(run.status, 1);
  assert.match(run.stderr, /only permits the staging context/);
  assert.doesNotMatch(run.stderr, /spawnSync kubectl/);
});

test("staging accepts full-SHA qualification tags and rejects floating candidates", async () => {
  const { spawnSync } = await import("node:child_process");
  for (const tag of [
    "qualification-" + "a".repeat(40),
    "qualification-main",
    "latest",
  ]) {
    const image = `ghcr.io/tuist/kura:${tag}`;
    const run = spawnSync(
      process.execPath,
      [
        new URL("staging.mjs", import.meta.url).pathname,
        "--context",
        "tuist-k8s-staging.taild6d7bb.ts.net",
        "--namespace",
        "kura-spec98",
        "--node",
        "unused",
        "--output",
        "/unused",
        "--scenario",
        "fresh",
        "--expect",
        "pass",
        "--source-image",
        "ghcr.io/tuist/kura:0.59.0-canary.2",
        "--warm-image",
        image,
        "--candidate-image",
        image,
      ],
      { encoding: "utf8", env: { PATH: "/nonexistent" } },
    );
    assert.equal(run.status, 1);
    assert.match(
      run.stderr,
      tag.length === 54 ? /reuse test must replace/ : /explicit pinned/,
    );
    assert.doesNotMatch(run.stderr, /spawnSync kubectl/);
  }
});

test("body verification decodes split preludes and rejects corruption or truncation", async () => {
  const { verifyBodyFrame } = await import("./body-frame.mjs");
  const body = Buffer.from("a retained synthetic artifact"),
    id = "a".repeat(64);
  const meta = Buffer.from(JSON.stringify({ key: "blob/test/29" }));
  const header = Buffer.alloc(22);
  header[0] = 1;
  header.writeUInt16BE(id.length, 2);
  header.writeUInt16BE(meta.length, 12);
  header.writeBigUInt64BE(BigInt(body.length), 14);
  const wire = Buffer.concat([header, Buffer.from(id), meta, body]);
  const expected = {
    record_id: id,
    key: "blob/test/29",
    size: body.length,
    hash: createHash("sha256").update(body).digest("hex"),
  };
  assert.equal(
    await verifyBodyFrame(
      [...wire].map((byte) => Buffer.from([byte])),
      expected,
    ),
    body.length,
  );
  assert.equal(await verifyBodyFrame([wire], expected), body.length);
  await assert.rejects(
    verifyBodyFrame([wire.subarray(0, 21)], expected),
    /truncated/,
  );
  await assert.rejects(
    verifyBodyFrame([wire.subarray(0, -1)], expected),
    /truncated/,
  );
  const corrupt = Buffer.from(wire);
  corrupt[corrupt.length - 1] ^= 1;
  await assert.rejects(verifyBodyFrame([corrupt], expected), /digest/);
});

test("streaming seed tolerates idempotent early responses without hiding rejections", async () => {
  const http = await import("node:http");
  const { once } = await import("node:events");
  const { upload } = await import("./upload.mjs");
  const server = http
    .createServer(async (req, res) => {
      if (req.url === "/already-present") {
        res.writeHead(204).end();
        return;
      }
      if (req.url === "/reject") {
        res.writeHead(503).end();
        return;
      }
      const hash = createHash("sha256");
      let size = 0;
      for await (const chunk of req) {
        hash.update(chunk);
        size += chunk.length;
      }
      assert.equal(size, 1000003);
      assert.equal(hash.digest("hex"), bodyHash("upload", size));
      res.writeHead(204).end();
    })
    .listen(0, "127.0.0.1");
  await once(server, "listening");
  const url = `http://127.0.0.1:${server.address().port}`;
  try {
    await upload(
      `${url}/complete`,
      () => bodyChunks("upload", 1000003),
      1000003,
    );
    await upload(
      `${url}/already-present`,
      () => bodyChunks("large", 100000000),
      100000000,
    );
    await assert.rejects(
      upload(`${url}/reject`, () => bodyChunks("large", 100000000), 100000000),
      /503/,
    );
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
});

test("runtime scheduling floor matches production instead of protecting the whole ceiling", async () => {
  const { runtimeResources } = await import("./profile.mjs");
  const resources = runtimeResources(profile("production"));
  assert.equal(resources.requests.memory, "1Gi");
  assert.equal(resources.limits.memory, "4Gi");
  assert.equal(resources.requests["ephemeral-storage"], "64Gi");
  assert.equal(resources.requests["tuist.dev/memory-ceiling-mib"], "4096");
  assert.equal(resources.limits["tuist.dev/memory-ceiling-mib"], "4096");
});

test("seed retries reset connections with a fresh body and stop after three attempts", async () => {
  const http = await import("node:http");
  const { once } = await import("node:events");
  const { upload } = await import("./upload.mjs");
  let attempts = 0;
  const server = http
    .createServer(async (req, res) => {
      attempts++;
      if (req.url === "/fail" || attempts === 1) {
        req.socket.destroy();
        return;
      }
      let size = 0;
      for await (const chunk of req) size += chunk.length;
      assert.equal(size, 1000003);
      res.writeHead(204).end();
    })
    .listen(0, "127.0.0.1");
  await once(server, "listening");
  const url = `http://127.0.0.1:${server.address().port}`,
    retries = [];
  try {
    await upload(
      `${url}/recover`,
      () => bodyChunks("retry", 1000003),
      1000003,
      (r) => retries.push(r),
    );
    assert.equal(attempts, 2);
    assert.equal(retries.length, 1);
    attempts = 0;
    await assert.rejects(
      upload(`${url}/fail`, () => bodyChunks("retry", 1000003), 1000003),
    );
    assert.equal(attempts, 3);
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
});

test("parallel seed batches bound aggregate payload and isolate oversized objects", async () => {
  const { seedBatches } = await import("./profile.mjs");
  const p = profile("production"),
    batches = [...seedBatches(p.sizes)];
  assert.deepEqual(
    batches.flat(),
    p.sizes.map((_, i) => i),
  );
  for (const batch of batches) {
    assert(batch.length <= 32);
    const bytes = batch.reduce((n, i) => n + p.sizes[i], 0);
    assert(bytes <= 128 * 1048576 || batch.length === 1);
  }
});
