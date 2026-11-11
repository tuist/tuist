import assert from 'node:assert/strict';
import { execFileSync, spawn } from 'node:child_process';
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { once } from 'node:events';
import test from 'node:test';

function render(chart = 'infra/helm/greptimedb-ingest') {
  const yaml = execFileSync('helm', ['template', 'pulse', chart, '-n', 'observability']);
  return JSON.parse(execFileSync('yq', ['ea', '-o=json', '-I=0', '[.]', '-'], {input: yaml}).toString()
    .trim().split('\n').filter(Boolean).join(''));
}

test('template-only nginx edits change Deployment checksum without value changes', () => {
  const work = mkdtempSync(join(tmpdir(), 'greptime-chart-'));
  try {
    cpSync('infra/helm/greptimedb-ingest', work, {recursive: true});
    const checksum = () => render(work).find(item => item.kind === 'Deployment').spec.template.metadata.annotations['checksum/config'];
    const before = checksum();
    const path = join(work, 'templates/gateway.yaml');
    writeFileSync(path, readFileSync(path, 'utf8').replace('proxy_read_timeout 35s', 'proxy_read_timeout 36s'));
    assert.notEqual(checksum(), before);
  } finally { rmSync(work, {recursive: true, force: true}); }
});

test('real nginx preserves wire bodies/auth/status; fixes routing and blocks selection/query/admin paths', {
  skip: !process.env.NGINX_BINARY, timeout: 30000,
}, async () => {
  const work = mkdtempSync(join(tmpdir(), 'greptime-gateway-'));
  const calls = [];
  let status = 200;
  const upstream = createServer(async (request, response) => {
    const parts = [];
    for await (const chunk of request) parts.push(chunk);
    calls.push({path: request.url, headers: request.headers, body: Buffer.concat(parts)});
    response.writeHead(status); response.end('upstream-result');
  });
  upstream.listen(0, '127.0.0.1'); await once(upstream, 'listening');
  const reservation = createServer(); reservation.listen(0, '127.0.0.1'); await once(reservation, 'listening');
  const port = reservation.address().port; await new Promise(resolve => reservation.close(resolve));
  const config = render().find(item => item.kind === 'ConfigMap').data['nginx.conf']
    .replace('listen 4000;', `listen ${port};`)
    .replaceAll('greptimedb.observability.svc.cluster.local:4000', `127.0.0.1:${upstream.address().port}`)
    .replaceAll('/tmp/', `${work}/`).replace('/dev/stderr', `${work}/error.log`);
  writeFileSync(join(work, 'nginx.conf'), config);
  const nginx = spawn(process.env.NGINX_BINARY, ['-p', work, '-c', join(work, 'nginx.conf'), '-g', 'daemon off;'], {stdio: 'ignore'});
  try {
    const base = `http://127.0.0.1:${port}`;
    let ready = false;
    for (let attempt = 0; attempt < 100; attempt++) {
      try { ready = (await fetch(`${base}/health`)).status === 200; } catch { /* starting */ }
      if (ready) break;
      await new Promise(resolve => setTimeout(resolve, 20));
    }
    assert.ok(ready, 'nginx did not start');
    const routes = {
      '/api/v1/write': '/v1/prometheus/write', '/loki/api/v1/push': '/v1/loki/api/v1/push',
      '/v1/metrics': '/v1/otlp/v1/metrics', '/otlp/v1/metrics': '/v1/otlp/v1/metrics',
      '/v1/logs': '/v1/otlp/v1/logs', '/otlp/v1/logs': '/v1/otlp/v1/logs',
      '/v1/traces': '/v1/otlp/v1/traces', '/otlp/v1/traces': '/v1/otlp/v1/traces',
    };
    const authorization = `Basic ${Buffer.from('tuist:synthetic-fixture').toString('base64')}`;
    for (const [path, target] of Object.entries(routes)) {
      for (const result of [200, 204, 401, 429, 500]) {
        status = result;
        const body = Buffer.from([0, 255, 1, 7, 64, 0]);
        const count = calls.length;
        const response = await fetch(`${base}${path}`, {method: 'POST', body, headers: {
          Authorization: authorization, 'Content-Type': 'application/x-protobuf', 'Content-Encoding': 'snappy',
          'X-Greptime-DB-Name': 'forbidden', 'X-Greptime-Log-Table-Name': 'forbidden',
          'X-Greptime-Trace-Table-Name': 'forbidden', 'X-Greptime-Pipeline-Name': 'forbidden',
          'X-Greptime-Log-Pipeline-Name': 'forbidden', 'X-Greptime-Log-Pipeline-Version': 'forbidden',
          'X-Greptime-Pipeline-Version': 'forbidden', 'X-Greptime-Pipeline-Params': 'forbidden',
          'X-Greptime-Insert-Skip-Wal': 'true',
        }});
        assert.equal(response.status, result);
        await response.arrayBuffer();
        assert.equal(calls.length, count + 1, 'write was replayed');
        const call = calls.at(-1);
        assert.equal(call.path, target); assert.deepEqual(call.body, body);
        assert.equal(call.headers.authorization, authorization);
        assert.equal(call.headers['content-encoding'], 'snappy');
        assert.equal(call.headers['x-greptime-db-name'], 'public');
        assert.equal(call.headers['x-greptime-log-table-name'], 'opentelemetry_logs');
        assert.equal(call.headers['x-greptime-trace-table-name'], 'opentelemetry_traces');
        assert.equal(call.headers['x-greptime-pipeline-name'], path.includes('loki') ? 'loki_otlp' : path.endsWith('traces') ? 'greptime_trace_v1' : undefined);
        for (const name of ['x-greptime-log-pipeline-name', 'x-greptime-log-pipeline-version', 'x-greptime-pipeline-version', 'x-greptime-pipeline-params', 'x-greptime-insert-skip-wal']) assert.equal(call.headers[name], undefined);
      }
      const count = calls.length;
      assert.equal((await fetch(`${base}${path}?db=forbidden&table=forbidden`, {method:'POST',body:'x'})).status, 400);
      assert.equal((await fetch(`${base}${path}`)).status, 405);
      assert.equal(calls.length, count);
    }
    for (const path of ['/v1/sql?sql=SELECT%201', '/v1/pipelines/loki_otlp', '/mcp', '/api/v1/query', '/v1/prometheus/write']) {
      const count = calls.length;
      assert.equal((await fetch(`${base}${path}`, {headers:{Authorization:authorization}})).status, 404);
      assert.equal(calls.length, count);
    }
  } finally {
    nginx.kill('SIGQUIT'); await once(nginx, 'exit');
    await new Promise(resolve => upstream.close(resolve));
    rmSync(work, {recursive:true,force:true});
  }
});
