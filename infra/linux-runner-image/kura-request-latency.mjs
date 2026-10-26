import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { appendFileSync, mkdirSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import { performance } from 'node:perf_hooks';
import { summarize } from './summarize-kura-request-latency.mjs';

assert.equal(process.env.TUIST_URL, 'https://staging.tuist.dev');
const endpoints = { pn: process.env.TUIST_CACHE_ENDPOINT, wan: process.env.BENCH_WAN_ENDPOINT };
assert.match(endpoints.pn, /^http:\/\/kura-[a-z0-9-]+-ovh-gra-runners\.kura\.svc\.cluster\.local:4000$/);
assert.match(endpoints.wan, /^http:\/\/kura-[a-z0-9-]+\.kura\.svc\.cluster\.local:4000$/);
assert.notEqual(endpoints.pn, endpoints.wan);
const project = process.env.SMOKE_PROJECT?.split('/');
assert.equal(project?.length, 2);
assert(project.every(p => /^[a-zA-Z0-9_-]+$/.test(p)));
assert(process.env.RUNNER_TEMP && process.env.GITHUB_OUTPUT);
const directory = `${process.env.RUNNER_TEMP}/kura-request-latency`;
mkdirSync(directory, { recursive: true });
appendFileSync(process.env.GITHUB_OUTPUT, `logs=${directory}\n`);
let token;
try {
  token = execFileSync('tuist', ['auth', 'token', '--url', process.env.TUIST_URL],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 30000 }).trim();
} catch {
  throw new Error('Could not resolve the staging job credential');
}
assert(token.length > 0);
const payload = randomBytes(1024);
const nonce = randomBytes(16).toString('hex');
const paths = Object.fromEntries(Object.keys(endpoints).map(mode => {
  const key = createHash('sha256').update(`${nonce}-${mode}`).digest('hex');
  const query = new URLSearchParams({ account_handle: project[0], project_handle: project[1] });
  return [mode, `/api/cache/gradle/${key}?${query}`];
}));
const agents = Object.fromEntries(Object.keys(endpoints).map(mode =>
  [mode, new http.Agent({ keepAlive: true, maxSockets: 1, maxFreeSockets: 1 })]));
const csv = `${directory}/requests.csv`;
writeFileSync(csv, 'connection,operation,mode,sample,status,reused_socket,ttfb_ms,total_ms,body_bytes\n');
writeFileSync(`${directory}/environment.json`, JSON.stringify({
  endpoints, runner: process.env.RUNNER_NAME, run: process.env.GITHUB_RUN_ID,
  revision: process.env.GITHUB_SHA, node: process.version, samples: 100,
  warmups: 10, protocol: 'HTTP/1.1 without TLS', payloadBytes: payload.length,
  payloadSha256: createHash('sha256').update(payload).digest('hex'),
  startedAt: new Date().toISOString(),
}, null, 2) + '\n');

function request(mode, connection, method, path, body) {
  const start = performance.now();
  return new Promise((resolve, reject) => {
    const headers = path === '/up' ? {} : { Authorization: `Bearer ${token}` };
    if (body) {
      headers['Content-Type'] = 'application/octet-stream';
      headers['Content-Length'] = body.length;
    }
    const req = http.request(new URL(path, endpoints[mode]), {
      method, headers, agent: connection === 'persistent' ? agents[mode] : false,
      signal: AbortSignal.timeout(15000),
    }, res => {
      const ttfb = performance.now() - start;
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('error', reject);
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers,
        reused: req.reusedSocket, ttfb, total: performance.now() - start,
        body: Buffer.concat(chunks) }));
    });
    req.on('error', () => reject(new Error(`${mode} ${method} request failed`)));
    req.end(body);
  });
}

const cases = [
  { name: 'health', method: 'GET', path: () => '/up', status: 200 },
  { name: 'metadata_hit', method: 'HEAD', path: mode => paths[mode], status: 200 },
  { name: 'metadata_miss', method: 'HEAD', path: mode => paths[mode].replace('/gradle/', '/gradle/missing-'), status: 404 },
  { name: 'read_1k', method: 'GET', path: mode => paths[mode], status: 200 },
];
try {
  for (const mode of ['wan', 'pn']) {
    const result = await request(mode, 'persistent', 'PUT', paths[mode], payload);
    assert([200, 201].includes(result.status), `${mode}: seed upload returned ${result.status}`);
  }
  for (const connection of ['persistent', 'fresh']) {
    for (const probe of cases) {
      for (let sample = -9; sample <= 100; sample++) {
        for (const mode of sample % 2 ? ['wan', 'pn'] : ['pn', 'wan']) {
          const r = await request(mode, connection, probe.method, probe.path(mode));
          assert.equal(r.status, probe.status, `${mode}/${probe.name}`);
          if (probe.name === 'metadata_hit') {
            assert.equal(Number(r.headers['content-length']), payload.length);
            assert(r.headers.etag);
          }
          if (probe.method === 'HEAD') assert.equal(r.body.length, 0);
          if (probe.name === 'read_1k') assert(r.body.equals(payload), 'Restored payload mismatch');
          if (sample <= 0) continue;
          assert.equal(r.reused, connection === 'persistent', 'Unexpected connection reuse');
          appendFileSync(csv, [connection, probe.name, mode, sample, r.status,
            r.reused, r.ttfb.toFixed(6), r.total.toFixed(6), r.body.length].join(',') + '\n');
        }
      }
      console.log(`Completed ${connection}/${probe.name}: 100 validated requests per endpoint`);
    }
  }
  console.log(summarize(csv));
} finally {
  for (const agent of Object.values(agents)) agent.destroy();
}
