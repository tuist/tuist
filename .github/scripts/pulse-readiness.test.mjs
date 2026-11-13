import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {existsSync, mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

test('managed product configuration scopes Greptime to the staging Tuist account', () => {
  for (const environment of ['staging', 'canary', 'production']) {
    const yaml = execFileSync('helm', ['template', 'tuist', 'infra/helm/tuist',
      '-f', 'infra/helm/tuist/values-managed-common.yaml',
      '-f', `infra/helm/tuist/values-managed-${environment}.yaml`,
      '-f', 'infra/helm/tuist/values-ci.yaml']);
    const objects = JSON.parse(execFileSync('yq', ['ea', '-o=json', '-I=0', '[.]', '-'], {input: yaml}));
    const server = objects.find(object => object.kind === 'Deployment' &&
      object.metadata.labels?.['app.kubernetes.io/component'] === 'server');
    const container = server.spec.template.spec.containers.find(container => container.name === 'server');
    const connection = Object.fromEntries(container.env.filter(variable => variable.name.startsWith('TUIST_PULSE_'))
      .map(variable => [variable.name, variable.value]));
    assert.deepEqual(connection, environment === 'staging' ? {
      TUIST_PULSE_BACKEND: 'greptime', TUIST_PULSE_ACCOUNT_ID: '2',
      TUIST_PULSE_URL: 'http://greptimedb.observability.svc.cluster.local:4000', TUIST_PULSE_TENANT: 'public',
    } : {}, environment);
    const secret = objects.find(object => object.kind === 'ExternalSecret' &&
      object.spec.data?.some(source => source.secretKey === 'TUIST_PULSE_TOKEN'));
    if (environment !== 'staging') {
      assert.equal(secret, undefined);
    } else {
      assert.ok(container.envFrom.some(source => source.secretRef?.name === secret.spec.target.name));
      assert.equal(secret.spec.data.find(source => source.secretKey === 'TUIST_PULSE_TOKEN').remoteRef.key,
        'PULSE_TOKEN/password');
      assert.equal(secret.spec.target.template.data.TUIST_PULSE_TOKEN, '{{ .TUIST_PULSE_TOKEN | trim }}');
    }
  }
});

test('routine deployment accepts existing Pulse without Greptime and managed replacement only when ready', () => {
  const work = mkdtempSync(join(tmpdir(), 'pulse-readiness-'));
  try {
    writeFileSync(join(work, 'kubectl'), `#!/usr/bin/env node
const args = process.argv.slice(2);
const scenario = process.env.SCENARIO;
const get = args.indexOf('get');
const kind = args[get + 1];
const name = args[get + 2];
if (get < 0 || /secret/i.test(kind)) process.exit(99);
if (kind === 'deployment' && name === 'pulso') {
  if (scenario === 'legacy deployment') console.log(JSON.stringify({spec:{replicas:1}}));
  process.exit(0);
}
if (kind === 'pods') {
  console.log(JSON.stringify({items:scenario === 'legacy pod' ? [{spec:{containers:[{image:'ghcr.io/tuist/pulso@sha256:old'}]}}] : []}));
  process.exit(0);
}
const greptime = scenario !== 'Pulse' && scenario !== 'Pulse unready';
const cluster = scenario.startsWith('cluster');
// Presence probe once the old pulse release is gone.
if (name === 'greptimedb' && args[get + 3] === 'greptimedb-datanode') {
  if (scenario !== 'no pulse no backend') console.log(cluster ? 'statefulset.apps/greptimedb-datanode' : 'statefulset.apps/greptimedb');
  process.exit(0);
}
// Topology probe: only the distributed backend has a datanode StatefulSet.
if (name === 'greptimedb-datanode' && args.includes('--ignore-not-found')) {
  if (cluster) console.log('statefulset.apps/greptimedb-datanode');
  process.exit(0);
}
// After uninstall the old pulse release has no Deployment at all.
if (name === 'pulse' && scenario.startsWith('no pulse')) process.exit(0);
const backend = name !== 'pulse';
if (backend && (!greptime || scenario === 'backend missing' || cluster === (name === 'greptimedb'))) process.exit(1);
let replicas = backend ? (name === 'greptimedb-frontend' ? 2 : cluster ? 3 : 1) : 1;
if (scenario === 'cluster datanode scaled down' && name === 'greptimedb-datanode' ||
  scenario === 'standalone scaled up' && name === 'greptimedb') replicas += scenario.endsWith('down') ? -1 : 1;
const value = {
  kind:kind === 'statefulset' ? 'StatefulSet' : 'Deployment',
  metadata:{name,generation:2,annotations:{'meta.helm.sh/release-name':backend?'greptimedb':'pulse','meta.helm.sh/release-namespace':'observability'},
    labels:{'app.kubernetes.io/name':greptime?'greptimedb-ingest':'pulse'}},
  spec:{replicas,strategy:{type:'Recreate'},template:{spec:{containers:[{image:backend?
    (/-(etcd|kafka)$/.test(name) ? 'docker.io/apache/kafka:4.3.2' : 'docker.io/greptime/greptimedb:v1.3.0'):
    greptime?'nginxinc/nginx-unprivileged:1.28.0-alpine':'ghcr.io/tuist/pulse:1.39.0@sha256:'+'a'.repeat(64)}]}}},
  status:{observedGeneration:2,updatedReplicas:replicas,readyReplicas:replicas,availableReplicas:replicas,currentRevision:'r2',updateRevision:'r2'}
};
if (scenario === 'cluster frontend unready' && name === 'greptimedb-frontend') value.status.readyReplicas = 1;
if (scenario === 'cluster kafka revision' && name === 'greptimedb-kafka') value.status.currentRevision = 'r1';
if (scenario === 'cluster metasrv image' && name === 'greptimedb-metasrv') value.spec.template.spec.containers[0].image = 'docker.io/greptime/greptimedb:v1.2.0';
if (scenario === 'owner') value.metadata.annotations['meta.helm.sh/release-name']='other';
if (scenario === 'image') value.spec.template.spec.containers[0].image='nginx:latest';
if (scenario === 'stale generation') value.status.observedGeneration=1;
if (scenario === 'Pulse unready' || scenario === 'gateway unready' && !backend || (scenario === 'backend unready' || scenario === 'no pulse backend unready') && backend) value.status.readyReplicas=0;
if (scenario === 'backend revision' && backend) value.status.currentRevision='r1';
console.log(JSON.stringify(value));
`, {mode:0o755});
    // Execute the real server-deployment step, including its chart guard.
    const step = execFileSync('yq', ['-r', '.jobs.observability-install.steps[] | select(.name == "Gate collectors on the currently deployed backend").run', '.github/workflows/server-deployment.yml'], {encoding:'utf8'});
    assert.ok(step.includes('pulse-readiness.sh'));
    for (const environment of ['staging', 'canary', 'production']) {
      for (const scenario of ['Pulse', 'Pulse unready', 'Greptime', 'backend missing', 'backend unready', 'backend revision', 'gateway unready', 'owner', 'image', 'stale generation', 'legacy deployment', 'legacy pod',
        'standalone scaled up', 'no pulse', 'no pulse backend unready', 'no pulse no backend', 'cluster', 'cluster frontend unready', 'cluster kafka revision', 'cluster metasrv image', 'cluster datanode scaled down']) {
        const result = spawnSync('bash', ['-c', step], {encoding:'utf8', env:{...process.env,
          PATH:`${work}:${process.env.PATH}`, SCENARIO:scenario, DEPLOY_ENV:environment,
          OBSERVABILITY_NAMESPACE:'observability', OBSERVABILITY_CHART_PATH:'infra/helm/k8s-monitoring'}});
        const accepted = ['Pulse', 'Greptime', 'no pulse', 'no pulse no backend', 'cluster'].includes(scenario);
        assert.equal(result.status === 0, accepted, `${environment}/${scenario}: ${result.stdout}${result.stderr}`);
        if (scenario === 'cluster') assert.match(result.stdout, /Greptime gateway and cluster backend ready/);
        if (scenario === 'no pulse') assert.match(result.stdout, /Greptime standalone backend ready/);
        if (scenario === 'no pulse no backend') assert.match(result.stdout, /no Pulse backend installed/);
      }
    }
  } finally { rmSync(work, {recursive:true, force:true}); }
});

test('managed cutover inspects the correct namespace and refuses incompatible readers before Helm', () => {
  const work = mkdtempSync(join(tmpdir(), 'pulse-readers-'));
  try {
    writeFileSync(join(work, 'kubectl'), `#!/usr/bin/env node
const scenario = process.env.SCENARIO;
const args = process.argv.slice(2);
const namespace = process.env.DEPLOY_ENV === 'production' ? 'tuist' : 'tuist-' + process.env.DEPLOY_ENV;
if (args[args.indexOf('-n') + 1] !== namespace) process.exit(99);
if (args.includes('exec')) {
  console.log('runtime startup synthetic-secret-must-not-appear');
  console.error('runtime diagnostic synthetic-secret-must-not-appear');
  if (scenario === 'RPC failure') process.exit(1);
  if (scenario === 'missing metadata') process.exit(0);
  let state = scenario === 'unenrolled' ? 'unenrolled' : 'greptime';
  if (scenario === 'Pulse reader' || scenario === 'mixed readers' && args.includes('server-2')) state='incompatible';
  console.log('PULSE_READER_STATE=' + state);
  if (scenario === 'duplicate metadata') console.log('PULSE_READER_STATE=' + state);
  process.exit(0);
}
if (args.includes('pods')) {
  const pods = [1,2].map(id => ({metadata:{name:'server-'+id},status:{conditions:[{type:'Ready',status:'True'}]}}));
  if (scenario === 'terminating pod') pods[1].metadata.deletionTimestamp='2026-11-11T00:00:00Z';
  if (scenario === 'unready pod') pods[1].status.conditions[0].status='False';
  if (scenario === 'missing pod') pods.pop();
  console.log(JSON.stringify({items:pods})); process.exit(0);
}
if (!args.includes('deployments')) process.exit(99);
const reader = {metadata:{generation:2},spec:{replicas:2},
  status:{observedGeneration:2,replicas:2,updatedReplicas:2,readyReplicas:2}};
if (scenario === 'old replicas') reader.status.updatedReplicas=1;
if (scenario === 'extra replica') reader.status.replicas=3;
if (scenario === 'unready') reader.status.readyReplicas=1;
if (scenario === 'stale') reader.status.observedGeneration=1;
console.log(JSON.stringify({items:scenario === 'absent' ? [] : [reader]}));
`, {mode:0o755});
    writeFileSync(join(work, 'helm'), '#!/bin/sh\nexit 42\n', {mode:0o755});
    const step = execFileSync('yq', ['-r', '.jobs.deploy.steps[] | select(.name == "Replace existing Pulse release only after independent backend qualification").run', '.github/workflows/greptimedb-deployment.yml'], {encoding:'utf8'});
    execFileSync('mkdir', ['-p', join(work, 'greptimedb-deploy')]);
    for (const environment of ['staging', 'canary', 'production']) {
      for (const scenario of ['ready', 'unenrolled', 'Pulse reader', 'mixed readers', 'old replicas', 'extra replica',
        'unready', 'stale', 'absent', 'terminating pod', 'unready pod', 'missing pod',
        'RPC failure', 'missing metadata', 'duplicate metadata']) {
        const result = spawnSync('bash', ['-c', step], {encoding:'utf8', env:{...process.env,
          PATH:`${work}:${process.env.PATH}`, RUNNER_TEMP:work, SCENARIO:scenario, DEPLOY_ENV:environment}});
        assert.equal(result.status, ['ready','unenrolled'].includes(scenario) ? 42 : 1, `${environment}/${scenario}: ${result.stdout}${result.stderr}`);
        assert.ok(!`${result.stdout}${result.stderr}`.includes('synthetic-secret-must-not-appear'), scenario);
      }
    }
  } finally { rmSync(work, {recursive:true, force:true}); }
});

test('explicit managed rollback restores only a known Pulse revision and verifies readiness', () => {
  const work = mkdtempSync(join(tmpdir(), 'pulse-rollback-'));
  try {
    writeFileSync(join(work, 'helm'), `#!/usr/bin/env node
const args = process.argv.slice(2);
const scenario = process.env.SCENARIO;
if (args[0] === 'rollback') require('node:fs').writeFileSync(process.env.ROLLBACK_MARKER, 'attempted');
if (JSON.stringify(args) === JSON.stringify(['history','pulse','-n','observability','-o','json'])) {
  if (scenario === 'history unavailable') process.exit(1);
  console.log(JSON.stringify([{revision:7,chart:scenario === 'gateway revision'?'greptimedb-ingest-0.1.0':'pulse-1.39.0',
    status:scenario === 'failed revision'?'failed':'superseded'}]));
} else if (JSON.stringify(args) === JSON.stringify(['rollback','pulse','7','-n','observability','--wait','--timeout','5m'])) {
  if (scenario === 'rollback failure') process.exit(1);
  if (scenario !== 'ready' && scenario !== 'unready after rollback') process.exit(98);
} else process.exit(99);
`, {mode:0o755});
    // Refuse every mutation and any Greptime/PVC/Secret access. The readiness
    // gate must accept restored Pulse without touching the retained backend.
    writeFileSync(join(work, 'kubectl'), `#!/usr/bin/env node
const args = process.argv.slice(2);
const scenario = process.env.SCENARIO;
if (JSON.stringify(args) === JSON.stringify(['-n','observability','get','deployment','pulso','--ignore-not-found','-o','json'])) process.exit(0);
if (JSON.stringify(args) === JSON.stringify(['-n','observability','get','pods','-o','json'])) {
  console.log(JSON.stringify({items:[]})); process.exit(0);
}
if (JSON.stringify(args.filter(arg => arg !== '--ignore-not-found')) !== JSON.stringify(['-n','observability','get','deployment','pulse','-o','json'])) process.exit(99);
const fs = require('node:fs');
const restored = fs.existsSync(process.env.ROLLBACK_MARKER);
const value = {
  metadata:{generation:2,labels:{'app.kubernetes.io/name':restored?'pulse':'greptimedb-ingest'},
    annotations:{'meta.helm.sh/release-name':'pulse','meta.helm.sh/release-namespace':'observability'}},
  spec:{replicas:1,strategy:{type:'Recreate'},template:{spec:{containers:[{image:'ghcr.io/tuist/pulse:1.39.0@sha256:'+'a'.repeat(64)}]}}},
  status:{observedGeneration:2,updatedReplicas:1,readyReplicas:1,availableReplicas:1}
};
if (scenario === 'foreign owner') value.metadata.annotations['meta.helm.sh/release-name']='other';
if (scenario === 'foreign namespace') value.metadata.annotations['meta.helm.sh/release-namespace']='other';
if (scenario === 'not a gateway') value.metadata.labels['app.kubernetes.io/name']='pulse';
if (scenario === 'unready after rollback' && restored) value.status.readyReplicas=0;
console.log(JSON.stringify(value));
`, {mode:0o755});
    const workflow = JSON.parse(execFileSync('yq', ['-o=json', '.', '.github/workflows/greptimedb-deployment.yml'], {encoding:'utf8'}));
    const job = workflow.jobs.rollback;
    assert.ok(job.if.includes("github.ref == 'refs/heads/main'"));
    assert.ok(job.if.includes("github.repository == 'tuist/tuist'"));
    assert.equal(job.environment, 'server-k8s-${{ inputs.environment }}');
    assert.equal(job.concurrency.group, 'server-deploy-${{ inputs.environment }}-observability');
    const step = job.steps.find(step => step.name === 'Restore selected Pulse release without touching Greptime data').run;
    for (const [scenario, environment, revision] of [
      ['ready','staging','7'], ['foreign owner','staging','7'], ['foreign namespace','staging','7'],
      ['not a gateway','staging','7'], ['gateway revision','staging','7'], ['failed revision','staging','7'],
      ['history unavailable','staging','7'], ['unready after rollback','staging','7'], ['rollback failure','staging','7'],
      ['ready','staging','8'], ['ready','staging','0'], ['ready','staging','-1'], ['ready','staging','7; exit 0'],
      ['ready','canary','7'], ['ready','production','7'], ['ready','foreign','7']
    ]) {
      const marker = join(work, 'seen');
      rmSync(marker, {force:true});
      const result = spawnSync('bash', ['-c', step], {encoding:'utf8', env:{...process.env,
        PATH:`${work}:${process.env.PATH}`, SCENARIO:scenario, DEPLOY_ENV:environment,
        PULSE_REVISION:revision, ROLLBACK_MARKER:marker}});
      assert.equal(spawnSync('test', ['-f', marker]).status === 0,
        ['ready', 'unready after rollback', 'rollback failure'].includes(scenario) && environment !== 'foreign' && revision === '7',
        `rollback mutation attempted: ${environment}/${scenario}/${revision}`);
      assert.equal(result.status === 0, scenario === 'ready' && environment !== 'foreign' && revision === '7',
        `${environment}/${scenario}/${revision}: ${result.stdout}${result.stderr}`);
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
  const record = {account_id:11,enrolled_account_id:null,pulse_reader_available:false,greptime_adapter_available:false,greptime_backend:false,
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

test('pulse uninstall refuses while collectors still use Pulse and never touches Secrets or Greptime', () => {
  const work = mkdtempSync(join(tmpdir(), 'pulse-uninstall-'));
  try {
    writeFileSync(join(work, 'helm'), `#!/usr/bin/env node
const args = process.argv.slice(2);
const fs = require('node:fs');
const uninstalled = process.env.SCENARIO === 'already uninstalled' || fs.existsSync(process.env.MARKER);
if (args[0] === 'status') console.log(JSON.stringify({info:{status:uninstalled ? 'uninstalled' : 'deployed'}}));
else if (args[0] === 'history') console.log(JSON.stringify([{revision:7,chart:'pulse-1.43.6',status:'deployed'}]));
else if (JSON.stringify(args) === JSON.stringify(['uninstall','pulse','-n','observability','--keep-history','--wait','--timeout','5m'])) fs.writeFileSync(process.env.MARKER, '');
else process.exit(99);
`, {mode:0o755});
    // Read-only apart from Helm: any Secret read or kubectl mutation fails the step.
    writeFileSync(join(work, 'kubectl'), `#!/usr/bin/env node
const args = process.argv.slice(2);
const scenario = process.env.SCENARIO;
const gone = scenario === 'already uninstalled' || require('node:fs').existsSync(process.env.MARKER);
const get = args.indexOf('get');
const kind = args[get + 1];
if (args[2] === 'rollout' && args[3] === 'status') process.exit(0);
if (get < 0 || /^secrets?$/i.test(kind)) process.exit(99);
if (kind === 'configmaps') {
  const data = scenario === 'live collectors' ? 'url = "http://pulse.observability.svc.cluster.local:4000"' : 'url = "https://grafana.net"';
  console.log(JSON.stringify({items:[{metadata:{name:'k8s-monitoring-alloy-metrics'},data:{'config.alloy':data}}]}));
} else if (kind === 'pods') {
  const pulse = {metadata:{labels:{'app.kubernetes.io/instance':'pulse'}},spec:{containers:[{image:'ghcr.io/tuist/pulse:1.43.6',envFrom:[{secretRef:{name:'pulse-credentials'}}]}]}};
  const alloy = {metadata:{labels:{'app.kubernetes.io/instance':'k8s-monitoring'}},spec:{containers:[{image:'docker.io/grafana/alloy:v1.15.0'}],
    volumes:scenario === 'pod mounts' ? [{secret:{secretName:'pulse-credentials'}}] : []}};
  console.log(JSON.stringify({items:gone ? [alloy] : [pulse, alloy]}));
} else if (kind === 'deployment,statefulset,daemonset') {
  console.log('deployment.apps/k8s-monitoring-alloy-receiver');
} else if (kind === 'deployment,service,ingress' || kind === 'externalsecret') {
  if (!gone) console.log(kind === 'externalsecret' ? 'externalsecret/pulse-credentials' : 'deployment.apps/pulse');
} else if (kind === 'deployment' || kind === 'statefulset') {
  // Readiness on a cluster with neither the old release nor Greptime.
  if (args[get + 2] === 'pulse' && !gone) process.exit(98);
} else process.exit(99);
`, {mode:0o755});
    const workflow = JSON.parse(execFileSync('yq', ['-o=json', '.', '.github/workflows/greptimedb-deployment.yml'], {encoding:'utf8'}));
    const job = workflow.jobs['uninstall-pulse'];
    assert.ok(job.if.includes('inputs.uninstall_pulse'));
    assert.ok(workflow.jobs.deploy.if.includes('!inputs.uninstall_pulse'));
    assert.equal(job.concurrency.group, 'server-deploy-${{ inputs.environment }}-observability');
    const step = job.steps.find(step => step.name === 'Uninstall the old pulse release once no collector writes to it').run;
    for (const scenario of ['clean', 'live collectors', 'pod mounts', 'already uninstalled']) {
      const marker = join(work, 'uninstalled');
      rmSync(marker, {force:true});
      const result = spawnSync('bash', ['-c', step], {encoding:'utf8', env:{...process.env,
        PATH:`${work}:${process.env.PATH}`, SCENARIO:scenario, DEPLOY_ENV:'production', MARKER:marker,
        GITHUB_STEP_SUMMARY:join(work, 'summary')}});
      const output = `${scenario}: ${result.stdout}${result.stderr}`;
      assert.equal(result.status === 0, ['clean', 'already uninstalled'].includes(scenario), output);
      assert.equal(existsSync(marker), scenario === 'clean', output);
      if (result.status === 0) assert.match(result.stdout, /no Pulse backend installed/, output);
    }
  } finally { rmSync(work, {recursive:true, force:true}); }
});
