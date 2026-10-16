import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";
import { parseArgs } from "node:util";
import { profile, classify, runtimeResources } from "./profile.mjs";
import { diskUsage } from "./disk-usage.mjs";

const { values: options } = parseArgs({
  options: Object.fromEntries(
    [
      "context",
      "namespace",
      "node",
      "output",
      "profile",
      "scenario",
      "source-image",
      "warm-image",
      "candidate-image",
      "expect",
    ].map((name) => [name, { type: "string" }]),
  ),
});
const context = options.context,
  namespace = options.namespace;
assert.equal(
  context,
  "tuist-k8s-staging.taild6d7bb.ts.net",
  "this fixture only permits the staging context",
);
assert.equal(
  namespace,
  "kura-spec98",
  "use the reserved qualification namespace",
);
assert(
  options.node && options.output && path.isAbsolute(options.output),
  "explicit node and absolute output required",
);
assert(
  ["fresh", "fragmented"].includes(options.scenario),
  "choose fresh or fragmented",
);
assert(
  ["pass", "repair-timeout"].includes(options.expect),
  "choose pass or repair-timeout",
);
for (const key of ["source-image", "warm-image", "candidate-image"])
  assert(
    /^ghcr\.io\/tuist\/kura:(?:[0-9][a-zA-Z0-9.\-]+|sha-[a-f0-9]+|qualification-[a-f0-9]{40})$/.test(
      options[key] ?? "",
    ),
    `explicit pinned ${key} required`,
  );
assert.notEqual(
  options["warm-image"],
  options["candidate-image"],
  "reuse test must replace the warm runtime",
);
const p = profile(options.profile),
  output = options.output;
assert(
  p.name !== "records" || options.scenario === "fresh",
  "the record-count diagnostic requires the fresh scenario",
);
assert(
  !fs.existsSync(output),
  "output must be new; never overwrite earlier evidence",
);
fs.mkdirSync(output, { recursive: true });
const name = `kura-handover-repro-${randomUUID().slice(0, 8)}`;
const labels = { "qualification.kura.tuist.dev/run": name };
const config = { ...options, name };
const save = (file, data) =>
  fs.writeFileSync(
    `${output}/${file}`,
    typeof data === "string" ? data : JSON.stringify(data, null, 2),
  );
const k = (...args) =>
  execFileSync(
    "kubectl",
    [
      "--context",
      context,
      "--namespace",
      namespace,
      "--request-timeout=30s",
      ...args,
    ],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024, timeout: 45000 },
  );
function kFile(file, ...args) {
  const temporary = `${output}/${file}.partial`;
  const fd = fs.openSync(temporary, "w");
  try {
    execFileSync(
      "kubectl",
      [
        "--context",
        context,
        "--namespace",
        namespace,
        "--request-timeout=30s",
        ...args,
      ],
      {
        stdio: ["ignore", fd, "pipe"],
        timeout: 60000,
        maxBuffer: 1024 * 1024,
      },
    );
    fs.renameSync(temporary, `${output}/${file}`);
  } finally {
    fs.closeSync(fd);
  }
}
const get = (kind, resource) =>
  JSON.parse(k("get", kind, resource, "-o", "json"));
const metadata = (resource) => ({ name: resource, namespace, labels });
const owned = [];
function create(object) {
  const file = `${output}/${object.kind}-${object.metadata.name}.json`;
  fs.writeFileSync(file, JSON.stringify(object, null, 2));
  const created = JSON.parse(k("create", "-f", file, "-o", "json"));
  owned.push({
    kind: object.kind,
    name: object.metadata.name,
    uid: created.metadata.uid,
  });
  save("owned.json", owned);
  return created;
}
function ownedObject(item) {
  const current = get(item.kind, item.name);
  assert.equal(
    current.metadata.uid,
    item.uid,
    "resource UID changed; refusing mutation",
  );
  assert.equal(
    current.metadata.labels["qualification.kura.tuist.dev/run"],
    name,
  );
  return current;
}
let interrupted = false;
for (const signal of ["SIGINT", "SIGTERM"])
  process.on(signal, () => {
    interrupted = true;
  });
