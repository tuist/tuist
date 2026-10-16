import fs from "node:fs";
import http2 from "node:http2";
import { upload } from "./upload.mjs";
import { inspect } from "node:util";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { setTimeout as sleep } from "node:timers/promises";
import { verifyBodyFrame } from "./body-frame.mjs";
import {
  profile,
  bodyHash,
  bodyChunks,
  seedBatches,
  missingShape,
  fragmentationReady,
} from "./profile.mjs";
import { field, number, frame, request } from "./protocol.mjs";

const config = JSON.parse(fs.readFileSync("/fixture/config.json"));
const p = profile(config.profile),
  namespace = "synthetic-retained";
const urls = ["source", "target"].map((r) => `http://${config.name}-${r}:4000`);
const peers = ["source", "target"].map(
  (r) => `http://${config.name}-${r}:7443`,
);
const peerUrls = ["source", "target"].map(
  (r) => `http://${config.name}-${r}-peer:7443`,
);
const result = {
  profile: p.name,
  scenario: config.scenario,
  started: Date.now(),
  ...config,
};
const save = (name, value) =>
  fs.writeFileSync(`/fixture/${name}.json`, JSON.stringify(value, null, 2));
const parse = (text) =>
  JSON.parse(text, (_k, v, c) =>
    typeof v === "number" && !Number.isSafeInteger(v)
      ? JSON.rawJSON(c.source)
      : v,
  );
const report = async (i) =>
  parse(
    await (
      await fetch(`${urls[i]}/status/rollout`, {
        signal: AbortSignal.timeout(5000),
      })
    ).text(),
  );
function grant(value) {
  fs.appendFileSync(
    "/fixture/grants.jsonl",
    JSON.stringify({ time: Date.now(), ...value }) + "\n",
  );
  save("grant.tmp", value);
  fs.renameSync("/fixture/grant.tmp.json", "/fixture/grant.json");
}
function progress(phase, extra = {}) {
  const value = { phase, time: Date.now(), ...extra };
  save("progress", value);
  console.log(JSON.stringify(value));
}
async function wait(check, message, timeout = 120000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await check()) return;
    await sleep(500);
  }
  throw new Error(message);
}
async function put(
  i,
  key,
  body,
  size,
  version,
  ns = namespace,
  inline = false,
) {
  const query = new URLSearchParams({
    producer: "reapi",
    namespace_id: ns,
    key,
    inline: String(inline),
    content_type: inline
      ? "application/x-protobuf"
      : "application/octet-stream",
    version_ms: String(version),
  });
  await upload(
    `${peers[i]}/_internal/replicate/artifact?${query}`,
    body,
    size,
    (retry) => {
      result.seedTransportRetries = (result.seedTransportRetries ?? 0) + 1;
      fs.appendFileSync(
        "/fixture/seed-retries.jsonl",
        JSON.stringify({ time: Date.now(), replica: i, key, ...retry }) + "\n",
      );
    },
  );
}
const recordId = (key, ns = namespace) =>
  createHash("sha256").update(`reapi\0default\0${ns}\0${key}`).digest("hex");
async function index(i) {
  const entries = [];
  let after;
  do {
    const query = new URLSearchParams({
      limit: "2048",
      ...(after ? { after } : {}),
    });
    const r = await fetch(`${peers[i]}/_internal/backfill/entries?${query}`, {
      signal: AbortSignal.timeout(30000),
    });
    assert.equal(r.status, 200);
    const page = await r.json();
    entries.push(...page.entries);
    after = page.next_after;
    assert(entries.length < 500000, "unbounded index walk");
  } while (after);
  return entries;
}
async function seedFiller(ns, bytes, replicas, version, stop) {
  for (let offset = 0, n = 0; offset < bytes; offset += p.fillerSize, n++) {
    const size = Math.min(p.fillerSize, bytes - offset),
      id = `${ns}-${n}`;
    const hash = bodyHash(id, size);
    await Promise.all(
      replicas.map((i) =>
        put(
          i,
          `blob/${hash}/${size}`,
          () => bodyChunks(id, size),
          size,
          version,
          ns,
        ),
      ),
    );
    if (n % 16 === 0)
      progress(`seed-${ns}`, { bytes: offset + size, total: bytes });
    if (stop && (await stop(offset + size))) return offset + size;
  }
  return bytes;
}
let collecting = false,
  collector,
  sessions = [];
