import fs from "node:fs";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
const label = process.argv[2];
const testImage = process.argv[3];
if (!label || !testImage) throw Error("Usage: node resources.mjs label image");
const network = "kura-resource-" + process.pid;
const created = [];
const dockerCommand = (...args) =>
  execFileSync("docker", args, { encoding: "utf8" });
process.on("exit", () => {
  for (const name of created) {
    try {
      dockerCommand("rm", "-f", name);
    } catch {}
  }
  try {
    dockerCommand("network", "rm", network);
  } catch {}
});
dockerCommand("network", "create", network);
for (const [suffix, port] of [
  ["a", 4191],
  ["b", 4192],
]) {
  const name = "kura-resource-" + suffix;
  const env = {
    KURA_PORT: "4000",
    KURA_INTERNAL_PORT: "7443",
    KURA_TENANT_ID: "default",
    KURA_REGION: "eu-west",
    KURA_NODE_URL: "http://" + name + ":7443",
    KURA_PEERS: "http://kura-resource-a:7443,http://kura-resource-b:7443",
    KURA_DATA_DIR: "/data",
    KURA_TMP_DIR: "/data/tmp",
    KURA_TMP_DIR_MAX_BYTES: "134217728",
    KURA_CAS_CAPACITY_BYTES: "3221225472",
    KURA_AUTH_JWT_SECRET: "local-quota-test-only",
    KURA_MEMORY_LIMIT_BYTES: "1073741824",
    KURA_OTEL_SERVICE_NAME: "quota-test",
    KURA_OTEL_DEPLOYMENT_ENVIRONMENT: "local",
  };
  dockerCommand(
    "run",
    "-d",
    "--name",
    name,
    "--network",
    network,
    "-p",
    "127.0.0.1:" + port + ":4000",
    "--memory=1536m",
    "--cpus=2",
    ...Object.entries(env).flatMap(([k, v]) => ["-e", k + "=" + v]),
    testImage,
  );
  created.push(name);
}
const out = process.env.KURA_RESOURCE_OUTPUT || `/tmp/kura-resource-${label}`;
fs.mkdirSync(out, { recursive: true });
const enc = (x) => Buffer.from(JSON.stringify(x)).toString("base64url");
const tokenInput =
  enc({ alg: "HS256", typ: "JWT" }) +
  "." +
  enc({
    sub: "test",
    type: "user",
    scopes: ["project_cache_write"],
    cache_grants: {
      project: { read: ["default/bench"], write: ["default/bench"] },
    },
    exp: 4000000000,
  });
const token =
  tokenInput +
  "." +
  crypto
    .createHmac("sha256", "local-quota-test-only")
    .update(tokenInput)
    .digest("base64url");
const headers = {
  authorization: `Bearer ${token}`,
  "content-type": "application/octet-stream",
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const url = (port, key) =>
  `http://127.0.0.1:${port}/api/cache/gradle/${key}?tenant_id=default&namespace_id=bench`;
const body = Buffer.alloc(8 * 1024 * 1024, 71);
const stats = { puts: 0, gets: 0, readBytes: 0, failures: [] };
async function write(key) {
  const r = await fetch(url(4191, key), { method: "PUT", headers, body });
  if (!r.ok) throw Error(`PUT ${key}: ${r.status} ${await r.text()}`);
  await r.arrayBuffer();
  stats.puts++;
}
async function read(port, key) {
  const r = await fetch(url(port, key), { headers });
  const b = Buffer.from(await r.arrayBuffer());
  stats.gets++;
  stats.readBytes += b.length;
  if (r.status !== 200 || b.length !== body.length || !b.equals(body))
    stats.failures.push({ port, key, status: r.status, bytes: b.length });
}
const docker = (...args) => execFileSync("docker", args, { encoding: "utf8" });
function hostStats() {
  return ["a", "b"].map((n) => ({
    node: n,
    cpu: docker("exec", `kura-resource-${n}`, "cat", "/sys/fs/cgroup/cpu.stat"),
    disk: docker("exec", `kura-resource-${n}`, "du", "-sb", "/data"),
    net: docker("exec", `kura-resource-${n}`, "cat", "/proc/net/dev"),
  }));
}
for (const port of [4191, 4192]) {
  for (let i = 0; i < 90; i++) {
    try {
      if ((await fetch(`http://127.0.0.1:${port}/ready`)).ok) break;
    } catch {}
    if (i === 89) throw Error("not ready");
    await sleep(1000);
  }
}
let sequence = 0;
async function sample() {
  for (const port of [4191, 4192])
    fs.writeFileSync(
      `${out}/${sequence}-${port}.prom`,
      await (await fetch(`http://127.0.0.1:${port}/metrics`)).text(),
    );
  sequence++;
}
await sample();
const before = hostStats();
let sampling = Promise.resolve();
const interval = setInterval(() => {
  sampling = sampling.then(sample);
}, 2000);
for (let i = 0; i < 64; i++) await write(`seed-${i}`);
for (let retry = 0; retry < 60; retry++) {
  const r = await fetch(url(4192, "seed-63"), { headers });
  await r.arrayBuffer();
  if (r.ok) break;
  if (retry === 59) throw Error("replication did not converge");
  await sleep(1000);
}
const start = Date.now();
await Promise.all([
  (async () => {
    for (let i = 0; i < 256; i++) {
      await sleep(Math.max(0, start + i * 250 - Date.now()));
      await write(`load-${i}`);
    }
  })(),
  ...[4191, 4192].map(async (port) => {
    for (let i = 0; i < 256; i++) {
      await sleep(Math.max(0, start + i * 250 - Date.now()));
      await read(port, `seed-${i % 64}`);
    }
  }),
]);
stats.loadDurationMs = Date.now() - start;
stats.loadEndSample = sequence;
await sleep(30000);
clearInterval(interval);
await sampling;
await sample();
const after = hostStats();
fs.writeFileSync(
  `${out}/result.json`,
  JSON.stringify({ stats, before, after, samples: sequence }, null, 2),
);
console.log(JSON.stringify(stats));
if (stats.failures.length) process.exitCode = 1;
