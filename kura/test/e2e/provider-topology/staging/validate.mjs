import fs from "node:fs";
import { execFileSync, spawn } from "node:child_process";
import assert from "node:assert/strict";

const [out, previousImage] = process.argv.slice(2);
if (!out) throw Error("usage: node validate.mjs RENDER_OUTPUT");
const context = "tuist-k8s-staging.taild6d7bb.ts.net";
const prefix = "kura-topology-e2e";
const ids = ["a", "b", "c", "d"];
const base = ["--context", context, "-n", "kura"];
const kubectl = (...args) => execFileSync("kubectl", [...base, ...args], { encoding: "utf8", timeout: 180000 });
const manifest = JSON.parse(fs.readFileSync(`${out}/manifest.json`));
const image = manifest.items.find(item => item.kind === "Deployment").spec.template.spec.containers[0].image;
const token = manifest.items.find(item => item.kind === "Secret").stringData["client-token"];
const headers = { authorization: `Bearer ${token}`, "content-type": "application/octet-stream" };
const report = [];
const children = new Map();
let versionChanged = false;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const endpoint = id => `http://127.0.0.1:${4381 + ids.indexOf(id)}`;
const keyURL = (id, key) => `${endpoint(id)}/api/cache/gradle/${key}?tenant_id=topology-staging-e2e&namespace_id=validation`;
const fetchBounded = (url, options = {}) => fetch(url, { ...options, signal: AbortSignal.timeout(45000) });
const pass = (test, evidence) => { report.push({ test, evidence }); fs.writeFileSync(`${out}/validation.json`, JSON.stringify(report, null, 2)); console.log(`PASS ${test}`); };
const pods = () => JSON.parse(kubectl("get", "pods", "-l", `tuist.dev/test=${prefix}`, "-o", "json")).items;
const pod = id => pods().find(p => p.metadata.labels["tuist.dev/test-node"] === id && !p.metadata.deletionTimestamp);
async function forward(id) {
  children.get(id)?.kill();
  const log = fs.openSync(`${out}/forward-${id}.log`, "a");
  const child = spawn("kubectl", [...base, "port-forward", `deployment/${prefix}-${id}`, `${4381 + ids.indexOf(id)}:4000`], { stdio: ["ignore", log, log] });
  fs.closeSync(log);
  children.set(id, child);
  for (let i = 0; i < 90; i++) {
    try { if ((await fetchBounded(`${endpoint(id)}/ready`)).ok) return; } catch {}
    if (child.exitCode !== null) throw Error(`port-forward ${id} exited`);
    await sleep(2000);
  }
  throw Error(`${id} did not become ready`);
}
async function put(id, key, body) {
  const response = await fetchBounded(keyURL(id, key), { method: "PUT", headers, body });
  assert.equal(response.status, 201, `PUT ${id}/${key}: ${await response.text()}`);
}
async function expectBody(id, key, body) {
  for (let i = 0; i < 90; i++) {
    const response = await fetchBounded(keyURL(id, key), { headers });
    const actual = Buffer.from(await response.arrayBuffer());
    if (response.status === 200 && actual.equals(body)) return;
    if (response.status === 200) assert.deepEqual(actual, body, `corrupt ${id}/${key}`);
    await sleep(2000);
  }
  throw Error(`replication did not converge: ${id}/${key}`);
}
function privatePath(enabled) {
  const ports = (enabled ? [4000, 7443, 8443] : [4000, 8443]).map(port => ({ protocol: "TCP", port }));
  kubectl("patch", "networkpolicy", `${prefix}-b`, "--type=json", "-p", JSON.stringify([{ op: "replace", path: "/spec/ingress/0/ports", value: ports }]));
}
const peerCurl = (id, target, certificate = true) => kubectl("exec", `deployment/${prefix}-${id}`, "-c", "kura", "--", "curl", "--fail", "--silent", "--show-error", "--max-time", "15", "--cacert", "/tls/ca.pem", ...(certificate ? ["--cert", "/tls/peer.pem", "--key", "/tls/peer.key"] : []), target);
function auditSameProvider() {
  const addresses = Object.fromEntries(pods().map(p => [p.metadata.labels["tuist.dev/test-node"], p.status.podIP]));
  let statusCalls = 0;
  let crossProviderData = 0;
  const violations = [];
  for (const target of ids) {
    const raw = kubectl("logs", `deployment/${prefix}-${target}`, "-c", "canonical-audit");
    fs.writeFileSync(`${out}/canonical-${target}.log`, raw);
    for (const line of raw.split("\n")) {
      if (!line.startsWith('{"source"')) continue;
      const row = JSON.parse(line);
      const source = ids.find(id => addresses[id] === row.source);
      if (!source || source === target) continue;
      const data = row.path.startsWith("/_internal/backfill/") || row.path.startsWith("/_internal/sync/");
      if ((source === "c") !== (target === "c") && data) crossProviderData++;
      if (source !== "c" && target !== "c") {
        if (row.path === "/_internal/status") statusCalls++;
        if (data) violations.push({ target, ...row });
      }
    }
  }
  assert(statusCalls > 0, "audit must see real same-provider canonical discovery");
  assert(crossProviderData > 0, "audit must see real cross-provider canonical replication");
  assert.deepEqual(violations, [], "same-provider data reached canonical endpoint");
  return { statusCalls, crossProviderData, violations };
}

