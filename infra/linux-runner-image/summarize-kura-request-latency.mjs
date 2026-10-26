import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

export function summarize(path) {
  const [header, ...lines] = readFileSync(path, 'utf8').trim().split('\n');
  assert.equal(header, 'connection,operation,mode,sample,status,reused_socket,ttfb_ms,total_ms,body_bytes');
  assert.equal(lines.length, 1600);
  const operations = ['health', 'metadata_hit', 'metadata_miss', 'read_1k'];
  const rows = lines.map(line => {
    const [connection, operation, mode, sample, status, reused, ttfb, total, bytes] = line.split(',');
    assert(['persistent', 'fresh'].includes(connection) && operations.includes(operation));
    assert(['pn', 'wan'].includes(mode));
    assert(Number.isInteger(Number(sample)) && Number(sample) >= 1 && Number(sample) <= 100);
    assert.equal(Number(status), operation === 'metadata_miss' ? 404 : 200);
    assert.equal(reused, String(connection === 'persistent'));
    assert(Number(ttfb) > 0 && Number(total) >= Number(ttfb));
    if (operation.startsWith('metadata')) assert.equal(Number(bytes), 0);
    if (operation === 'read_1k') assert.equal(Number(bytes), 1024);
    return { connection, operation, mode, sample, ttfb: Number(ttfb), total: Number(total) };
  });
  assert.equal(new Set(rows.map(r => [r.connection, r.operation, r.mode, r.sample].join('/'))).size, 1600);
  const table = [
    '| Connection | Request | WAN p50 / p95 | PN p50 / p95 |',
    '| --- | --- | --- | --- |',
  ];
  for (const connection of ['persistent', 'fresh']) for (const operation of operations) {
    const columns = ['wan', 'pn'].map(mode => {
      const values = rows.filter(r => r.connection === connection && r.operation === operation && r.mode === mode)
        .map(r => r.total).sort((a, b) => a - b);
      assert.equal(values.length, 100);
      return `${((values[49] + values[50]) / 2).toFixed(3)} / ${values[94].toFixed(3)} ms`;
    });
    table.push(`| ${connection} | ${operation} | ${columns.join(' | ')} |`);
  }
  return table.join('\n');
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  console.log(summarize(process.argv[2]));
}
