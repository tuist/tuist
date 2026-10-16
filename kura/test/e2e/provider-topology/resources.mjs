// Three origin regions, two providers, separate private DNS aliases, real mTLS.
// Local Docker networking tests the runtime, not physical vRack/VPC reachability.
// Run sequentially on baseline and changed images; both receive identical config.
import fs from "node:fs";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
const label = process.argv[2];
const testImage = process.argv[3];
if (!label || !testImage) throw Error("Usage: node resources.mjs label image");
const prefix = "kura-provider-resource-" + process.pid;
const network = prefix;
const out = process.env.KURA_RESOURCE_OUTPUT || `/tmp/kura-provider-resource-${label}`;
fs.mkdirSync(out, { recursive: true });
const certs = out + "/certs";
fs.mkdirSync(certs, { recursive: true });
const names = ["a", "b", "c"].map((suffix) => prefix + "-" + suffix);
const openssl = (...args) => execFileSync("openssl", args, { stdio: "ignore" });
openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", certs + "/ca.key", "-out", certs + "/ca.pem", "-days", "1", "-subj", "/CN=kura-resource-ca");
openssl("req", "-newkey", "rsa:2048", "-nodes", "-keyout", certs + "/peer.key", "-out", certs + "/peer.csr", "-subj", "/CN=kura-resource-peer");
fs.writeFileSync(certs + "/extensions", "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth,clientAuth\nsubjectAltName=" + names.flatMap(n => ["DNS:" + n, "DNS:private-" + n]).join(",") + "\n");
openssl("x509", "-req", "-in", certs + "/peer.csr", "-CA", certs + "/ca.pem", "-CAkey", certs + "/ca.key", "-CAcreateserial", "-out", certs + "/peer.pem", "-days", "1", "-extfile", certs + "/extensions");
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
for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => process.exit(1));
}
dockerCommand("network", "create", network);
for (const [suffix, port] of [
  ["a", 4291],
  ["b", 4292],
  ["c", 4293],
]) {
  const name = prefix + "-" + suffix;
  const env = {
    KURA_PORT: "4000",
    KURA_INTERNAL_PORT: "7443",
    KURA_TENANT_ID: "default",
    KURA_REGION: suffix,
    KURA_NODE_URL: "https://" + name + ":7443",
    KURA_PEERS: names.map(n => "https://" + n + ":7443").join(","),
    KURA_INTERNAL_TLS_CA_CERT_PATH: "/certs/ca.pem",
    KURA_INTERNAL_TLS_CERT_PATH: "/certs/peer.pem",
    KURA_INTERNAL_TLS_KEY_PATH: "/certs/peer.key",
    KURA_PEER_TOPOLOGY: JSON.stringify({provider: suffix === "c" ? "vultr" : "ovh", private_network: suffix === "c" ? "ord-vpc" : "vrack", private_url: "https://private-" + name + ":7443"}),
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
    "--network-alias",
    "private-" + name,
    "-v",
    certs + ":/certs:ro",
    "-p",
    "127.0.0.1:" + port + ":4000",
    "--memory=1536m",
    "--cpus=2",
    ...Object.entries(env).flatMap(([k, v]) => ["-e", k + "=" + v]),
    testImage,
  );
  created.push(name);
}
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
const body = Buffer.alloc(1024 * 1024, 71);
const stats = { puts: 0, gets: 0, readBytes: 0, failures: [] };
async function write(key) {
  const port = 4291 + (stats.puts % 3);
  const r = await fetch(url(port, key), { method: "PUT", headers, body });
  if (!r.ok) throw Error(`PUT ${key}: ${r.status} ${await r.text()}`);
  await r.arrayBuffer();
  stats.puts++;
  if (stats.puts % 32 === 0) console.log(`completed ${stats.puts} writes`);
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
  return ["a", "b", "c"].map((n) => ({
    node: n,
    cpu: docker("exec", `${prefix}-${n}`, "cat", "/sys/fs/cgroup/cpu.stat"),
    processCpu: docker(
      "exec",
      `${prefix}-${n}`,
      "sh",
      "-c",
      'read -r kura_pid rest < /proc/1/task/1/children; cat "/proc/$kura_pid/stat"; getconf CLK_TCK',
    ),
    memory: docker(
      "exec",
      `${prefix}-${n}`,
      "sh",
      "-c",
      'read -r kura_pid rest < /proc/1/task/1/children; cat "/proc/$kura_pid/smaps_rollup"',
    ),
    disk: docker("exec", `${prefix}-${n}`, "du", "-sb", "/data"),
    net: docker("exec", `${prefix}-${n}`, "cat", "/proc/net/dev"),
  }));
}
for (const port of [4291, 4292, 4293]) {
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
  for (const port of [4291, 4292, 4293])
    fs.writeFileSync(
      `${out}/${sequence}-${port}.prom`,
      await (await fetch(`http://127.0.0.1:${port}/metrics`)).text(),
    );
  sequence++;
}
await sample();
console.log("all nodes ready; starting seed and resource sampling");
const before = hostStats();
let sampling = Promise.resolve();
const interval = setInterval(() => {
  sampling = sampling.then(sample);
}, 2000);
for (let i = 0; i < 64; i++) await write(`seed-${i}`);
for (const port of [4291, 4292, 4293]) {
  for (let i = 0; i < 64; i++) {
    for (let retry = 0; retry < 60; retry++) {
      const r = await fetch(url(port, "seed-" + i), { headers });
      const data = Buffer.from(await r.arrayBuffer());
      if (r.ok && data.equals(body)) break;
      if (retry === 59) throw Error("replication did not converge: " + port + "/" + i);
      await sleep(1000);
    }
  }
}
const start = Date.now();
console.log("seed corpus replicated; starting sustained load");
await Promise.all([
  (async () => {
    for (let i = 0; i < 256; i++) {
      await sleep(Math.max(0, start + i * 250 - Date.now()));
      await write(`load-${i}`);
    }
  })(),
  ...[4291, 4292, 4293].map(async (port) => {
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