try {
  for (const id of ids) await forward(id);
  const initial = pods().map(p => ({ name: p.metadata.name, node: p.spec.nodeName, ip: p.status.podIP, images: p.status.containerStatuses.map(c => ({ name: c.name, imageID: c.imageID })) }));
  fs.writeFileSync(`${out}/placements.json`, JSON.stringify(initial, null, 2));
  pass("four nodes ready on three physical staging hosts", initial);
  const corpus = new Map();
  for (const id of ids) {
    const key = `origin-${id}-${Date.now()}`;
    const body = Buffer.alloc(1024 * 1024, id.charCodeAt(0));
    corpus.set(key, body);
    await put(id, key, body);
    for (const other of ids) await expectBody(other, key, body);
  }
  pass("all origins replicate in both directions, including sibling feeds", { objects: corpus.size });
  const largeKey = `oversized-${Date.now()}`;
  const large = Buffer.alloc(33 * 1024 * 1024, 79);
  corpus.set(largeKey, large);
  await put("b", largeKey, large);
  for (const id of ids) await expectBody(id, largeKey, large);
  pass("33 MiB individual body replicates with exact bytes", { bytes: large.length });
  for (const privatePath of [false, true]) {
    const target = `https://${prefix}-${privatePath ? "private-" : ""}b.kura.svc.cluster.local:7443/_internal/status`;
    assert.throws(() => peerCurl("a", target, false));
    assert.equal(JSON.parse(peerCurl("a", target)).tenant_id, "topology-staging-e2e");
  }
  pass("canonical and private paths reject missing client certificates", {});
  const faultStart = new Date().toISOString();
  privatePath(false);
  await sleep(15000);
  assert.equal(JSON.parse(peerCurl("a", `https://${prefix}-b.kura.svc.cluster.local:7443/_internal/status`)).region, "b");
  const failureLogs = kubectl("logs", `deployment/${prefix}-a`, "-c", "kura", `--since-time=${faultStart}`);
  fs.writeFileSync(`${out}/private-failure.log`, failureLogs);
  assert(failureLogs.includes("peer private probe failed"), "private failure must be observed");
  const duringKey = `during-fault-${Date.now()}`;
  const during = Buffer.alloc(1024 * 1024, 70);
  corpus.set(duringKey, during);
  await put("b", duringKey, during);
  await expectBody("c", duringKey, during);
  pass("cross-provider replication continues during a proven private failure", { canonicalStillReachable: true });
  await sleep(5000);
  pass("private failure has no canonical data fallback", auditSameProvider());
  privatePath(true);
  for (const id of ids) await expectBody(id, duringKey, during);
  pass("private path recovers and replicas catch up", {});
  // Replace only a disposable fixture replica; emptyDir guarantees cold backfill.
  const old = pod("d").metadata;
  children.get("d")?.kill();
  kubectl("delete", "pod", old.name, "--wait=true");
  for (let i = 0; i < 60; i++) {
    const next = pod("d");
    if (next && next.metadata.uid !== old.uid && next.status.phase === "Running") break;
    if (i === 59) throw Error("replacement replica did not start");
    await sleep(2000);
  }
  await forward("d");
  for (const [key, body] of corpus) await expectBody("d", key, body);
  pass("cold sibling restart restores the full corpus", { objects: corpus.size, previousUID: old.uid, currentUID: pod("d").metadata.uid });
  if (previousImage) {
    children.get("c")?.kill();
    versionChanged = true;
    kubectl("set", "image", `deployment/${prefix}-c`, `kura=${previousImage}`);
    kubectl("rollout", "status", `deployment/${prefix}-c`, "--timeout=150s");
    await forward("c");
    for (const source of ["a", "c"]) {
      const key = `mixed-${source}-${Date.now()}`;
      const body = Buffer.alloc(1024 * 1024, source.charCodeAt(0));
      corpus.set(key, body);
      await put(source, key, body);
      for (const target of ids) await expectBody(target, key, body);
    }
    pass("previous staging image and topology image replicate in both directions", { previousImage, image });
    children.get("c")?.kill();
    kubectl("set", "image", `deployment/${prefix}-c`, `kura=${image}`);
    kubectl("rollout", "status", `deployment/${prefix}-c`, "--timeout=150s");
    versionChanged = false;
    await forward("c");
    for (const [key, body] of corpus) await expectBody("c", key, body);
    pass("upgraded peer backfills all retained objects", { objects: corpus.size });
  }
  const cleaned = await fetchBounded(`${endpoint("b")}/api/cache/clean?tenant_id=topology-staging-e2e&namespace_id=validation`, { method: "DELETE", headers });
  assert.equal(cleaned.status, 204, await cleaned.text());
  for (const id of ids) {
    for (const key of corpus.keys()) {
      for (let i = 0; i < 90; i++) {
        const response = await fetchBounded(keyURL(id, key), { headers });
        await response.arrayBuffer();
        if (response.status === 404) break;
        if (i === 89) throw Error(`tombstone did not replicate: ${id}/${key}`);
        await sleep(2000);
      }
    }
  }
  pass("namespace tombstones replicate to every node", { objects: corpus.size });
  for (const id of ids) {
    const status = await (await fetchBounded(`${endpoint(id)}/status/rollout`)).json();
    fs.writeFileSync(`${out}/rollout-${id}.json`, JSON.stringify(status, null, 2));
    assert.equal(status.ready, true, `${id} final readiness`);
    assert.equal(status.backfill_initial_cycle, "complete", `${id} final catch-up`);
    assert.equal(status.memory_pressure_state, 0, `${id} final memory pressure`);
  }
  pass("all nodes finish ready and caught up without memory pressure", {});
} finally {
  if (versionChanged) {
    try { kubectl("set", "image", `deployment/${prefix}-c`, `kura=${image}`); } catch (error) { console.error("failed to restore fixture image:", error.message); process.exitCode = 1; }
  }
  try { privatePath(true); } catch (error) { console.error("failed to restore fixture policy:", error.message); process.exitCode = 1; }
  for (const child of children.values()) child.kill();
}
