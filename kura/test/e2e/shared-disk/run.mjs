import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { execFileSync, spawn } from "node:child_process";

// Run as root in a disposable LOCAL Linux VM with XFS quota support. All
// storage is a bounded loop image created here; no host block device is used.
const kura = process.env.KURA_BINARY;
const agent = process.env.KURA_DISK_AGENT_BINARY;
assert(kura && agent, "KURA_BINARY and KURA_DISK_AGENT_BINARY are required");
const root = fs.mkdtempSync("/var/tmp/kura-shared-disk-");
const mount = path.join(root, "data");
const control = path.join(root, "control");
const inventory = path.join(root, "volumes.json");
const GiB = 1024 ** 3;
const children = [];
const descriptors = [];
const cgroups = [];
let mounted = false;
const run = (cmd, ...args) => execFileSync(cmd, args, { encoding: "utf8", maxBuffer: 8 * 1024 ** 2 }).trim();
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(label, fn, seconds = 120) {
  const deadline = Date.now() + seconds * 1000;
  while (Date.now() < deadline) {
    if (await fn()) return;
    await sleep(500);
  }
  throw Error(`Timed out: ${label}; evidence: ${root}`);
}
function launch(name, command, args = [], env = {}) {
  const log = fs.openSync(path.join(root, `${name}.log`), "a");
  const child = spawn(command, args, { env: { ...process.env, ...env }, stdio: ["ignore", log, log] });
  fs.closeSync(log);
  children.push(child);
  return child;
}
const volumes = ["a", "b"].map(id => ({ id, path: path.join(mount, id), floor_bytes: 4 * GiB, ceiling_bytes: 8 * GiB }));
function startAgent() {
  return launch("allocator", agent, ["--inventory", inventory, "--mount", mount,
    "--control-dir", control, "--lock", path.join(root, "quota.lock"),
    "--reserve-bytes", `${2 * GiB}`, "--capacity-bytes", `${12 * GiB}`]);
}
function budget(id) { try { return JSON.parse(fs.readFileSync(path.join(control, `${id}.json`))); } catch { return null; } }
function quota(id) {
  const report = run("xfs_quota", "-x", "-c", "report -p -b -n -N", mount);
  const fields = report.split("\n").map(line => line.trim().split(/\s+/)).find(fields => fields[0].replace(/^#/, "") === `${id}`);
  assert(fields, report);
  return { used: Number(fields[1]) * 1024, limit: Number(fields[3]) * 1024 };
}
const encode = value => Buffer.from(JSON.stringify(value)).toString("base64url");
const input = `${encode({ alg: "HS256", typ: "JWT" })}.${encode({ sub: "local-test", type: "user",
  scopes: ["project_cache_write"], cache_grants: { project: { read: ["default/shared"], write: ["default/shared"] } }, exp: 4000000000 })}`;
const token = `${input}.${crypto.createHmac("sha256", "local-shared-disk-only").update(input).digest("base64url")}`;
const headers = { authorization: `Bearer ${token}`, "content-type": "application/octet-stream" };
const body = Buffer.alloc(8 * 1024 ** 2, 73);
const base = id => `http://127.0.0.1:${id === "a" ? 4301 : 4302}`;
const uri = (id, key) => `${base(id)}/api/cache/gradle/${key}?tenant_id=default&namespace_id=shared`;
async function put(id, key) {
  let lastFailure;
  for (let n = 0; n < 45; n++) {
    let response;
    try {
      response = await fetch(uri(id, key), { method: "PUT", headers, body, signal: AbortSignal.timeout(30_000) });
    } catch (error) {
      // Early write rejection can close the connection while the body is
      // still streaming. Retry with the same bounded policy as a 503.
      lastFailure = error;
      await sleep(1000);
      continue;
    }
    if (response.ok) { await response.arrayBuffer(); return; }
    const text = await response.text();
    lastFailure = `${response.status}: ${text}`;
    if (!text.includes("disk") && !text.includes("capacity")) throw Error(`PUT ${id}: ${response.status} ${text}`);
    await sleep(1000);
  }
  throw Error(`PUT ${id}/${key} never recovered: ${lastFailure}`);
}
async function verify(id, key) {
  const response = await fetch(uri(id, key), { headers, signal: AbortSignal.timeout(10_000) });
  assert.equal(response.status, 200, `${id}/${key}`);
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), body);
}
async function stop(child) {
  if (child.exitCode !== null) return;
  child.kill("SIGTERM");
  await until("process exit", () => child.exitCode !== null || child.signalCode !== null, 30);
}