function openSessions() {
  return urls.map((url, replica) => {
    const session = http2.connect(url);
    const event = (name, detail) =>
      fs.appendFileSync(
        "/fixture/channels.jsonl",
        JSON.stringify({ time: Date.now(), replica, event: name, detail }) +
          "\n",
      );
    session.on("error", (error) => event("error", error.message));
    session.on("goaway", (code) => event("goaway", code));
    session.on("close", () => event("close"));
    return session;
  });
}
try {
  await wait(
    async () => {
      try {
        return (
          await Promise.all(
            urls.map(
              async (url) =>
                (
                  await fetch(`${url}/ready`, {
                    signal: AbortSignal.timeout(2000),
                  })
                ).ok,
            ),
          )
        ).every(Boolean);
      } catch {
        return false;
      }
    },
    "runtimes not ready",
    300000,
  );
  progress("runtime_ready");
  await wait(
    async () => fs.existsSync("/fixture/runtime-ready"),
    "runtime resource preflight not acknowledged",
  );
  let identities = await Promise.all(
    [0, 1].map(async (i) => (await report(i)).serving_authority.identity),
  );
  const sourceIdentity = identities[0];
  grant({ epoch: 1, holder: sourceIdentity, phase: "Serving", renew: true });
  await wait(
    async () => (await report(0)).serving_authority.valid,
    "source grant inactive",
  );
  const version = Date.now() - 72 * 3600000;
  if (config.scenario === "fragmented")
    await seedFiller("history", p.historyBytes, [0, 1], version - 1000);
  const records = [];
  let seeded = 0,
    next = 0,
    bytes = 0;
  progress("seed-retained", { total: p.sizes.length });
  for (const batch of seedBatches(p.sizes)) {
    let position = 0;
    await Promise.all(
      Array.from({ length: 4 }, async () => {
        while (position < batch.length) {
          const n = batch[position++],
            size = p.sizes[n],
            id = `retained-${n}`,
            hash = bodyHash(id, size);
          const key = `blob/${hash}/${size}`;
          await Promise.all(
            [0, 1].map((i) =>
              put(i, key, () => bodyChunks(id, size), size, version + n),
            ),
          );
          records[n] = { key, hash, size, record_id: recordId(key) };
          seeded++;
          bytes += size;
          if (seeded % 1000 === 0)
            progress("seed-retained", { seeded, total: p.sizes.length, bytes });
        }
      }),
    );
  }
  save("corpus", records);
  next = 0;
  await Promise.all(
    Array.from({ length: 4 }, async () => {
      while (next < p.actions) {
        const n = next++,
          record = records[n % records.length];
        const digest = Buffer.concat([
          field(1, record.hash),
          number(2, record.size),
        ]);
        const body = Buffer.concat([
          field(
            2,
            Buffer.concat([field(1, `output-${n}.bin`), field(2, digest)]),
          ),
          field(5, Buffer.alloc(540, 83)),
        ]);
        const actionHash = createHash("sha256")
          .update(`synthetic-action-${n}`)
          .digest("hex");
        await Promise.all(
          [0, 1].map((i) =>
            put(
              i,
              `action_cache/${actionHash}/0`,
              body,
              body.length,
              version + records.length + n,
              namespace,
              true,
            ),
          ),
        );
        if (n % 1000 === 0)
          progress("seed-actions", { seeded: n, total: p.actions });
      }
    }),
  );
  if (config.scenario === "fragmented") {
    for (const i of [0, 1]) {
      const r = await fetch(
        `${peers[i]}/_internal/replicate/namespace?namespace_id=history&version_ms=${Date.now()}`,
        { method: "DELETE", signal: AbortSignal.timeout(30000) },
      );
      assert.equal(r.status, 204);
      await r.arrayBuffer();
    }
    result.divergenceBytes = await seedFiller(
      "divergence",
      p.divergenceBytes,
      [1],
      1,
      async (bytes) => {
        if (
          p.name !== "production" ||
          (bytes % 1024 ** 3 !== 0 && bytes !== p.divergenceBytes)
        )
          return false;
        const present = new Set(
          (await index(1)).map((record) => record.record_id),
        );
        const shape = missingShape(records, present);
        const sample = { time: Date.now(), bytes, ...shape };
        fs.appendFileSync(
          "/fixture/calibration.jsonl",
          JSON.stringify(sample) + "\n",
        );
        progress("seed-divergence", { bytes, ...shape });
        assert(
          shape.missingBytes <= 5e9,
          "fragmentation overshot its bounded deficit; refuse an invalid baseline",
        );
        return fragmentationReady(shape);
      },
    );
  }
  progress("upgrade_requested");
  await wait(
    async () => fs.existsSync("/fixture/upgrade-complete"),
    "orchestrator did not replace standby",
    600000,
  );
  await wait(
    async () => {
      try {
        return (
          await fetch(`${urls[1]}/ready`, { signal: AbortSignal.timeout(2000) })
        ).ok;
      } catch {
        return false;
      }
    },
    "upgraded standby not ready",
    300000,
  );
  identities = await Promise.all(
    [0, 1].map(async (i) => (await report(i)).serving_authority.identity),
  );
  assert.deepEqual(
    identities[0],
    sourceIdentity,
    "source restarted during preparation",
  );
  await sleep(10000);
  const before = await Promise.all([0, 1].map(index));
  before.forEach((entries, i) => save(`index-before-${i}`, entries));
  // Some versions serialize the enum as Artifact; use manifest membership as
  // the authoritative corpus-shape check, independent of enum spelling.
  const sourceIds = new Set(before[0].map((r) => r.record_id));
  const targetIds = new Set(before[1].map((r) => r.record_id));
  const retained = records.filter((r) => sourceIds.has(r.record_id));
  result.shape = {
    sourceRows: before[0].length,
    targetRows: before[1].length,
    retainedBlobs: retained.length,
    retainedBytes: retained.reduce((n, r) => n + r.size, 0),
    largest: retained.reduce((max, r) => Math.max(max, r.size), 0),
    ...missingShape(retained, targetIds),
  };
  save("shape", result.shape);
  assert(
    retained.length >= records.length * 0.9,
    "source lost too much of the synthetic corpus during preparation",
  );
  if (p.name === "production") {
    assert(
      result.shape.sourceRows >= 220000 &&
        result.shape.retainedBytes >= 40e9 &&
        result.shape.largest >= 750e6,
      "production shape not reached",
    );
    if (config.scenario === "fragmented")
      assert(
        result.shape.missingBytes >= 1e9 &&
          result.shape.missingBytes <= 5e9 &&
          result.shape.missingLargeBlobs >= 1,
        "standby holes must be 1–5 GB and include a largest body; reject transfer-bound or unrepresentative baselines",
      );
  }
  if (p.name === "records")
    assert(
      result.shape.sourceRows === records.length + p.actions &&
        result.shape.targetRows === result.shape.sourceRows &&
        retained.length === records.length &&
        result.shape.missingBlobs === 0,
      "record-count control requires the complete corpus on both replicas",
    );
  result.setupVerified = true;
  save("before", await Promise.all([0, 1].map(report)));
  progress("measurement_ready");
  await wait(
    async () => fs.existsSync("/fixture/measurement-ready"),
    "resource baseline was not captured",
  );
  sessions = openSessions();
  const httpWrite = (i, key) =>
    request(
      sessions[i],
      "/api/cache/keyvalue?tenant_id=default&namespace_id=probes",
      "PUT",
      JSON.stringify({ cas_id: key, entries: [{ value: key }] }),
    );
  const grpcWrite = (i, key) => {
    const body = Buffer.from(key),
      hash = createHash("sha256").update(body).digest("hex");
    return request(
      sessions[i],
      "/google.bytestream.ByteStream/Write",
      "POST",
      frame(
        Buffer.concat([
          field(1, `probes/uploads/${key}/blobs/${hash}/${body.length}`),
          number(3, 1),
          field(10, body),
        ]),
      ),
      true,
    );
  };
  assert.equal((await httpWrite(0, "before")).status, 204);
  assert.equal((await grpcWrite(0, "before")).grpc, "0");
  fs.writeFileSync("/fixture/measure", "enabled");
  collecting = true;
  collector = (async () => {
    while (collecting) {
      const metrics = await Promise.all(
        urls.map(async (url) =>
          (
            await fetch(`${url}/metrics`, { signal: AbortSignal.timeout(5000) })
          ).text(),
        ),
      );
      fs.appendFileSync(
        "/fixture/metrics.jsonl",
        JSON.stringify({ time: Date.now(), metrics }) + "\n",
      );
      await sleep(2000);
    }
  })().catch((error) => {
    result.collectorError = error.message;
  });
  const started = Date.now(),
    id = "synthetic-production-handover";
  const intent = {
    id,
    destination: identities[1],
    destination_url: peerUrls[1],
    source_url: peerUrls[0],
    deadline_ms: started + p.deadlineMs,
  };
  grant({
    epoch: 1,
    holder: sourceIdentity,
    phase: "Quiescing",
    handover: intent,
    renew: true,
  });
  progress("handover", { deadline: intent.deadline_ms });
  while (Date.now() < intent.deadline_ms) {
    const [a, b] = await Promise.all(
      [0, 1].map(async (i) => (await report(i)).serving_authority),
    );
    fs.appendFileSync(
      "/fixture/authority.jsonl",
      JSON.stringify({ time: Date.now(), source: a, target: b }) + "\n",
    );
    if (a.barrier?.id === id && b.barrier?.id === id) {
      assert.deepEqual(a.barrier, b.barrier);
      result.barrier = a.barrier;
      break;
    }
    await sleep(1000);
  }
  result.receiptMs = result.barrier ? Date.now() - started : null;
  result.handoverMs = Date.now() - started;
  if (result.barrier) {
    // Read bodies through the internal endpoint while both retained holds exist;
    // public reads after release may promote records and rotate the ring.
    const held = await index(0);
    save("index-held", held);
    const heldIds = new Set(held.map((r) => r.record_id));
    let verifiedBytes = 0;
    for (const r of retained
      .filter((r) => heldIds.has(r.record_id))
      .filter((r) => r.size >= 500e6 || r === retained[0])) {
      for (const i of [0, 1]) {
        const response = await fetch(
          `${peers[i]}/_internal/backfill/artifacts/${r.record_id}`,
          { signal: AbortSignal.timeout(120000) },
        );
        assert.equal(response.status, 200);
        verifiedBytes += await verifyBodyFrame(response.body, r);
      }
    }
    result.sampleVerifiedBytes = verifiedBytes;
    assert(
      Date.now() < intent.deadline_ms,
      "verification exhausted the handover deadline before revocation",
    );
    grant({
      epoch: 1,
      holder: sourceIdentity,
      phase: "Revoking",
      handover: intent,
      barrier: result.barrier,
      renew: true,
    });
    await wait(
      async () => (await report(0)).serving_authority.revoked_epoch === 1,
      "source did not revoke",
    );
    grant({
      epoch: 2,
      holder: identities[1],
      phase: "Serving",
      barrier: result.barrier,
      renew: true,
    });
    await wait(
      async () => (await report(1)).serving_authority.valid,
      "target did not activate",
    );
    assert.equal((await httpWrite(0, "stale-http")).status, 503);
    assert.equal((await grpcWrite(0, "stale-grpc")).grpc, "14");
    assert.equal((await httpWrite(1, "after-http")).status, 204);
    assert.equal((await grpcWrite(1, "after-grpc")).grpc, "0");
    result.persistentChannelChecks = true;
    result.handoverMs = Date.now() - started;
    assert(
      result.handoverMs < p.deadlineMs,
      "activation exceeded the original handover deadline",
    );
  } else {
    // Explicit simulator abort; a deadline itself never grants serving rights.
    grant({ epoch: 1, holder: sourceIdentity, phase: "Serving", renew: true });
    // Kura ages connections out after 300 seconds. Recovery after a full
    // deadline uses fresh sessions; successful handovers must use the originals.
    sessions.forEach((session) => session.destroy());
    sessions = openSessions();
    result.abortUsesFreshChannels = true;
    await wait(
      async () =>
        (await report(0)).serving_authority.valid &&
        (await httpWrite(0, "resumed-http")).status === 204,
      "source did not resume",
    );
    assert.equal((await grpcWrite(0, "resumed-grpc")).grpc, "0");
    assert.equal((await httpWrite(1, "standby-http")).status, 503);
    result.sourceResumed = true;
    result.handoverMs = Date.now() - started;
  }
  await sleep(10000);
  assert(!result.collectorError, result.collectorError);
  assert.deepEqual(
    (await report(0)).serving_authority.identity,
    sourceIdentity,
  );
  save("after", await Promise.all([0, 1].map(report)));
  const proxy = fs
    .readFileSync("/fixture/proxy.jsonl", "utf8")
    .trim()
    .split("\n")
    .filter(Boolean)
    .map(JSON.parse);
  result.requestTimeouts = proxy.filter(
    (r) =>
      r.route.includes("handover") &&
      r.ms >= 29000 &&
      r.ms < 35000 &&
      !r.completed,
  ).length;
} catch (error) {
  result.error = inspect(error, { depth: 5 });
  console.error(error.stack);
} finally {
  collecting = false;
  if (collector) await collector;
  sessions.forEach((s) => s.destroy());
  result.finished = Date.now();
  save("result", result);
  progress("finished", { error: result.error });
}
// Stay alive for evidence collection; restarting this container must not reseed.
await new Promise(() => setInterval(() => {}, 60000));
