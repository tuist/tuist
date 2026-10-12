import http2 from "node:http2";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";
import { createHash } from "node:crypto";
import { field, number, frame, request } from "./protocol.mjs";

const [mode, primaryURL, standbyURL, primaryPod, standbyPod] =
  process.argv.slice(2);
if (!["handover", "partition", "leader-restart"].includes(mode) || !standbyPod)
  throw new Error(
    "usage: client.mjs handover|partition|leader-restart PRIMARY_URL STANDBY_URL PRIMARY_POD STANDBY_POD",
  );
const context = process.env.KURA_SPEC98_CONTEXT;
if (!context)
  throw new Error(
    "KURA_SPEC98_CONTEXT must explicitly identify the isolated staging context",
  );
const instance = process.env.KURA_SPEC98_INSTANCE ?? "kura-spec98";
const namespace = process.env.KURA_SPEC98_NAMESPACE ?? "kura-spec98";
const kube = (...args) =>
  execFileSync(
    "kubectl",
    ["--request-timeout=20s", "--context", context, "-n", namespace, ...args],
    { encoding: "utf8", timeout: 30_000 },
  );
const sessions = [http2.connect(primaryURL), http2.connect(standbyURL)];
const report = async (url) =>
  (await (await fetch(`${url}/status/rollout`)).json()).serving_authority;
const capabilities = (session) =>
  request(
    session,
    "/build.bazel.remote.execution.v2.Capabilities/GetCapabilities",
    "POST",
    frame(field(1, "e2e")),
    true,
  );
const key = `persistent-${Date.now()}`;
const query = "?tenant_id=spec98-validation&namespace_id=e2e";
const write = (session) =>
  request(
    session,
    `/api/cache/keyvalue${query}`,
    "PUT",
    JSON.stringify({ cas_id: key, entries: [{ value: key }] }),
  );
