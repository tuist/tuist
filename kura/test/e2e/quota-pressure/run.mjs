import assert from "node:assert/strict";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import fs from "node:fs";

// A disposable, enforced filesystem limit exercises statvfs without host disk
// devices or privileged containers. The filler models metadata outside CAS.
// Requires an 8 GiB Docker VM. Run each image sequentially on the same host.
const image = process.env.KURA_IMAGE || "kura:e2e";
const sourceImage = process.env.KURA_QUOTA_SOURCE_IMAGE || image;
const expectBlocked = process.env.KURA_QUOTA_EXPECT_BLOCKED === "1";
const prefix = `kura-quota-${process.pid}`;
const source = `${prefix}-source`;
const target = `${prefix}-target`;
const docker = (...args) =>
  execFileSync("docker", args, {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  }).trim();
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const encode = (value) =>
  Buffer.from(JSON.stringify(value)).toString("base64url");
const signingInput = `${encode({ alg: "HS256", typ: "JWT" })}.${encode({
  sub: "quota-test",
  type: "user",
  scopes: ["project_cache_write"],
  cache_grants: {
    project: { read: ["default/quota"], write: ["default/quota"] },
  },
  exp: 4000000000,
})}`;
const token = `${signingInput}.${crypto.createHmac("sha256", "local-quota-test-only").update(signingInput).digest("base64url")}`;
const headers = {
  authorization: `Bearer ${token}`,
  "content-type": "application/octet-stream",
};
const body = Buffer.alloc(8 * 1024 * 1024, 73);
const uri = (base, index) =>
  `${base}/api/cache/gradle/key-${index}?tenant_id=default&namespace_id=quota`;
const output = process.env.KURA_QUOTA_OUTPUT;
if (output) fs.mkdirSync(output, { recursive: true });

function start(name, limited) {
  const env = {
    KURA_PORT: "4000",
    KURA_INTERNAL_PORT: "7443",
    KURA_TENANT_ID: "default",
    KURA_REGION: "eu-west",
    KURA_NODE_URL: `http://${name}:7443`,
    KURA_PEERS: `http://${source}:7443,http://${target}:7443`,
    KURA_DATA_DIR: "/data",
    KURA_TMP_DIR: "/data/tmp",
    KURA_TMP_DIR_MAX_BYTES: "134217728",
    KURA_CAS_CAPACITY_BYTES: "3221225472",
    KURA_AUTH_JWT_SECRET: "local-quota-test-only",
    KURA_MEMORY_LIMIT_BYTES: limited ? "7516192768" : "1073741824",
    // tmpfs is charged as shmem; keep this filesystem test out of memory shedding.
    ...(limited
      ? {
          KURA_MEMORY_SOFT_LIMIT_BYTES: "6442450944",
          KURA_MEMORY_HARD_LIMIT_BYTES: "6979321856",
        }
      : {}),
    KURA_OTEL_SERVICE_NAME: "quota-test",
    KURA_OTEL_DEPLOYMENT_ENVIRONMENT: "local",
  };
  docker(
    "run",
    "-d",
    "--name",
    name,
    "--network",
    prefix,
    "-p",
    "127.0.0.1::4000",
    "--memory",
    limited ? "7g" : "1536m",
    "--cpus",
    "2",
    ...(limited ? ["--tmpfs", "/data:rw,size=5g"] : []),
    ...Object.entries(env).flatMap(([key, value]) => ["-e", `${key}=${value}`]),
    limited ? image : sourceImage,
  );
  return `http://${docker("port", name, "4000/tcp")}`;
}

try {
  docker("network", "create", prefix);
  const a = start(source, false);
  const b = start(target, true);
  for (const base of [a, b]) {
    let ready = false;
    for (let attempt = 0; attempt < 90; attempt++) {
      try {
        ready = (await fetch(`${base}/ready`)).ok;
      } catch {}
      if (ready) break;
      await sleep(1000);
    }
    assert(ready, `${base} did not become ready`);
  }
  docker(
    "exec",
    target,
    "dd",
    "if=/dev/zero",
    "of=/data/metadata-pressure",
    "bs=1M",
    "count=1280",
    "status=none",
  );
  for (let index = 0; index < 512; index++) {
    const response = await fetch(uri(a, index), {
      method: "PUT",
      headers,
      body,
    });
    if (!response.ok)
      throw new Error(
        `source write ${index}: ${response.status} ${await response.text()}`,
      );
    await response.arrayBuffer();
  }
  let replicated = false;
  for (let attempt = 0; attempt < 60; attempt++) {
    const response = await fetch(uri(b, 511), { headers });
    const received = Buffer.from(await response.arrayBuffer());
    if (response.ok) {
      assert.deepEqual(received, body);
      replicated = true;
      break;
    }
    assert.equal(response.status, 404);
    await sleep(1000);
  }
  const logs = docker("logs", target);
  const metrics = await (await fetch(`${b}/metrics`)).text();
  const result = {
    image,
    sourceImage,
    expectBlocked,
    replicated,
    diskFull: logs.includes("disk_full"),
    filesystem: docker("exec", target, "df", "-B1", "/data"),
    disk: docker("exec", target, "du", "-sb", "/data"),
    rollout: await (await fetch(`${b}/status/rollout`)).json(),
  };
  if (output) {
    fs.writeFileSync(`${output}/result.json`, JSON.stringify(result, null, 2));
    fs.writeFileSync(`${output}/target.prom`, metrics);
    fs.writeFileSync(`${output}/target.log`, logs);
  }
  console.log(JSON.stringify(result));
  assert.equal(replicated, !expectBlocked);
  if (expectBlocked)
    assert(
      result.diskFull,
      "baseline must fail specifically at the disk guard",
    );
  else {
    const evicted = metrics.match(
      /kura_segment_evicted_artifacts_total_total[^\n]* ([0-9]+)/,
    );
    assert(
      evicted && Number(evicted[1]) > 0,
      "replication must exercise reclamation",
    );
  }
} finally {
  for (const name of [source, target]) {
    try {
      docker("rm", "-f", name);
    } catch {}
  }
  try {
    docker("network", "rm", prefix);
  } catch {}
}
