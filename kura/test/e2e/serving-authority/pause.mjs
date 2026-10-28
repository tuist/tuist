import assert from "node:assert/strict";
import http2 from "node:http2";
import fs from "node:fs";
import { createHash } from "node:crypto";
import { setTimeout as sleep } from "node:timers/promises";
import { fixture } from "./fixture.mjs";
import { field, number, frame, request } from "./protocol.mjs";

const [image, output] = process.argv.slice(2);
if (!image || !output) throw new Error("usage: pause.mjs IMAGE OUTPUT_DIR");
const f = await fixture(image, "active", output);
const { urls, names, docker, report, grant } = f;
const session = http2.connect(urls[0]);
session.on("error", (error) => console.error(error.message));
let paused = false;
try {
  const payload = Buffer.from(
    "an upload held across a complete runtime freeze",
  );
  const hash = createHash("sha256").update(payload).digest("hex"),
    split = 16;
  const stream = session.request({
    ":method": "POST",
    ":path": "/google.bytestream.ByteStream/Write",
    "content-type": "application/grpc",
    te: "trailers",
  });
  const completion = new Promise((resolve, reject) => {
    let status;
    stream.on("response", (h) => (status = h["grpc-status"]));
    stream.on("trailers", (h) => (status = h["grpc-status"] ?? status));
    stream.on("data", () => {});
    stream.on("error", reject);
    stream.on("end", () => resolve(status));
  });
  stream.write(
    frame(
      Buffer.concat([
        field(1, `pause/uploads/frozen/blobs/${hash}/${payload.length}`),
        field(10, payload.subarray(0, split)),
      ]),
    ),
  );
  let admitted = false;
  for (let retry = 0; retry < 30; retry++) {
    if ((await report(0)).serving_authority.mutations > 0) {
      admitted = true;
      break;
    }
    await sleep(100);
  }
  assert(admitted);
  grant({
    epoch: 1,
    holder: f.identities[0],
    phase: "Serving",
    expires_ms: Date.now() + 14000,
  });
  docker("pause", names[0]);
  paused = true;
  await sleep(20000);
  assert.equal(
    (await report(1)).serving_authority.valid,
    false,
    "standby promoted while source was frozen",
  );
  docker("unpause", names[0]);
  paused = false;
  stream.end(
    frame(
      Buffer.concat([
        number(2, split),
        number(3, 1),
        field(10, payload.subarray(split)),
      ]),
    ),
  );
  const lateStatus = await completion;
  assert.equal(lateStatus, "14");
  // A fresh observation must not resurrect an expired primary incarnation.
  grant({ epoch: 1, holder: f.identities[0], phase: "Serving", renew: true });
  await sleep(2000);
  assert.equal((await report(0)).serving_authority.valid, false);
  const oldWrite = await request(
    session,
    "/api/cache/keyvalue?tenant_id=default&namespace_id=pause",
    "PUT",
    JSON.stringify({
      cas_id: "after-pause",
      entries: [{ value: "forbidden" }],
    }),
  );
  assert.equal(oldWrite.status, 503);
  docker("stop", "--time", "5", names[0]);
  docker("start", names[0]);
  await sleep(2000);
  assert.equal(
    docker("inspect", "-f", "{{.State.Running}}", names[0]).trim(),
    "false",
  );
  assert(f.logs(names[0]).includes("unclean primary volume"));
  grant({ epoch: 2, holder: f.identities[1], phase: "Serving", renew: true });
  let active = false;
  for (let retry = 0; retry < 30; retry++) {
    active = (await report(1)).serving_authority.valid;
    if (active) break;
    await sleep(500);
  }
  assert(active);
  const replacement = http2.connect(urls[1]);
  try {
    const read = await request(
      replacement,
      "/google.bytestream.ByteStream/Read",
      "POST",
      frame(field(1, `pause/blobs/${hash}/${payload.length}`)),
      true,
    );
    assert.equal(read.grpc, "5", "late write appeared after promotion");
  } finally {
    replacement.destroy();
  }
  const result = {
    freezeSeconds: 20,
    noTimeoutPromotion: true,
    lateStatus,
    expiredIncarnationStayedFenced: true,
    dirtyRestartRefused: true,
    positiveTerminationBeforePromotion: true,
    lateWriteAbsent: true,
  };
  fs.writeFileSync(`${output}/result.json`, JSON.stringify(result, null, 2));
  console.log(JSON.stringify(result));
} finally {
  if (paused) docker("unpause", names[0]);
  session.destroy();
  f.close();
}