let policyInstalled = false;
try {
  const before = await report(primaryURL),
    target = await report(standbyURL);
  assert.equal(before.valid, true);
  assert.equal(target.valid, false);
  if (process.env.KURA_E2E_MISSING_HASH) {
    const missing = await request(
      sessions[0],
      "/google.bytestream.ByteStream/Read",
      "POST",
      frame(
        field(
          1,
          `e2e/blobs/${process.env.KURA_E2E_MISSING_HASH}/${process.env.KURA_E2E_MISSING_SIZE}`,
        ),
      ),
      true,
    );
    assert.equal(
      missing.grpc,
      "5",
      "rejected late write appeared on the promoted replica",
    );
  }
  assert.equal((await write(sessions[0])).status, 204);
  assert.equal((await capabilities(sessions[0])).grpc, "0");
  const blob = Buffer.from(`grpc-persistent-${key}`);
  const hash = createHash("sha256").update(blob).digest("hex");
  const digest = Buffer.concat([field(1, hash), number(2, blob.length)]);
  const batch = Buffer.concat([
    field(1, "e2e"),
    field(2, Buffer.concat([field(1, digest), field(2, blob)])),
  ]);
  const upload = await request(
    sessions[0],
    "/build.bazel.remote.execution.v2.ContentAddressableStorage/BatchUpdateBlobs",
    "POST",
    frame(batch),
    true,
  );
  assert.equal(upload.grpc, "0");
  if (mode === "handover") {
    const id = `persistent-${Date.now()}`;
    kube(
      "patch",
      "kurainstance",
      instance,
      "--type=merge",
      "-p",
      JSON.stringify({
        spec: {
          plannedHandover: {
            id,
            podName: standbyPod,
            podUID: target.identity.pod_uid,
            incarnation: target.identity.incarnation,
          },
        },
      }),
    );
    let after;
    const deadline = Date.now() + 330_000;
    while (Date.now() < deadline) {
      await sleep(1000);
      after = await report(standbyURL);
      if (after.valid && after.epoch > before.epoch) break;
    }
    assert.equal(after.valid, true);
    assert.equal(after.epoch, before.epoch + 1);
    const read = await request(
      sessions[1],
      `/api/cache/keyvalue/${key}${query}`,
    );
    assert.equal(read.status, 200);
    assert.equal(JSON.parse(read.body).entries[0].value, key);
    const blobRead = await request(
      sessions[1],
      "/google.bytestream.ByteStream/Read",
      "POST",
      frame(field(1, `e2e/blobs/${hash}/${blob.length}`)),
      true,
    );
    assert.equal(
      blobRead.grpc,
      "0",
      JSON.stringify({
        status: blobRead.status,
        grpc: blobRead.grpc,
        body: blobRead.body.toString("hex").slice(0, 300),
      }),
    );
    assert(blobRead.body.includes(blob));
    assert.equal((await write(sessions[0])).status, 503);
    assert.notEqual((await capabilities(sessions[0])).grpc, "0");
    assert.equal((await write(sessions[1])).status, 204);
    console.log(
      JSON.stringify({
        mode,
        epoch: after.epoch,
        retainedHTTP: true,
        retainedGRPC: true,
        oldPersistentHTTPRejected: true,
        oldPersistentGRPCRejected: true,
      }),
    );
  } else if (mode === "leader-restart") {
    kube("rollout", "restart", "deployment/spec98-tuist-kura-controller");
    for (let i = 0; i < 40; i++) {
      await sleep(1000);
      assert.equal(
        (await write(sessions[0])).status,
        204,
        "controller restart interrupted HTTP writes",
      );
      assert.equal(
        (await capabilities(sessions[0])).grpc,
        "0",
        "controller restart interrupted gRPC",
      );
      const current = await report(primaryURL);
      assert.equal(current.valid, true);
      assert.equal(current.epoch, before.epoch);
    }
    kube(
      "rollout",
      "status",
      "deployment/spec98-tuist-kura-controller",
      "--timeout=30s",
    );
    assert.equal((await report(standbyURL)).valid, false);
    console.log(
      JSON.stringify({
        mode,
        epoch: before.epoch,
        continuousHTTP: true,
        continuousGRPC: true,
        unchangedHolder: true,
      }),
    );
  } else {
    const lateBlob = Buffer.from(
      `started-before-expiry-completed-after-${key}`,
    );
    const lateHash = createHash("sha256").update(lateBlob).digest("hex");
    const split = Math.floor(lateBlob.length / 2);
    const lateStream = sessions[0].request({
      ":method": "POST",
      ":path": "/google.bytestream.ByteStream/Write",
      "content-type": "application/grpc",
      te: "trailers",
    });
    const lateResult = new Promise((resolve, reject) => {
      let headers = {},
        trailers = {};
      lateStream.on("response", (h) => (headers = h));
      lateStream.on("trailers", (h) => (trailers = h));
      lateStream.on("data", () => {});
      lateStream.on("error", reject);
      lateStream.on("end", () =>
        resolve(trailers["grpc-status"] ?? headers["grpc-status"]),
      );
    });
    lateStream.write(
      frame(
        Buffer.concat([
          field(1, `e2e/uploads/spec98/blobs/${lateHash}/${lateBlob.length}`),
          field(10, lateBlob.subarray(0, split)),
        ]),
      ),
    );
    let admitted = false;
    for (let i = 0; i < 20; i++) {
      if ((await report(primaryURL)).mutations > 0) {
        admitted = true;
        break;
      }
      await sleep(100);
    }
    assert(admitted, "streaming write was not admitted before the partition");
    kube(
      "label",
      "pod",
      primaryPod,
      "spec98.tuist.dev/api-partition=true",
      "--overwrite",
    );
    policyInstalled = true;
    const observations = [];
    for (let i = 0; i < 45; i++) {
      await sleep(2000);
      const observed = await report(primaryURL);
      const http = await write(sessions[0]);
      const grpc = await capabilities(sessions[0]);
      observations.push({
        second: (i + 1) * 2,
        valid: observed.valid,
        expires: observed.observed?.expires_ms,
        http: http.status,
        grpc: grpc.grpc ?? String(grpc.status),
      });
      if (
        observations.length >= 5 &&
        observations
          .slice(-5)
          .every((x) => !x.valid && x.http === 503 && x.grpc !== "0")
      )
        break;
    }
    console.log(JSON.stringify({ mode, observations }));
    lateStream.end(
      frame(
        Buffer.concat([
          number(2, split),
          number(3, 1),
          field(10, lateBlob.subarray(split)),
        ]),
      ),
    );
    const lateStatus = await lateResult;
    assert.notEqual(
      lateStatus,
      "0",
      "write admitted before expiry published after expiry",
    );
    assert(
      observations
        .slice(-5)
        .every((x) => !x.valid && x.http === 503 && x.grpc !== "0"),
    );
    assert.equal(
      (await report(standbyURL)).valid,
      false,
      "partition alone promoted standby",
    );
    assert(
      observations
        .slice(-5)
        .every((x) => x.expires === observations.at(-1).expires),
      "API partition did not stop renewal observations",
    );
    console.log(
      JSON.stringify({
        mode,
        epoch: before.epoch,
        noTimeoutPromotion: true,
        lateWriteRejected: true,
        lateStatus,
        lateHash,
        lateSize: lateBlob.length,
        observations,
      }),
    );
  }
} finally {
  if (policyInstalled)
    kube("label", "pod", primaryPod, "spec98.tuist.dev/api-partition-");
  for (const session of sessions) session.destroy();
}
