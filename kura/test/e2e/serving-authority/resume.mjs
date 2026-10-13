import assert from "node:assert/strict";
import http2 from "node:http2";
import fs from "node:fs";
import { createHash } from "node:crypto";
import { setTimeout as sleep } from "node:timers/promises";
import { fixture } from "./fixture.mjs";
import { field, number, frame, request } from "./protocol.mjs";

const [image, output] = process.argv.slice(2);
assert(image && output, "usage: resume.mjs IMAGE OUTPUT_DIR");
const f = await fixture(image, "active", output);
const session = http2.connect(f.urls[0]);
session.on("error", () => {});
const query = "?tenant_id=default&namespace_id=resume";
const write = (key) => request(session, `/api/cache/keyvalue${query}`, "PUT",
  JSON.stringify({ cas_id: key, entries: [{ value: key }] }));
async function waitFor(check, message) {
  for (let i = 0; i < 60; i++) {
    if (await check()) return;
    await sleep(250);
  }
  assert.fail(message);
}
try {
  assert.equal((await write("retained")).status, 204);
  const payload = Buffer.from("upload admitted before the authority API interruption");
  const hash = createHash("sha256").update(payload).digest("hex");
  const stream = session.request({ ":method": "POST", ":path": "/google.bytestream.ByteStream/Write",
    "content-type": "application/grpc", te: "trailers" });
  const completion = new Promise((resolve, reject) => {
    let status;
    stream.on("response", h => status = h["grpc-status"]);
    stream.on("trailers", h => status = h["grpc-status"] ?? status);
    stream.on("data", () => {});
    stream.on("error", reject);
    stream.on("end", () => resolve(status));
  });
  stream.write(frame(Buffer.concat([field(1, `resume/uploads/held/blobs/${hash}/${payload.length}`), field(10, payload.subarray(0, 8))])));
  await waitFor(async () => (await f.report(0)).serving_authority.mutations > 0, "upload not admitted");
  fs.writeFileSync(`${output}/api-unavailable`, "503");
  await sleep(16000);
  assert.equal((await write("expired")).status, 503);
  assert.equal((await f.report(1)).serving_authority.valid, false);
  // This fixture supplies protocol inputs, not controller decisions. The real
  // Kubernetes controller's partition/recovery test lives in client.mjs.
  f.grant({ epoch: 1, holder: f.identities[0], phase: "Fencing", renew: true });
  fs.unlinkSync(`${output}/api-unavailable`);
  await waitFor(async () => (await f.report(0)).serving_authority.observed.phase === "Fencing", "fencing was not observed");
  assert.equal((await f.report(0)).serving_authority.fenced_epoch, 0);
  stream.end(frame(Buffer.concat([number(2, 8), number(3, 1), field(10, payload.subarray(8))])));
  assert.equal(await completion, "14");
  await waitFor(async () => (await f.report(0)).serving_authority.fenced_epoch === 1, "writer did not acknowledge publication fencing");
  const fenced = (await f.report(0)).serving_authority;
  assert.equal(fenced.mutations, 0);
  f.grant({ epoch: 2, resume_epoch: 1, holder: f.identities[0], phase: "Serving", renew: true });
  await waitFor(async () => (await f.report(0)).serving_authority.valid, "same writer did not resume");
  assert.deepEqual((await f.report(0)).serving_authority.identity, f.identities[0]);
  assert.equal((await write("resumed")).status, 204);
  assert.equal((await request(session, `/api/cache/keyvalue/retained${query}`, "GET")).status, 200);
  const missing = await request(session, "/google.bytestream.ByteStream/Read", "POST",
    frame(field(1, `resume/blobs/${hash}/${payload.length}`)), true);
  assert.equal(missing.grpc, "5", "expired upload published after resumption");
  session.destroy();
  f.docker("stop", "--time", "5", f.names[0]);
  f.docker("start", f.names[0]);
  await sleep(2000);
  assert.equal(f.docker("inspect", "-f", "{{.State.Running}}", f.names[0]).trim(), "false");
  assert(f.logs(f.names[0]).includes("unclean primary volume"));
  const result = { sameWriterResumed: true, noTimeoutPromotion: true, drainedBeforeAcknowledgment: true,
    persistentChannelWrite: true, retainedRead: true, lateWriteAbsent: true, dirtyRestartRefused: true };
  fs.writeFileSync(`${output}/result.json`, JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
} finally {
  session.destroy();
  f.close();
}
