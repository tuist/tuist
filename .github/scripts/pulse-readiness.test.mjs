import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {existsSync, mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

test('managed product configuration scopes Greptime to each environment\'s Tuist account', () => {
  for (const environment of ['staging', 'canary', 'production']) {
    const yaml = execFileSync('helm', ['template', 'tuist', 'infra/helm/tuist',
      '-f', 'infra/helm/tuist/values-managed-common.yaml',
      '-f', `infra/helm/tuist/values-managed-${environment}.yaml`,
      '-f', 'infra/helm/tuist/values-ci.yaml']);
    const objects = JSON.parse(execFileSync('yq', ['ea', '-o=json', '-I=0', '[.]', '-'], {input: yaml}));
    const server = objects.find(object => object.kind === 'Deployment' &&
      object.metadata.labels?.['app.kubernetes.io/component'] === 'server');
    const container = server.spec.template.spec.containers.find(container => container.name === 'server');
    const pulseEnv = container.env.filter(variable => variable.name.startsWith('TUIST_PULSE_'));
    // A repeated name would let a later entry silently override the asserted one.
    assert.equal(new Set(pulseEnv.map(variable => variable.name)).size, pulseEnv.length, environment);
    const connection = Object.fromEntries(pulseEnv.map(variable => [variable.name, variable.value]));
    // The tuist account is 2 in staging and 3 in production; canary has no reader.
    const accountID = {staging: '2', production: '3'}[environment];
    assert.deepEqual(connection, accountID ? {
      TUIST_PULSE_ACCOUNT_ID: accountID,
      TUIST_PULSE_URL: 'http://pulse.observability.svc.cluster.local:4000', TUIST_PULSE_TENANT: 'public',
    } : {}, environment);
    const secret = objects.find(object => object.kind === 'ExternalSecret' &&
      object.spec.data?.some(source => source.secretKey === 'TUIST_PULSE_TOKEN'));
    if (!accountID) {
      assert.equal(secret, undefined);
    } else {
      assert.ok(secret, `${environment}: no ExternalSecret syncs TUIST_PULSE_TOKEN`);
      assert.ok(container.envFrom.some(source => source.secretRef?.name === secret.spec.target.name));
      assert.equal(secret.spec.data.find(source => source.secretKey === 'TUIST_PULSE_TOKEN').remoteRef.key,
        'PULSE_TOKEN/password');
      assert.equal(secret.spec.target.template.data.TUIST_PULSE_TOKEN, '{{ .TUIST_PULSE_TOKEN | trim }}');
    }
  }
});

test('routine deployment gates on a ready Pulse release and still deploys collectors without one', () => {
  const work = mkdtempSync(join(tmpdir(), 'pulse-readiness-'));
  try {
    writeFileSync(join(work, 'kubectl'), `#!/usr/bin/env node
const args = process.argv.slice(2);
const scenario = process.env.SCENARIO;
const get = args.indexOf('get');
const kind = args[get + 1];
const name = args[get + 2];
if (get < 0 || /^secrets?$/i.test(kind)) process.exit(99);
if (kind === 'externalsecret') {
  if (scenario === 'ingest login missing') process.exit(1);
  console.log(JSON.stringify({spec:{target:{template:{data:{passwd:'', 'ingest-username':'tuist', 'ingest-password':''}}}},
    status:{conditions:[{type:'Ready', status:scenario === 'ingest login unready' ? 'False' : 'True'}]}}));
  process.exit(0);
}
const cluster = scenario.startsWith('cluster');
// The old greptimedb release is ignored: only the pulse release is Pulse.
const installed = !['none', 'old greptimedb release', 'ingest login missing', 'ingest login unready'].includes(scenario);
const exists = workload => installed && (cluster ? workload.startsWith('pulse-') : workload === 'pulse') &&
  !(scenario === 'cluster metasrv missing' && workload === 'pulse-metasrv');
if (args.includes('--ignore-not-found')) {
  if (exists(name)) console.log(kind + '.apps/' + name);
  process.exit(0);
}
if (!exists(name)) process.exit(1);
let replicas = name === 'pulse-frontend' ? 2 : cluster ? 3 : 1;
if (scenario === 'cluster datanode scaled down' && name === 'pulse-datanode') replicas -= 1;
if (scenario === 'standalone scaled up') replicas += 1;
const value = {
  kind:kind === 'statefulset' ? 'StatefulSet' : 'Deployment',
  metadata:{name,generation:2,annotations:{'meta.helm.sh/release-name':'pulse','meta.helm.sh/release-namespace':'observability'}},
  spec:{replicas,template:{spec:{containers:[{image:/-(etcd|kafka)$/.test(name) ? 'docker.io/apache/kafka:4.3.2' : 'ghcr.io/tuist/pulse:1.3.0-12'}]}}},
  status:{observedGeneration:2,updatedReplicas:replicas,readyReplicas:replicas,currentRevision:'r2',updateRevision:'r2'}
};
const image = value.spec.template.spec.containers;
if (scenario === 'standalone unready' || scenario === 'cluster frontend unready' && name === 'pulse-frontend') value.status.readyReplicas -= 1;
if (scenario === 'cluster kafka revision' && name === 'pulse-kafka' || scenario === 'standalone revision') value.status.currentRevision = 'r1';
if (scenario === 'cluster metasrv upstream image' && name === 'pulse-metasrv' || scenario === 'standalone upstream image') image[0].image = 'docker.io/greptime/greptimedb:v1.3.0';
if (scenario === 'standalone digest-only image') image[0].image = 'ghcr.io/tuist/pulse@sha256:' + 'a'.repeat(64);
if (scenario === 'standalone canary image') image[0].image = 'ghcr.io/tuist/pulse:1.44.0-canary.3';
if (scenario === 'cluster stable image') image[0].image = 'ghcr.io/tuist/pulse:1.44.0';
if (scenario === 'standalone unknown prerelease') image[0].image = 'ghcr.io/tuist/pulse:1.44.0-beta.1';
if (scenario === 'standalone sidecar') image.push({image:'busybox:1.37.0'});
if (scenario === 'owner') value.metadata.annotations['meta.helm.sh/release-name'] = 'greptimedb';
if (scenario === 'stale generation') value.status.observedGeneration = 1;
console.log(JSON.stringify(value));
`, {mode:0o755});
    // Execute the real server-deployment step, including its chart guard.
    const step = execFileSync('yq', ['-r', '.jobs.observability-install.steps[] | select(.name == "Gate collectors on the currently deployed backend").run', '.github/workflows/server-deployment.yml'], {encoding:'utf8'});
    assert.ok(step.includes('pulse-readiness.sh'));
    const accepted = {none: /no Pulse backend installed/, 'old greptimedb release': /no Pulse backend installed/,
      standalone: /Pulse standalone backend ready/, cluster: /Pulse cluster backend ready/,
      'standalone canary image': /Pulse standalone backend ready/, 'cluster stable image': /Pulse cluster backend ready/};
    for (const environment of ['staging', 'canary', 'production']) {
      for (const scenario of [...Object.keys(accepted), 'standalone unready', 'standalone scaled up', 'standalone revision',
        'standalone upstream image', 'standalone digest-only image', 'standalone unknown prerelease', 'standalone sidecar', 'owner', 'stale generation',
        'cluster frontend unready', 'cluster kafka revision', 'cluster metasrv upstream image',
        'cluster metasrv missing', 'cluster datanode scaled down']) {
        const result = spawnSync('bash', ['-c', step], {encoding:'utf8', env:{...process.env,
          PATH:`${work}:${process.env.PATH}`, SCENARIO:scenario, DEPLOY_ENV:environment,
          OBSERVABILITY_NAMESPACE:'observability', OBSERVABILITY_CHART_PATH:'infra/helm/k8s-monitoring'}});
        const output = `${environment}/${scenario}: ${result.stdout}${result.stderr}`;
        assert.equal(result.status === 0, scenario in accepted, output);
        if (scenario in accepted) assert.match(result.stdout, accepted[scenario], output);
      }
    }
    // Collectors that write to Pulse need its ingest login before Helm runs.
    const chart = join(work, 'chart');
    execFileSync('mkdir', ['-p', chart]);
    execFileSync('cp', ['infra/helm/k8s-monitoring/Chart.yaml', chart]);
    writeFileSync(join(chart, 'values-staging.yaml'), 'name: pulse-dashboard-auth\n');
    for (const scenario of ['none', 'ingest login missing', 'ingest login unready']) {
      const result = spawnSync('bash', ['-c', step], {encoding:'utf8', env:{...process.env,
        PATH:`${work}:${process.env.PATH}`, SCENARIO:scenario, DEPLOY_ENV:'staging',
        OBSERVABILITY_NAMESPACE:'observability', OBSERVABILITY_CHART_PATH:chart}});
      assert.equal(result.status === 0, scenario === 'none', `${scenario}: ${result.stdout}${result.stderr}`);
    }
  } finally { rmSync(work, {recursive:true, force:true}); }
});

test('staging reader inspection withholds runtime output and emits only typed metadata', () => {
  const work = mkdtempSync(join(tmpdir(), 'pulse-inspection-'));
  try {
    writeFileSync(join(work, 'kubectl'), `#!/usr/bin/env node
const args = process.argv.slice(2);
const scenario = process.env.SCENARIO;
if (args.includes('deployments')) {
  console.log('NAME IMAGES\\nserver ghcr.io/tuist/tuist:sha-fixture');
} else if (args.includes('pods')) {
  console.log(JSON.stringify({items:scenario === 'no ready reader' ? [] : [{metadata:{name:'server-1'},
    status:{conditions:[{type:'Ready',status:'True'}]}}]}));
} else if (args.includes('exec')) {
  const canary = 'synthetic-secret-must-not-appear';
  console.log('runtime startup ' + canary);
  console.error('runtime diagnostic ' + canary);
  if (scenario === 'RPC failure') process.exit(1);
  const record = {account_id:11,enrolled_account_id:null,pulse_reader_available:false,greptime_adapter_available:false,
    expected_endpoint:false,expected_database:false,pulse_flag:true,password:canary,url:'https://user:'+canary+'@example.invalid'};
  if (scenario === 'untyped metadata') record.account_id=canary;
  console.log('STAGING_READER_INSPECTION=' + JSON.stringify(record));
  if (scenario === 'duplicate metadata') console.log('STAGING_READER_INSPECTION=' + JSON.stringify(record));
} else process.exit(99);
`, {mode:0o755});
    writeFileSync(join(work, 'helm'), '#!/bin/sh\necho \'[{"revision":7,"chart":"pulse-1.39.0","status":"deployed"}]\'\n', {mode:0o755});
    const step = execFileSync('yq', ['-r', '.jobs.deploy.steps[] | select(.name == "Inspect staging reader identity without changing enrollment").run', '.github/workflows/greptimedb-deployment.yml'], {encoding:'utf8'});
    for (const scenario of ['ready', 'RPC failure', 'untyped metadata', 'duplicate metadata', 'no ready reader']) {
      execFileSync('mkdir', ['-p', join(work, 'greptimedb-deploy')]);
      const result = spawnSync('bash', ['-c', step], {encoding:'utf8', env:{...process.env,
        PATH:`${work}:${process.env.PATH}`, SCENARIO:scenario, DEPLOY_ENV:'staging', RUNNER_TEMP:work}});
      assert.equal(result.status === 0, scenario === 'ready', scenario);
      assert.ok(!`${result.stdout}${result.stderr}`.includes('synthetic-secret-must-not-appear'), scenario);
      if (scenario === 'ready') {
        assert.ok(result.stdout.includes('"account_id": 11'));
        assert.ok(result.stdout.includes('"pulse_flag": true'));
        assert.ok(!result.stdout.includes('password'));
        assert.ok(!result.stdout.includes('https://'));
      }
    }
  } finally { rmSync(work, {recursive:true, force:true}); }
});
