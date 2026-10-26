import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const [header, ...lines] = readFileSync(process.argv[2], 'utf8').trim().split('\n');
assert.equal(header, 'mode,size_mib,round,phase,wall_ms,task_ms,sha256');
assert.equal(lines.length, 40, 'Expected every cold/warm pair from five rounds at both sizes');
const rows = lines.map((line) => {
  const [mode, size, round, phase, wall, task, hash] = line.split(',');
  assert(['pn', 'wan'].includes(mode));
  assert(['cold', 'warm'].includes(phase));
  assert([1, 64].includes(Number(size)));
  assert(Number(round) >= 1 && Number(round) <= 5);
  assert(Number(wall) > 0 && Number(task) >= 0);
  assert.match(hash, /^[a-f0-9]{64}$/);
  return { mode, size: Number(size), round: Number(round), phase, wall: Number(wall), task: Number(task), hash };
});
assert.equal(new Set(rows.map(r => [r.mode, r.size, r.round, r.phase].join('/'))).size, 40);
const median = (values) => [...values].sort((a, b) => a - b)[2];
console.log('| Payload | Phase | WAN wall median (range) | PN wall median (range) | Paired wall speedup | WAN / PN task medians |');
console.log('| --- | --- | --- | --- | --- | --- |');
for (const size of [1, 64]) {
  assert.equal(new Set(rows.filter(r => r.size === size).map(r => r.hash)).size, 1, 'Both paths must restore identical content');
  for (const phase of ['cold', 'warm']) {
    const wan = rows.filter(r => r.size === size && r.phase === phase && r.mode === 'wan');
    const pn = rows.filter(r => r.size === size && r.phase === phase && r.mode === 'pn');
    const display = (samples) => {
      const values = samples.map(r => r.wall / 1000);
      return `${median(values).toFixed(3)} s (${Math.min(...values).toFixed(3)}–${Math.max(...values).toFixed(3)})`;
    };
    const speedups = wan.map(w => w.wall / pn.find(p => p.round === w.round).wall);
    console.log(`| ${size} MiB | ${phase === 'cold' ? 'Cold upload' : 'Remote restore'} | ${display(wan)} | ${display(pn)} | ${median(speedups).toFixed(2)}× | ${(median(wan.map(r => r.task)) / 1000).toFixed(3)} / ${(median(pn.map(r => r.task)) / 1000).toFixed(3)} s |`);
  }
}
