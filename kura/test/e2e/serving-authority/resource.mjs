import fs from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const [base, container, output] = process.argv.slice(2);
if (!base || !container || !output) throw new Error('usage: resource.mjs URL CONTAINER OUTPUT');
const docker = (...args) => execFileSync('docker', ['--context', 'default', ...args], { encoding: 'utf8' });
const cpu = () => Number(docker('exec', container, 'cat', '/sys/fs/cgroup/cpu.stat').match(/usage_usec (\d+)/)[1]);
const disk = () => Number(docker('exec', container, 'du', '-sk', '/data').split(/\s/)[0]) * 1024;
const sample = async () => ({ time: Date.now(), metrics: await (await fetch(`${base}/metrics`)).text() });
const ready = await fetch(`${base}/ready`);
if (!ready.ok) throw new Error('runtime is not ready');
const payload = Buffer.alloc(64 * 1024, 42);
const samples = [await sample()];
const started = Date.now(), cpuStart = cpu();
let sampling = true, writes = 0, reads = 0;
const collector = (async () => { while (sampling) { await sleep(2000); samples.push(await sample()); } })();
await Promise.all(Array.from({length: 4}, (_, worker) => (async () => {
  for (let i = 0; i < 1200; i++) {
    const target = started + i * 50;
    if (Date.now() < target) await sleep(target - Date.now());
    const key = `resource-${worker}-${i % 128}`;
    const url = `${base}/api/cache/cas/${key}?tenant_id=default&namespace_id=resource`;
    const write = await fetch(url, {method:'POST',body:payload});
    await write.arrayBuffer();
    if (!write.ok) throw new Error(`write ${write.status}`);
    writes++;
    const read = await fetch(url);
    const body = Buffer.from(await read.arrayBuffer());
    if (!read.ok || !body.equals(payload)) throw new Error(`read ${read.status}`);
    reads++;
  }
})()));
const cpuEnd = cpu(), diskEnd = disk(), loadEnded = Date.now();
await sleep(20_000);
sampling = false;
await collector;
await fs.writeFile(output, JSON.stringify({container,writes,reads,payloadBytes:payload.length,cpuSeconds:(cpuEnd-cpuStart)/1e6,diskBytes:diskEnd,loadSeconds:(loadEnded-started)/1000,samples},null,2));
console.log(JSON.stringify({container,writes,reads,cpuSeconds:(cpuEnd-cpuStart)/1e6,diskBytes:diskEnd,loadSeconds:(loadEnded-started)/1000}));