function checkInterrupt() {
  assert(!interrupted, "fixture interrupted");
}
const podName = (container) =>
  ["source", "target"].includes(container) ? `${name}-${container}` : name;
function exec(container, ...args) {
  return k("exec", podName(container), "-c", container, "--", ...args);
}
const logs = (container) =>
  k("logs", podName(container), "-c", container, "--timestamps=false");
function verifyMemoryBudget() {
  for (const replica of ["source", "target"]) {
    assert.equal(
      Number(exec(replica, "cat", "/sys/fs/cgroup/memory.min")),
      1073741824,
      "kernel memory floor differs from production",
    );
    assert.equal(
      Number(exec(replica, "cat", "/sys/fs/cgroup/memory.max")),
      4294967296,
      "kernel memory ceiling differs from production",
    );
  }
}

function snapshot(phase) {
  const sample = { time: Date.now(), phase, replicas: [] };
  for (const replica of ["source", "target"])
    sample.replicas.push({
      replica,
      cpu: exec(replica, "cat", "/sys/fs/cgroup/cpu.stat"),
      memory: exec(replica, "cat", "/sys/fs/cgroup/memory.stat"),
      memoryMin: exec(replica, "cat", "/sys/fs/cgroup/memory.min"),
      memoryMax: exec(replica, "cat", "/sys/fs/cgroup/memory.max"),
      memoryEvents: exec(replica, "cat", "/sys/fs/cgroup/memory.events"),
      ...diskUsage(() => exec(replica, "du", "-sk", "/data")),
      net: exec(replica, "cat", "/proc/net/dev"),
    });
  fs.appendFileSync(`${output}/resources.jsonl`, JSON.stringify(sample) + "\n");
}

let podCreated = false,
  evidenceCollected = false,
  result,
  failure;
