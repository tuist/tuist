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

test('capacity spreads anti-affine replicas over distinct hosts and can require a one-node failure reserve', () => {
  const work = mkdtempSync(join(tmpdir(), 'openobserve-spread-'));
  try {
    const labels = { 'app.kubernetes.io/instance': 'greptimedb', 'app.kubernetes.io/component': 'kafka' };
    // Three 1-CPU replicas that must not share a host; every node has room for two.
    const workload = [{ kind: 'StatefulSet', metadata: { name: 'kafka' }, spec: { replicas: 3, template: {
      metadata: { labels },
      spec: { affinity: { podAntiAffinity: { requiredDuringSchedulingIgnoredDuringExecution: [
        { topologyKey: 'kubernetes.io/hostname', labelSelector: { matchLabels: labels } }] } },
      containers: [{ resources: { requests: { cpu: '1', memory: '1Gi' } } }] },
    } } }];
    const node = name => ({ metadata: { name }, spec: {}, status: {
      allocatable: { cpu: '3.1', memory: '8Gi', pods: '10' }, conditions: [{ type: 'Ready', status: 'True' }] } });
    const run = (count, env = {}) => {
      writeFileSync(join(work, 'nodes'), JSON.stringify({ items: Array.from({ length: count }, (_, i) => node(`n${i}`)) }));
      writeFileSync(join(work, 'pods'), JSON.stringify({ items: [] }));
      writeFileSync(join(work, 'workload'), JSON.stringify(workload));
      return spawnSync(process.execPath, ['.github/scripts/openobserve-capacity.mjs', ...['nodes', 'pods', 'workload'].map(name => join(work, name))],
        { env: { ...process.env, ...env } }).status;
    };
    // Two nodes hold 6.2 CPUs, enough for 3 CPUs plus the surge reserve, but not three distinct hosts.
    assert.equal(run(2), 1);
    assert.equal(run(3), 0);
    assert.equal(run(3, { CAPACITY_TOLERATE_NODE_LOSS: '1' }), 1);
    assert.equal(run(4, { CAPACITY_TOLERATE_NODE_LOSS: '1' }), 0);
    // Without the anti-affinity the same replicas may share hosts again.
    delete workload[0].spec.template.spec.affinity;
    assert.equal(run(2), 0);
  } finally { rmSync(work, { recursive: true, force: true }); }
});

test('capacity counts an upgraded release once, not as both running pods and new demand', () => {
  const work = mkdtempSync(join(tmpdir(), 'openobserve-upgrade-'));
  try {
    const labels = { 'app.kubernetes.io/instance': 'greptimedb', 'app.kubernetes.io/component': 'datanode' };
    const workload = [{ kind: 'StatefulSet', metadata: { name: 'greptimedb-datanode' }, spec: { replicas: 1,
      selector: { matchLabels: labels }, template: { metadata: { labels },
        spec: { containers: [{ resources: { requests: { cpu: '2', memory: '1Gi' } } }] } } } }];
    // 4 CPUs: the 2-CPU release plus the 1-CPU surge reserve fit once, not twice.
    const nodes = { items: [{ metadata: { name: 'general' }, spec: {}, status: {
      allocatable: { cpu: '4', memory: '8Gi', pods: '10' }, conditions: [{ type: 'Ready', status: 'True' }] } }] };
    const running = namespace => ({ metadata: { namespace, labels }, spec: { nodeName: 'general',
      containers: [{ resources: { requests: { cpu: '2', memory: '1Gi' } } }] }, status: { phase: 'Running' } });
    const run = (pods, env = {}) => {
      for (const [name, value] of Object.entries({ nodes, pods: { items: pods }, workload })) writeFileSync(join(work, name), JSON.stringify(value));
      return spawnSync(process.execPath, ['.github/scripts/openobserve-capacity.mjs', ...['nodes', 'pods', 'workload'].map(name => join(work, name))],
        { env: { ...process.env, ...env } }).status;
    };
    assert.equal(run([]), 0);
    assert.equal(run([running('observability')]), 1);
    assert.equal(run([running('observability')], { CAPACITY_NAMESPACE: 'observability' }), 0);
    // Matching labels elsewhere are other workloads and still use capacity.
    assert.equal(run([running('tuist')], { CAPACITY_NAMESPACE: 'observability' }), 1);
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
