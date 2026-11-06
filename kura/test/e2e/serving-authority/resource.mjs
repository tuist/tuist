import fs from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { setTimeout as sleep } from "node:timers/promises";

const [base, container, output] = process.argv.slice(2);
if (!base || !container || !output)
  throw new Error("usage: resource.mjs URL CONTAINER OUTPUT");
const iterations = Number(process.env.KURA_RESOURCE_ITERATIONS ?? 1200);
const intervalMs = Number(process.env.KURA_RESOURCE_INTERVAL_MS ?? 50);
const warmupIterations = Number(
  process.env.KURA_RESOURCE_WARMUP_ITERATIONS ?? 0,
);
if (
  ![iterations, intervalMs, warmupIterations].every(Number.isSafeInteger) ||
  iterations < 1 ||
  intervalMs < 0 ||
  warmupIterations < 0
)
  throw new Error("invalid resource workload configuration");
const docker = (...args) =>
  execFileSync("docker", ["--context", "default", ...args], {
    encoding: "utf8",
  });
const cpu = () =>
  Number(
    docker("exec", container, "cat", "/sys/fs/cgroup/cpu.stat").match(
      /usage_usec (\d+)/,
    )[1],
  );
const disk = () =>
  Number(docker("exec", container, "du", "-sk", "/data").split(/\s/)[0]) * 1024;
const sample = async () => ({
  time: Date.now(),
  metrics: await (await fetch(`${base}/metrics`)).text(),
});
const ready = await fetch(`${base}/ready`);
if (!ready.ok) throw new Error("runtime is not ready");
const payload = Buffer.alloc(64 * 1024, 42);
async function transfer(worker, i) {
  const key = `resource-${worker}-${i % 128}`;
  const url = `${base}/api/cache/cas/${key}?tenant_id=default&namespace_id=resource`;
  const write = await fetch(url, {
    method: "POST",
    body: payload,
    signal: AbortSignal.timeout(30_000),
  });
  await write.arrayBuffer();
  if (!write.ok) throw new Error(`write ${write.status}`);
  const read = await fetch(url, { signal: AbortSignal.timeout(30_000) });
  const body = Buffer.from(await read.arrayBuffer());
  if (!read.ok || !body.equals(payload)) throw new Error(`read ${read.status}`);
}
await Promise.all(
  Array.from({ length: 4 }, (_, worker) =>
    (async () => {
      for (let i = 0; i < warmupIterations; i++) await transfer(worker, i);
    })(),
  ),
);
const samples = [await sample()];
const started = Date.now(),
  cpuStart = cpu();
let sampling = true,
  writes = 0,
  reads = 0;
const collector = (async () => {
  while (sampling) {
    await sleep(2000);
    samples.push(await sample());
  }
})();
await Promise.all(
  Array.from({ length: 4 }, (_, worker) =>
    (async () => {
      for (let i = 0; i < iterations; i++) {
        const target = started + i * intervalMs;
        if (Date.now() < target) await sleep(target - Date.now());
        await transfer(worker, i);
        writes++;
        reads++;
      }
    })(),
  ),
);
const cpuEnd = cpu(),
  diskEnd = disk(),
  loadEnded = Date.now();
await sleep(20_000);
sampling = false;
await collector;
await fs.writeFile(
  output,
  JSON.stringify(
    {
      container,
      writes,
      reads,
      iterations,
      intervalMs,
      warmupIterations,
      payloadBytes: payload.length,
      cpuSeconds: (cpuEnd - cpuStart) / 1e6,
      diskBytes: diskEnd,
      loadSeconds: (loadEnded - started) / 1000,
      samples,
    },
    null,
    2,
  ),
);
console.log(
  JSON.stringify({
    container,
    writes,
    reads,
    cpuSeconds: (cpuEnd - cpuStart) / 1e6,
    diskBytes: diskEnd,
    loadSeconds: (loadEnded - started) / 1000,
  }),
);
