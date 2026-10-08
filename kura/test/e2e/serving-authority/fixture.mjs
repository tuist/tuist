import fs from "node:fs";
import path from "node:path";
import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";

export async function fixture(
  image,
  mode,
  output,
  { limitedTarget = false } = {},
) {
  fs.mkdirSync(output, { recursive: true });
  const prefix = `spec98-mesh-${process.pid}`,
    names = [`${prefix}-a`, `${prefix}-b`],
    ports = [19510, 19511];
  const docker = (...args) =>
    execFileSync("docker", ["--context", "default", ...args], {
      encoding: "utf8",
      maxBuffer: 8 * 1024 * 1024,
    });
  const created = [],
    api = `${prefix}-api`,
    urls = ports.map((p) => `http://127.0.0.1:${p}`);
  const report = async (i) =>
    JSON.parse(
      await (
        await fetch(`${urls[i]}/status/rollout`, {
          signal: AbortSignal.timeout(5000),
        })
      ).text(),
      (_key, value, context) =>
        typeof value === "number" && !Number.isSafeInteger(value)
          ? JSON.rawJSON(context.source)
          : value,
    );
  const grant = (g) => {
    fs.writeFileSync(path.join(output, "grant.tmp"), JSON.stringify(g));
    fs.renameSync(
      path.join(output, "grant.tmp"),
      path.join(output, "grant.json"),
    );
  };
  const metric = async (i) =>
    await (
      await fetch(`${urls[i]}/metrics`, { signal: AbortSignal.timeout(5000) })
    ).text();
  const snapshot = () =>
    names.map((name) => ({
      name,
      cpu: docker("exec", name, "cat", "/sys/fs/cgroup/cpu.stat"),
      disk:
        Number(docker("exec", name, "du", "-sk", "/data").split(/\s/)[0]) *
        1024,
      net: docker("exec", name, "cat", "/proc/net/dev"),
    }));
  const logs = (name) => {
    const result = spawnSync("docker", ["--context", "default", "logs", name], {
      encoding: "utf8",
      maxBuffer: 32 * 1024 * 1024,
    });
    return (result.stdout ?? "") + (result.stderr ?? "");
  };
  function close() {
    for (const name of created.reverse()) {
      try {
        fs.writeFileSync(`${output}/${name}.log`, logs(name));
      } catch {}
      try {
        docker("rm", "-f", name);
      } catch {}
    }
    try {
      docker("network", "rm", prefix);
    } catch {}
  }
  try {
    docker("network", "create", prefix);
    if (mode === "active") {
      execFileSync(
        "openssl",
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
          "/CN=spec98-fixture-ca",
        ],
        { stdio: "ignore" },
      );
      execFileSync(
        "openssl",
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
        { stdio: "ignore" },
      );
      fs.writeFileSync(
        `${output}/extensions`,
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
      fs.writeFileSync(`${output}/token`, "local-fixture-only");
      fs.copyFileSync(
        new URL("./fixture-api.mjs", import.meta.url),
        `${output}/api.mjs`,
      );
      created.push(api);
      docker(
        "run",
        "-d",
        "--name",
        api,
        "--network",
        prefix,
        "--network-alias",
        "kubernetes.default.svc",
        "--memory=128m",
        "--cpus=0.25",
        "-v",
        `${output}:/fixture:ro`,
        "node:22-bookworm-slim",
        "node",
        "/fixture/api.mjs",
      );
    }
    for (let i = 0; i < 2; i++) {
      const limited = limitedTarget && i === 1;
      const env = {
        KURA_PORT: "4000",
        KURA_INTERNAL_PORT: "7443",
        KURA_TENANT_ID: "default",
        KURA_REGION: "qualification",
        KURA_NODE_URL: `http://${names[i]}:7443`,
        KURA_PEERS: names.map((n) => `http://${n}:7443`).join(","),
        KURA_DATA_DIR: "/data",
        KURA_TMP_DIR: "/data/tmp",
        KURA_TMP_DIR_MAX_BYTES: "134217728",
        KURA_CAS_CAPACITY_BYTES: "3221225472",
        KURA_AUTH_ENABLED: "false",
        KURA_MEMORY_LIMIT_BYTES: limited ? "7516192768" : "1073741824",
        KURA_OTEL_SERVICE_NAME: "qualification",
        KURA_OTEL_DEPLOYMENT_ENVIRONMENT: "local",
        KURA_REPLICATION_PULL: "true",
        KURA_BACKFILL_ENABLED: "true",
      };
      if (limited)
        Object.assign(env, {
          KURA_MEMORY_SOFT_LIMIT_BYTES: "6442450944",
          KURA_MEMORY_HARD_LIMIT_BYTES: "6979321856",
        });
      if (mode === "active")
        Object.assign(env, {
          KURA_SERVING_AUTHORITY: "qualification",
          POD_NAMESPACE: "qualification",
          KURA_INSTANCE_UID: prefix,
          POD_UID: names[i],
          POD_NODE_NAME: `fixture-host-${i}`,
        });
      const args = [
        "run",
        "-d",
        "--name",
        names[i],
        "--network",
        prefix,
        "--memory",
        limited ? "7g" : "1536m",
        "--cpus=2",
        "-p",
        `127.0.0.1:${ports[i]}:4000`,
        ...Object.entries(env).flatMap(([k, v]) => ["-e", `${k}=${v}`]),
      ];
      if (limited) args.push("--tmpfs", "/data:rw,size=5g");
      if (mode === "active")
        args.push(
          "-v",
          `${output}:/var/run/secrets/kubernetes.io/serviceaccount:ro`,
        );
      created.push(names[i]);
      docker(...args, image);
    }
    for (let i = 0; i < 2; i++) {
      let ready = false;
      for (let retry = 0; retry < 90; retry++) {
        try {
          ready = (
            await fetch(`${urls[i]}/ready`, {
              signal: AbortSignal.timeout(2000),
            })
          ).ok;
        } catch {}
        if (ready) break;
        await sleep(1000);
      }
      assert(ready, `node ${i} not ready`);
    }
    const identities =
      mode === "active"
        ? await Promise.all(
            [0, 1].map(
              async (i) => (await report(i)).serving_authority.identity,
            ),
          )
        : null;
    if (mode === "active") {
      grant({ epoch: 1, holder: identities[0], phase: "Serving", renew: true });
      let active = false;
      for (let retry = 0; retry < 20; retry++) {
        active = (await report(0)).serving_authority.valid;
        if (active) break;
        await sleep(500);
      }
      assert(active);
    }
    return {
      prefix,
      names,
      urls,
      docker,
      report,
      grant,
      metric,
      snapshot,
      identities,
      close,
      logs,
    };
  } catch (error) {
    close();
    throw error;
  }
}

