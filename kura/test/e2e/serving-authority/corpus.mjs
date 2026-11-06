import http2 from "node:http2";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import { createHash } from "node:crypto";
import { once } from "node:events";
import { field, number, frame, request } from "./protocol.mjs";

const [mode, url, manifestPath, countArg = "256", bytesArg = "1048576"] =
  process.argv.slice(2);
if (!["seed", "verify"].includes(mode) || !manifestPath)
  throw new Error("usage: corpus.mjs seed|verify URL MANIFEST [COUNT] [BYTES]");
let session, goaway;
async function connect() {
  goaway = undefined;
  session = http2.connect(url, {
    settings: { initialWindowSize: 8 * 1024 * 1024 },
  });
  session.on("error", (error) => console.error(error.message));
  session.on("goaway", (code, lastStreamID, opaque) => {
    goaway = { code, lastStreamID, reason: opaque?.toString() };
    console.log(JSON.stringify({ goaway }));
  });
  await once(session, "connect");
  session.setLocalWindowSize(16 * 1024 * 1024);
}
await connect();
const namespace = "spec98-corpus";
const digest = (hash, size) => Buffer.concat([field(1, hash), number(2, size)]);
const hash = (body) => createHash("sha256").update(body).digest("hex");
function decode(bytes) {
  let offset = 0;
  const vint = () => {
    let value = 0,
      multiplier = 1;
    while (offset < bytes.length) {
      const b = bytes[offset++];
      value += (b & 127) * multiplier;
      if (!(b & 128)) return value;
      multiplier *= 128;
    }
    throw new Error("truncated varint");
  };
  const result = [];
  while (offset < bytes.length) {
    const tag = vint(),
      id = Math.floor(tag / 8),
      wire = tag % 8;
    if (wire === 0) result.push({ id, value: vint() });
    else if (wire === 2) {
      const size = vint();
      assert(offset + size <= bytes.length);
      result.push({ id, value: bytes.subarray(offset, offset + size) });
      offset += size;
    } else throw new Error(`unsupported wire ${wire}`);
  }
  return result;
}
function messages(body) {
  const out = [];
  let offset = 0;
  while (offset < body.length) {
    assert.equal(body[offset], 0);
    const size = body.readUInt32BE(offset + 1);
    assert(offset + 5 + size <= body.length);
    out.push(body.subarray(offset + 5, offset + 5 + size));
    offset += 5 + size;
  }
  return out;
}
const rpc = async (method, body) => {
  for (let attempt = 0; ; attempt++) {
    if (goaway) {
      assert.equal(
        goaway.code,
        0,
        `unexpected GOAWAY: ${JSON.stringify(goaway)}`,
      );
      session.destroy();
      await connect();
    }
    let r;
    try {
      r = await request(session, method, "POST", frame(body), true);
    } catch (error) {
      // Corpus reads are idempotent. Persistent fencing tests use client.mjs,
      // which deliberately never reconnects its existing channels.
      if (
        mode !== "verify" ||
        attempt >= 2 ||
        ![
          "ECONNRESET",
          "ERR_HTTP2_GOAWAY_SESSION",
          "ERR_HTTP2_INVALID_SESSION",
        ].includes(error.code)
      )
        throw error;
      console.log(
        JSON.stringify({ readReconnect: error.code, attempt: attempt + 1 }),
      );
      session.destroy();
      await connect();
      continue;
    }
    assert.equal(r.grpc, "0", `${method}: status ${r.grpc}`);
    return messages(r.body);
  }
};
try {
  if (mode === "seed") {
    const count = Number(countArg),
      size = Number(bytesArg);
    assert(Number.isSafeInteger(count) && count > 0 && count <= 65536);
    assert(Number.isSafeInteger(size) && size >= 8 && size <= 2 * 1024 * 1024);
    const manifest = { namespace, count, size, records: [] };
    for (let i = 0; i < count; i++) {
      const body = Buffer.alloc(size, i % 251);
      body.writeBigUInt64BE(BigInt(i));
      const blobHash = hash(body),
        actionHash = hash(Buffer.from(`spec98-action-${i}-${blobHash}`));
      const upload = Buffer.concat([
        field(1, `${namespace}/uploads/${i}/blobs/${blobHash}/${size}`),
        number(3, 1),
        field(10, body),
      ]);
      await rpc("/google.bytestream.ByteStream/Write", upload);
      const result = field(
        2,
        Buffer.concat([
          field(1, `output-${i}.bin`),
          field(2, digest(blobHash, size)),
        ]),
      );
      await rpc(
        "/build.bazel.remote.execution.v2.ActionCache/UpdateActionResult",
        Buffer.concat([
          field(1, namespace),
          field(2, digest(actionHash, 32)),
          field(3, result),
        ]),
      );
      manifest.records.push({
        actionHash,
        blobHash,
        size,
        path: `output-${i}.bin`,
      });
      if ((i + 1) % 64 === 0)
        console.log(JSON.stringify({ seeded: i + 1, bytes: (i + 1) * size }));
    }
    await fs.writeFile(manifestPath, JSON.stringify(manifest));
    console.log(
      JSON.stringify({ mode, actions: count, blobBytes: count * size }),
    );
  } else {
    const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));
    let total = 0,
      verified = 0;
    for (const record of manifest.records) {
      const [action] = await rpc(
        "/build.bazel.remote.execution.v2.ActionCache/GetActionResult",
        Buffer.concat([
          field(1, manifest.namespace),
          field(2, digest(record.actionHash, 32)),
        ]),
      );
      const files = decode(action)
        .filter((x) => x.id === 2)
        .map((x) => decode(x.value));
      const output = files.find((f) =>
        f.some((x) => x.id === 1 && x.value.toString() === record.path),
      );
      assert(output, "action output missing");
      const d = decode(output.find((x) => x.id === 2).value);
      assert.equal(d.find((x) => x.id === 1).value.toString(), record.blobHash);
      assert.equal(d.find((x) => x.id === 2).value, record.size);
      const chunks = await rpc(
        "/google.bytestream.ByteStream/Read",
        field(
          1,
          `${manifest.namespace}/blobs/${record.blobHash}/${record.size}`,
        ),
      );
      const data = Buffer.concat(
        chunks.flatMap((x) =>
          decode(x)
            .filter((f) => f.id === 10)
            .map((f) => f.value),
        ),
      );
      assert.equal(data.length, record.size);
      assert.equal(hash(data), record.blobHash);
      total += data.length;
      verified++;
      if (verified % 64 === 0)
        console.log(JSON.stringify({ verified, bytes: total }));
    }
    console.log(
      JSON.stringify({
        mode,
        actions: manifest.records.length,
        verifiedBlobBytes: total,
      }),
    );
  }
} finally {
  session.destroy();
}
