import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

test('capacity retains a server surge slot, counts init peaks and excludes unavailable nodes', () => {
  const work = mkdtempSync(join(tmpdir(), 'openobserve-capacity-'));
  try {
    const pod = { spec: { nodeName: 'general', containers: [{ resources: { requests: { cpu: '500m', memory: '512Mi' } } }] }, status: { phase: 'Running' } };
    const workload = [{ kind: 'Deployment', spec: { replicas: 1, template: { spec: {
      containers: [{ resources: { requests: { cpu: '1', memory: '1Gi' } } }],
    } } } }];
    const nodes = { items: [{ metadata: { name: 'general' }, spec: {}, status: {
      allocatable: { cpu: '3', memory: '4Gi', pods: '10' }, conditions: [{ type: 'Ready', status: 'True' }],
    } }] };
    const run = () => {
      for (const [name, value] of Object.entries({ nodes, pods: { items: [pod] }, workload })) writeFileSync(join(work, name), JSON.stringify(value));
      return spawnSync(process.execPath, ['.github/scripts/openobserve-capacity.mjs', ...['nodes', 'pods', 'workload'].map(name => join(work, name))]);
    };
    assert.equal(run().status, 0);
    nodes.items[0].status.allocatable.cpu = '2'; // fits the workload, but not the reserved surge
    assert.equal(run().status, 1);
    nodes.items[0].status.allocatable.cpu = '3';
    workload[0].spec.template.spec.initContainers = [{ resources: { requests: { cpu: '2' } } }];
    assert.equal(run().status, 1);
    delete workload[0].spec.template.spec.initContainers;
    nodes.items[0].status.conditions[0].status = 'False';
    assert.equal(run().status, 1);
  } finally { rmSync(work, { recursive: true, force: true }); }
});

for (const prefix of ['openobserve', 'greptimedb']) {
for (const scenario of ['success', 'lifecycle rules', 'lifecycle unavailable', 'public bucket', 'corrupt read', 'failed delete']) {
  test(`storage ${prefix}: ${scenario}`, () => {
    const work = mkdtempSync(join(tmpdir(), 'openobserve-storage-'));
    try {
      // Fake only the external S3 transport; exercise the real executable and its cleanup.
      writeFileSync(join(work, 'curl'), `#!/usr/bin/env node
const { writeFileSync, readFileSync, unlinkSync } = require('node:fs');
const { join } = require('node:path');
const args = process.argv.slice(2);
const url = new URL(args.at(-1));
const scenario = process.env.SCENARIO;
const object = join(process.env.FIXTURE, 'object');
if (url.origin !== 'https://t3.storage.dev' || !url.pathname.startsWith('/tuist-pulso-staging')) process.exit(90);
const method = args.includes('-X') ? args[args.indexOf('-X') + 1] : 'GET';
let code = 200, body = '';
if (url.searchParams.has('lifecycle')) {
  if (scenario === 'lifecycle unavailable') { code = 403; body = '<Error><Code>AccessDenied</Code><Message>test-secret</Message></Error>'; }
  else if (scenario === 'lifecycle rules') body = '<LifecycleConfiguration><Rule><Status>Enabled</Status></Rule></LifecycleConfiguration>';
  else { code = 404; body = '<Error><Code>NoSuchLifecycleConfiguration</Code></Error>'; }
} else if (url.searchParams.has('list-type')) body = '<ListBucketResult/>';
else {
  if (url.pathname !== '/tuist-pulso-staging/' + process.env.STORAGE_PREFIX + '/ci-preflight/test-run') process.exit(91);
  if (method === 'PUT') writeFileSync(object, readFileSync(args[args.indexOf('--data-binary') + 1].slice(1)));
  else if (method === 'DELETE') {
    if (scenario === 'failed delete') code = 403;
    else { unlinkSync(object); code = 204; }
  } else if (!args.includes('--user')) code = scenario === 'public bucket' ? 200 : 403;
  else body = scenario === 'corrupt read' ? 'wrong-content' : readFileSync(object, 'utf8');
}
writeFileSync(args[args.indexOf('--output') + 1], body);
process.stdout.write(String(code));
`, { mode: 0o755 });
      const result = spawnSync('sh', ['.github/scripts/openobserve-storage-check.sh'], { encoding: 'utf8', env: {
        ...process.env, PATH: `${work}:${process.env.PATH}`, FIXTURE: work, SCENARIO: scenario,
        DEPLOY_ENV: 'staging', CHECK_RUN: 'test-run', STORAGE_PREFIX: prefix,
        AWS_ACCESS_KEY_ID: 'test-key', AWS_SECRET_ACCESS_KEY: 'test-secret',
      } });
      assert.equal(result.status, scenario === 'success' ? 0 : 1, result.stdout + result.stderr);
      assert.equal(existsSync(join(work, 'object')), scenario === 'failed delete');
      assert.ok(!(result.stdout + result.stderr).includes('test-secret'));
      if (scenario === 'lifecycle unavailable') assert.match(result.stderr, /HTTP 403, S3 AccessDenied/);
    } finally { rmSync(work, { recursive: true, force: true }); }
  });
}
}