const volumes = [];
function rememberVolume(item) {
  const claim = ownedObject(item);
  if (!claim.spec.volumeName) return;
  const volume = get("pv", claim.spec.volumeName);
  assert.equal(volume.spec.claimRef.uid, claim.metadata.uid);
  assert.equal(
    volume.spec.persistentVolumeReclaimPolicy,
    "Delete",
    "fixture requires disposable storage",
  );
  if (!volumes.some((v) => v.name === volume.metadata.name))
    volumes.push({ name: volume.metadata.name, uid: volume.metadata.uid });
  save(`PV-${volume.metadata.name}.json`, volume);
}
async function collect() {
  if (!podCreated) return;
  save(
    "pods-final.json",
    owned.filter((o) => o.kind === "Pod").map(ownedObject),
  );
  for (const container of ["source", "target", "client", "proxy", "api"]) {
    try {
      kFile(
        `${container}.log`,
        "logs",
        podName(container),
        "-c",
        container,
        "--timestamps=false",
      );
      const status = get(
        "pod",
        podName(container),
      ).status.containerStatuses?.find((s) => s.name === container);
      if (status?.restartCount)
        save(
          `${container}-previous.log`,
          k("logs", podName(container), "-c", container, "--previous"),
        );
    } catch (error) {
      save(`${container}-log-error.txt`, error.message);
    }
  }
  // Only known evidence files are read; no credential directory is copied out.
  const files = JSON.parse(
    exec(
      "client",
      "node",
      "-e",
      `console.log(JSON.stringify(require('fs').readdirSync('/fixture').filter(n=>/\\.(json|jsonl)$/.test(n))))`,
    ),
  );
  for (const file of files)
    kFile(file, "exec", name, "-c", "client", "--", "cat", `/fixture/${file}`);
  for (const item of owned.filter(
    (item) => item.kind === "PersistentVolumeClaim",
  ))
    rememberVolume(item);
  evidenceCollected = true;
}
try {
  save("config.json", config);
  const node = get("node", options.node);
  save("node.json", node);
  assert(
    node.status.conditions.some(
      (c) => c.type === "Ready" && c.status === "True",
    ),
  );
  assert(
    !node.status.conditions.some(
      (c) => /Pressure$/.test(c.type) && c.status === "True",
    ),
  );
  save("node-before.txt", k("describe", "node", options.node));
  for (const args of [
    [
      "req",
      "-x509",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-keyout",
      `${output}/ca.key`,
      "-out",
      `${output}/ca.crt`,
      "-days",
      "1",
      "-subj",
      "/CN=isolated-handover-fixture",
    ],
    [
      "req",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-keyout",
      `${output}/server.key`,
      "-out",
      `${output}/server.csr`,
      "-subj",
      "/CN=kubernetes.default.svc",
    ],
  ])
    execFileSync("openssl", args, { stdio: "ignore" });
  save(
    "extensions",
    "basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:kubernetes.default.svc\n",
  );
  execFileSync(
    "openssl",
    [
      "x509",
      "-req",
      "-in",
      `${output}/server.csr`,
      "-CA",
      `${output}/ca.crt`,
      "-CAkey",
      `${output}/ca.key`,
      "-CAcreateserial",
      "-out",
      `${output}/server.crt`,
      "-days",
      "1",
      "-extfile",
      `${output}/extensions`,
    ],
    { stdio: "ignore" },
  );
  create({
    apiVersion: "v1",
    kind: "Secret",
    metadata: metadata(name),
    stringData: {
      "ca.crt": fs.readFileSync(`${output}/ca.crt`, "utf8"),
      "server.crt": fs.readFileSync(`${output}/server.crt`, "utf8"),
      "server.key": fs.readFileSync(`${output}/server.key`, "utf8"),
      token: "isolated-fixture-only",
    },
  });
  const code = Object.fromEntries(
    ["run.mjs", "profile.mjs", "proxy.mjs", "body-frame.mjs", "upload.mjs"].map(
      (file) => [file, fs.readFileSync(new URL(file, import.meta.url), "utf8")],
    ),
  );
  for (const file of ["fixture-api.mjs", "protocol.mjs"])
    code[file] = fs.readFileSync(
      new URL(`../${file}`, import.meta.url),
      "utf8",
    );
  code["config.json"] = JSON.stringify(config);
  create({
    apiVersion: "v1",
    kind: "ConfigMap",
    metadata: metadata(name),
    data: code,
  });
  for (const replica of ["source", "target"])
    create({
      apiVersion: "v1",
      kind: "PersistentVolumeClaim",
      metadata: metadata(`${name}-${replica}`),
      spec: {
        accessModes: ["ReadWriteOncePod"],
        storageClassName: "scw-local-nvme",
        resources: { requests: { storage: p.volume } },
      },
    });
  const nodeContainer = (container, script, cpu, memory) => ({
    name: container,
    image: "node:22-bookworm-slim",
    command: ["node", `/code/${script}`],
    resources: { requests: { cpu, memory }, limits: { cpu, memory } },
    volumeMounts: [
      { name: "code", mountPath: "/code", readOnly: true },
      { name: "fixture", mountPath: "/fixture" },
    ],
  });
  const runtimes = ["source", "target"].map((replica, i) => ({
    name: replica,
    image: options[i === 0 ? "source-image" : "warm-image"],
    resources: runtimeResources(p),
    env: Object.entries({
      KURA_PORT: "4000",
      KURA_INTERNAL_PORT: "7443",
      KURA_GATEWAY_GRPC_PORT: "4001",
      KURA_NODE_URL: `http://${name}-${replica}-peer:7443`,
      KURA_PEERS: `http://${name}-source-peer:7443,http://${name}-target-peer:7443`,
      KURA_TENANT_ID: "default",
      KURA_REGION: "qualification",
      KURA_DATA_DIR: "/data",
      KURA_TMP_DIR: "/data/tmp",
      KURA_CAS_CAPACITY_BYTES: String(p.capacity),
      KURA_AUTH_ENABLED: "false",
      KURA_MEMORY_LIMIT_BYTES: "4294967296",
      KURA_MEMORY_FLOOR_BYTES: "1073741824",
      KURA_SNAPSHOT_CACHE_MAX_BYTES: "67108864",
      KURA_MANIFEST_CACHE_MAX_BYTES: "33554432",
      KURA_METADATA_STORE_READ_CACHE_BYTES: "33554432",
      KURA_OTEL_SERVICE_NAME: "qualification",
      KURA_OTEL_DEPLOYMENT_ENVIRONMENT: "isolated-staging",
      KURA_REPLICATION_PULL: "true",
      KURA_BACKFILL_ENABLED: "true",
      KURA_SERVING_AUTHORITY: "qualification",
      POD_NAMESPACE: "qualification",
      KURA_INSTANCE_UID: name,
      POD_UID: `${name}-${replica}`,
      POD_NODE_NAME: `simulated-${replica}`,
    }).map(([name, value]) => ({ name, value })),
    volumeMounts: [
      { name: replica, mountPath: "/data" },
      {
        name: "credentials",
        mountPath: "/var/run/secrets/kubernetes.io/serviceaccount",
        readOnly: true,
      },
    ],
  }));
  create({
    apiVersion: "networking.k8s.io/v1",
    kind: "NetworkPolicy",
    metadata: metadata(name),
    spec: {
      podSelector: { matchLabels: labels },
      policyTypes: ["Ingress", "Egress"],
      ingress: [{ from: [{ podSelector: { matchLabels: labels } }] }],
      egress: [
        { to: [{ podSelector: { matchLabels: labels } }] },
        {
          to: [
            {
              namespaceSelector: {
                matchLabels: { "kubernetes.io/metadata.name": "kube-system" },
              },
            },
          ],
          ports: [
            { protocol: "UDP", port: 53 },
            { protocol: "TCP", port: 53 },
          ],
        },
      ],
    },
  });
  for (const replica of ["source", "target"]) {
    for (const proxy of [false, true])
      create({
        apiVersion: "v1",
        kind: "Service",
        metadata: metadata(name + "-" + replica + (proxy ? "-peer" : "")),
        spec: {
          selector: {
            ...labels,
            "qualification.kura.tuist.dev/role": proxy ? "fixture" : replica,
          },
          ports: [
            { name: "peer", port: 7443 },
            ...(!proxy
              ? [
                  { name: "http", port: 4000 },
                  { name: "grpc", port: 4001 },
                ]
              : []),
          ],
        },
      });
  }
  const pod = create({
    apiVersion: "v1",
    kind: "Pod",
    metadata: {
      ...metadata(name),
      labels: { ...labels, "qualification.kura.tuist.dev/role": "fixture" },
    },
    spec: {
      automountServiceAccountToken: false,
      terminationGracePeriodSeconds: 30,
      nodeSelector: { "kubernetes.io/hostname": options.node },
      tolerations: [
        {
          key: "tuist.dev/kura-cache",
          operator: "Equal",
          value: "true",
          effect: "NoSchedule",
        },
        {
          key: "tuist.dev/runner-tier",
          operator: "Equal",
          value: "bare-metal",
          effect: "NoSchedule",
        },
      ],
      volumes: [
        { name: "code", configMap: { name } },
        { name: "credentials", secret: { secretName: name } },
        { name: "fixture", emptyDir: { sizeLimit: "1Gi" } },
      ],
      initContainers: [
        {
          ...nodeContainer("init", "run.mjs", "100m", "128Mi"),
          command: [
            "node",
            "-e",
            "const fs=require('fs');for(const f of ['server.key','server.crt'])fs.copyFileSync('/credentials/'+f,'/fixture/'+f);fs.copyFileSync('/code/config.json','/fixture/config.json')",
          ],
          volumeMounts: [
            { name: "credentials", mountPath: "/credentials", readOnly: true },
            { name: "code", mountPath: "/code", readOnly: true },
            { name: "fixture", mountPath: "/fixture" },
          ],
        },
      ],
      containers: [
        nodeContainer("api", "fixture-api.mjs", "250m", "128Mi"),
        nodeContainer("proxy", "proxy.mjs", "1", "256Mi"),
        nodeContainer("client", "run.mjs", "2", "1Gi"),
      ],
    },
  });
  podCreated = true;
  let fixtureIP;
  const schedulingDeadline = Date.now() + 180000;
  while (Date.now() < schedulingDeadline) {
    checkInterrupt();
    fixtureIP = get("pod", name).status.podIP;
    if (fixtureIP) break;
    await sleep(2000);
  }
  assert(fixtureIP, "fixture pod did not schedule");
  for (const runtime of runtimes)
    create({
      apiVersion: "v1",
      kind: "Pod",
      metadata: {
        ...metadata(name + "-" + runtime.name),
        labels: {
          ...labels,
          "qualification.kura.tuist.dev/role": runtime.name,
        },
      },
      spec: {
        automountServiceAccountToken: false,
        terminationGracePeriodSeconds: 30,
        nodeSelector: pod.spec.nodeSelector,
        tolerations: pod.spec.tolerations,
        hostAliases: [{ ip: fixtureIP, hostnames: ["kubernetes.default.svc"] }],
        containers: [runtime],
        volumes: [
          {
            name: runtime.name,
            persistentVolumeClaim: { claimName: name + "-" + runtime.name },
          },
          { name: "credentials", secret: { secretName: name } },
        ],
      },
    });
  const podItem = owned.find(
    (item) => item.kind === "Pod" && item.name === name,
  );
  const targetItem = owned.find(
    (item) => item.kind === "Pod" && item.name === name + "-target",
  );
  const deadline = Date.now() + 2 * 3600000;
  let upgraded = false,
    lastProgress = "",
    sampleAt = 0;
  while (Date.now() < deadline) {
    checkInterrupt();
    const current = ownedObject(podItem);
    assert(
      !["Failed", "Succeeded"].includes(current.status.phase),
      `pod ended: ${current.status.phase}`,
    );
    const targetPod = ownedObject(targetItem);
    for (const obj of owned.filter((o) => o.kind === "Pod").map(ownedObject))
      for (const status of obj.status.containerStatuses ?? [])
        assert(
          status.restartCount <= (status.name === "target" && upgraded ? 1 : 0),
          `${status.name} unexpectedly restarted`,
        );
    if (
      (current.status.containerStatuses ?? []).some(
        (s) => s.name === "client" && s.state.running,
      )
    ) {
      const progress = JSON.parse(
        exec(
          "client",
          "node",
          "-e",
          "const fs=require('fs');console.log(fs.existsSync('/fixture/progress.json')?fs.readFileSync('/fixture/progress.json','utf8'):'{}')",
        ),
      );
      if (JSON.stringify(progress) !== lastProgress) {
        console.log(JSON.stringify(progress));
        lastProgress = JSON.stringify(progress);
      }
      if (progress.phase === "runtime_ready") {
        verifyMemoryBudget();
        save(
          "cpu.json",
          Object.fromEntries(
            ["source", "target"].map((replica) => {
              const info = exec(replica, "cat", "/proc/cpuinfo");
              return [
                replica,
                {
                  logicalProcessors: (info.match(/^processor\s*:/gm) ?? [])
                    .length,
                  firstProcessor: info.split(/\n\s*\n/)[0],
                },
              ];
            }),
          ),
        );
        snapshot("empty");
        exec(
          "client",
          "node",
          "-e",
          "require('fs').writeFileSync('/fixture/runtime-ready','ready')",
        );
      }
      if (progress.phase === "upgrade_requested" && !upgraded) {
        save("pod-before-upgrade.json", targetPod);
        save("target-warm.log", logs("target"));
        k(
          "patch",
          "pod",
          targetItem.name,
          "--type=json",
          "-p",
          JSON.stringify([
            { op: "test", path: "/metadata/uid", value: targetItem.uid },
            {
              op: "test",
              path: "/spec/containers/0/image",
              value: options["warm-image"],
            },
            {
              op: "replace",
              path: "/spec/containers/0/image",
              value: options["candidate-image"],
            },
          ]),
        );
        upgraded = true;
      }
      if (upgraded && !fs.existsSync(`${output}/pod-after-upgrade.json`)) {
        const old = JSON.parse(
          fs.readFileSync(`${output}/pod-before-upgrade.json`),
        );
        const before = old.status.containerStatuses.find(
          (s) => s.name === "target",
        );
        const after = targetPod.status.containerStatuses.find(
          (s) => s.name === "target",
        );
        if (
          after?.state.running &&
          after.containerID !== before.containerID &&
          after.image === options["candidate-image"]
        ) {
          save("pod-after-upgrade.json", targetPod);
          exec(
            "client",
            "node",
            "-e",
            "require('fs').writeFileSync('/fixture/upgrade-complete','ready')",
          );
        }
      }
      if (
        (progress.phase === "handover" ||
          progress.phase?.startsWith("seed-")) &&
        Date.now() > sampleAt
      ) {
        sampleAt = Date.now() + 15000;
        snapshot(progress.phase);
      }
      if (progress.phase === "measurement_ready") {
        verifyMemoryBudget();
        snapshot("before");
        exec(
          "client",
          "node",
          "-e",
          "require('fs').writeFileSync('/fixture/measurement-ready','ready')",
        );
      }
      if (progress.phase === "finished") {
        snapshot("settled");
        break;
      }
    }
    await sleep(5000);
  }
  await collect();
  assert(
    fs.existsSync(`${output}/result.json`),
    "fixture timed out before producing a result",
  );
  result = JSON.parse(
    fs.readFileSync(`${output}/result.json`, "utf8"),
    (_key, value, context) =>
      typeof value === "number" && !Number.isSafeInteger(value)
        ? JSON.rawJSON(context.source)
        : value,
  );
  assert(!result.error, result.error);
  result.classification =
    result.barrier && result.persistentChannelChecks
      ? "pass"
      : classify(
          result,
          fs.readFileSync(`${output}/source.log`, "utf8"),
          fs.readFileSync(`${output}/target.log`, "utf8"),
        );
  save("result.json", result);
  assert.equal(
    result.classification,
    options.expect,
    "observed outcome differs from the requested baseline/qualification",
  );
} catch (error) {
  failure = error;
  save("orchestrator-error.txt", error.stack);
  try {
    if (!evidenceCollected) await collect();
  } catch (collectionError) {
    save("collection-error.txt", collectionError.stack);
  }
} finally {
  const cleanup = [];
  // Remove the pod first and wait for cessation before releasing its PVCs.
  for (const item of [...owned].reverse()) {
    try {
      ownedObject(item);
      // Track reclamation even when setup or evidence collection failed early.
      if (item.kind === "PersistentVolumeClaim") rememberVolume(item);
      k("delete", item.kind, item.name, "--wait=true", "--timeout=120s");
      cleanup.push({ ...item, deleted: true });
    } catch (error) {
      cleanup.push({ ...item, error: error.message });
      // A live pod or changed UID is not permission to remove storage beneath it.
      if (item.kind === "Pod") break;
    }
  }
  save("cleanup.json", cleanup);
  if (
    cleanup.length === owned.length &&
    cleanup.every((entry) => entry.deleted)
  ) {
    const reclamation = [];
    for (const volume of volumes) {
      try {
        const until = Date.now() + 60000;
        let present;
        do {
          present = k(
            "get",
            "pv",
            volume.name,
            "--ignore-not-found",
            "-o",
            "name",
          ).trim();
          if (present) await sleep(2000);
        } while (present && Date.now() < until);
        assert(!present, "PVC removed but PV not yet reclaimed");
        reclamation.push({ ...volume, reclaimed: true });
      } catch (error) {
        reclamation.push({ ...volume, error: error.message });
        failure ??= error;
      }
    }
    save("reclamation.json", reclamation);
  }
  if (
    cleanup.length !== owned.length ||
    cleanup.some((entry) => !entry.deleted)
  )
    failure ??= new Error(`cleanup incomplete; inspect ${output}/cleanup.json`);
}
if (fs.existsSync(`${output}/result.json`)) {
  try {
    execFileSync(
      process.execPath,
      [new URL("summarize.mjs", import.meta.url).pathname, output],
      { stdio: "ignore" },
    );
  } catch (error) {
    save("summary-error.txt", error.message);
  }
}
console.log(
  JSON.stringify({
    name,
    output,
    classification: result?.classification,
    error: failure?.message,
  }),
);
if (failure) process.exitCode = 1;