try {
  fs.mkdirSync(mount); fs.mkdirSync(control);
  run("truncate", "-s", "16G", path.join(root, "disk.img"));
  run("mkfs.xfs", "-f", path.join(root, "disk.img"));
  run("mount", "-o", "loop,prjquota", path.join(root, "disk.img"), mount); mounted = true;
  for (const [index, volume] of volumes.entries()) {
    fs.mkdirSync(volume.path);
    run("xfs_quota", "-x", "-c", `project -s -p ${volume.path} ${1001 + index}`, mount);
    run("xfs_quota", "-x", "-c", `limit -p bsoft=4g bhard=4g ${1001 + index}`, mount);
  }
  fs.writeFileSync(inventory, JSON.stringify(volumes));
  let allocator = startAgent();
  await until("initial floors", () => volumes.every(v => budget(v.id)?.allow_writes));
  for (const [index, volume] of volumes.entries()) {
    // Kura reads the container-root cgroup. Give native VM processes the same
    // cgroup/mount namespace and real memory bound as deployed containers.
    fs.writeFileSync("/sys/fs/cgroup/cgroup.subtree_control", "+memory");
    const cgroup = `/sys/fs/cgroup/kura-disk-${process.pid}-${volume.id}`;
    fs.mkdirSync(cgroup); cgroups.push(cgroup);
    fs.writeFileSync(path.join(cgroup, "memory.max"), `${1536 * 1024 ** 2}`);
    launch(volume.id, "/bin/sh", ["-ec", 'echo $$ > "$TEST_CGROUP/cgroup.procs"; exec unshare --mount --cgroup /bin/sh -ec \'mount --make-rprivate /; umount /sys/fs/cgroup; mount -t cgroup2 none /sys/fs/cgroup; exec "$KURA_BINARY"\''], {
      TEST_CGROUP: cgroup, KURA_BINARY: kura,
      KURA_PORT: `${4301 + index}`, KURA_INTERNAL_PORT: `${7441 + index}`,
      KURA_NODE_URL: `http://127.0.0.1:${7441 + index}`, KURA_PEERS: `http://127.0.0.1:${7441 + index}`,
      KURA_TENANT_ID: "default", KURA_REGION: "local", KURA_DATA_DIR: volume.path,
      KURA_TMP_DIR: path.join(volume.path, "tmp"), KURA_TMP_DIR_MAX_BYTES: `${128 * 1024 ** 2}`,
      KURA_CAS_CAPACITY_BYTES: `${Math.floor(8 * GiB * 0.8)}`, KURA_MEMORY_LIMIT_BYTES: `${GiB}`,
      KURA_AUTH_JWT_SECRET: "local-shared-disk-only", KURA_DISK_VOLUME_ID: volume.id,
      KURA_DISK_BUDGET_FILE: path.join(control, `${volume.id}.json`),
      KURA_OTEL_SERVICE_NAME: "shared-disk-e2e", KURA_OTEL_DEPLOYMENT_ENVIRONMENT: "local", RUST_LOG: "warn",
    });
    await until(`${volume.id} ready`, async () => {
      try {
        const response = await fetch(`${base(volume.id)}/ready`, { headers: { connection: "close" }, signal: AbortSignal.timeout(5000) });
        await response.arrayBuffer();
        return response.ok;
      } catch { return false; }
    });
  }
  // A occupies the shared space while B's unused floor remains reserved.
  for (let n = 0; n < 900; n += 4) {
    await Promise.all(Array.from({ length: 4 }, (_, i) => put("a", `a-${n + i}`)));
  }
  await until("A grows above floor", () => budget("a").current_bytes === 8 * GiB);
  assert.equal(budget("b").current_bytes, 4 * GiB);
  await verify("a", "a-899");
  console.log("PASS: demand grows A while preserving B's unused floor");

  // Model a retained, unlinked file that is invisible to a directory walk.
  // The runtime deliberately keeps rotation/metadata slack below its quota;
  // fill part of that slack so the held inode really crosses the next target.
  const retained = path.join(mount, "a", "retained-open");
  const retainedBytes = Math.max(1024 ** 2, 7 * GiB - quota(1001).used);
  run("fallocate", "-l", `${retainedBytes}`, retained);
  descriptors.push(fs.openSync(retained, "r"));
  fs.unlinkSync(retained);

  // Hold real file descriptors across unlink. Quota usage must remain
  // charged until they close, regardless of the runtime's requested shrink.
  for (const file of fs.readdirSync(path.join(mount, "a", "segments"))) {
    const full = path.join(mount, "a", "segments", file);
    if (fs.statSync(full).isFile()) descriptors.push(fs.openSync(full, "r"));
  }
  assert(descriptors.length > 0);
  assert(quota(1001).used >= 7 * GiB, "held blocks must cross the future fair target");
  let writesB = 0;
  async function writeBatchB() {
    const count = Math.min(4, 650 - writesB);
    await Promise.all(Array.from({ length: count }, (_, i) => put("b", `b-${writesB + i}`)));
    writesB += count;
  }
  while (writesB < 650) {
    await writeBatchB();
    // Once both demand the fair share, inspect the blocked transfer before
    // filling B further: its growth intentionally waits for held blocks.
    if (budget("a").target_bytes < budget("a").current_bytes && quota(1001).used > budget("a").target_bytes) break;
  }
  await until("A asked to reclaim", () => budget("a").target_bytes < budget("a").current_bytes);
  await sleep(4000);
  const held = { a: budget("a"), b: budget("b"), quotaA: quota(1001), quotaB: quota(1002) };
  assert(held.quotaA.used > held.a.target_bytes, "open files must retain enough blocks to block reassignment");
  assert(held.a.current_bytes + held.b.current_bytes <= 12 * GiB);
  assert(held.b.current_bytes < 6 * GiB, "B must wait for A's occupied blocks");
  fs.writeFileSync(path.join(root, "held.json"), JSON.stringify(held, null, 2));
  console.log("PASS: unlinked open files remain charged and block growth");

  const previousGeneration = budget("a").generation;
  await stop(allocator); allocator = startAgent();
  await until("allocator restart", () => budget("a").generation > previousGeneration && budget("a").expires_ms > Date.now() + 5000);
  assert(budget("b").current_bytes < 6 * GiB);
  console.log("PASS: restart does not reissue occupied capacity");

  for (const fd of descriptors.splice(0)) fs.closeSync(fd);
  while (writesB < 650) await writeBatchB();
  await until("physical reclaim funds waiting demand", () => budget("a").current_bytes <= 6 * GiB && budget("b").current_bytes >= 6 * GiB);
  assert(quota(1001).used <= 6 * GiB);
  assert(budget("a").current_bytes + budget("b").current_bytes <= 12 * GiB);
  await verify("a", "a-899"); await verify("b", "b-649");
  console.log("PASS: released blocks fund B's growth; recent cache hits survive");

  // Agent loss expires authorization without deleting existing data.
  await stop(allocator); await sleep(17_000);
  const refused = await fetch(uri("b", "expired"), { method: "PUT", headers, body, signal: AbortSignal.timeout(30_000) }).catch(() => null);
  assert(!refused?.ok, "expired authorization must refuse growth");
  if (refused) await refused.arrayBuffer();
  const absent = await fetch(uri("b", "expired"), { headers, signal: AbortSignal.timeout(10_000) });
  assert.equal(absent.status, 404, "refused write must not commit"); await absent.arrayBuffer();
  await verify("b", "b-649");
  allocator = startAgent();
  await until("renewed authorization", () => budget("b").expires_ms > Date.now() + 5000);
  await put("b", "recovered"); await verify("b", "recovered");
  console.log("PASS: agent loss blocks writes, preserves reads, and recovers");
  fs.writeFileSync(path.join(root, "result.json"), JSON.stringify({ passed: true, held, final: volumes.map(v => budget(v.id)) }, null, 2));
  console.log(`Evidence: ${root}`);
} finally {
  for (const fd of descriptors) fs.closeSync(fd);
  for (const child of children.reverse()) {
    try { await stop(child); } catch { child.kill("SIGKILL"); }
  }
  if (mounted) run("umount", mount);
  for (const cgroup of cgroups) fs.rmdirSync(cgroup);
  fs.rmSync(path.join(root, "disk.img"), { force: true });
}