export async function handover(
  f,
  { id = `resource-${process.pid}`, deadlineMs = 300000 } = {},
) {
  const { identities, names, grant, report } = f;
  const intent = {
    id,
    destination: identities[1],
    destination_url: `http://${names[1]}:7443`,
    source_url: `http://${names[0]}:7443`,
    deadline_ms: Date.now() + deadlineMs,
  };
  grant({
    epoch: 1,
    holder: identities[0],
    phase: "Quiescing",
    handover: intent,
    renew: true,
  });
  let source, target;
  const deadline = Date.now() + deadlineMs;
  while (Date.now() < deadline) {
    [source, target] = await Promise.all(
      [0, 1].map(async (i) => (await report(i)).serving_authority),
    );
    if (source.barrier?.id === id && target.barrier?.id === id) break;
    await sleep(1000);
  }
  if (source.barrier?.id !== id || target.barrier?.id !== id) return null;
  assert.deepEqual(source.barrier, target.barrier);
  grant({
    epoch: 1,
    holder: identities[0],
    phase: "Revoking",
    barrier: source.barrier,
    handover: intent,
    renew: true,
  });
  let revoked = false;
  for (let retry = 0; retry < 30; retry++) {
    revoked = (await report(0)).serving_authority.revoked_epoch === 1;
    if (revoked) break;
    await sleep(500);
  }
  assert(revoked, "source did not acknowledge revocation");
  grant({
    epoch: 2,
    holder: identities[1],
    phase: "Serving",
    barrier: source.barrier,
    renew: true,
  });
  let active = false;
  for (let retry = 0; retry < 30; retry++) {
    active = (await report(1)).serving_authority.valid;
    if (active) break;
    await sleep(500);
  }
  assert(active, "destination did not activate");
  return source.barrier;
}
