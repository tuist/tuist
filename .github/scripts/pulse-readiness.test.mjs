import assert from 'node:assert/strict';
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdtempSync, writeFileSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';

test('routine deployment accepts existing Pulse without Greptime and staging replacement only when ready', () => {
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
const backend = kind === 'statefulset';
if (backend && (!greptime || scenario === 'backend missing')) process.exit(1);
const value = {
  metadata:{generation:2,annotations:{'meta.helm.sh/release-name':backend?'greptimedb':'pulse','meta.helm.sh/release-namespace':'observability'},
    labels:{'app.kubernetes.io/name':greptime?'greptimedb-ingest':'pulse'}},
  spec:{replicas:1,strategy:{type:'Recreate'},template:{spec:{containers:[{image:backend?'docker.io/greptime/greptimedb:v1.3.0':
    greptime?'nginxinc/nginx-unprivileged:1.28.0-alpine':'ghcr.io/tuist/pulse:1.39.0@sha256:'+'a'.repeat(64)}]}}},
  status:{observedGeneration:2,updatedReplicas:1,readyReplicas:1,availableReplicas:1,currentRevision:'r2',updateRevision:'r2'}
};
if (scenario === 'owner') value.metadata.annotations['meta.helm.sh/release-name']='other';
if (scenario === 'image') value.spec.template.spec.containers[0].image='nginx:latest';
if (scenario === 'stale generation') value.status.observedGeneration=1;
if (scenario === 'Pulse unready' || scenario === 'gateway unready' && !backend || scenario === 'backend unready' && backend) value.status.readyReplicas=0;
if (scenario === 'backend revision' && backend) value.status.currentRevision='r1';
console.log(JSON.stringify(value));
`, {mode:0o755});
    // Execute the real server-deployment step, including its chart guard.
    const step = execFileSync('yq', ['-r', '.jobs.observability-install.steps[] | select(.name == "Gate collectors on the currently deployed backend").run', '.github/workflows/server-deployment.yml'], {encoding:'utf8'});
    assert.ok(step.includes('pulse-readiness.sh'));
    for (const environment of ['staging', 'canary', 'production']) {
      for (const scenario of ['Pulse', 'Pulse unready', 'Greptime', 'backend missing', 'backend unready', 'backend revision', 'gateway unready', 'owner', 'image', 'stale generation', 'legacy deployment', 'legacy pod']) {
        const result = spawnSync('bash', ['-c', step], {encoding:'utf8', env:{...process.env,
          PATH:`${work}:${process.env.PATH}`, SCENARIO:scenario, DEPLOY_ENV:environment,
          OBSERVABILITY_NAMESPACE:'observability', OBSERVABILITY_CHART_PATH:'infra/helm/k8s-monitoring'}});
        const accepted = scenario === 'Pulse' || scenario === 'Greptime' && environment === 'staging';
        assert.equal(result.status === 0, accepted, `${environment}/${scenario}: ${result.stdout}${result.stderr}`);
      }
    }
  } finally { rmSync(work, {recursive:true, force:true}); }
});

test('staging cutover refuses unconfigured or unconverged readers before any Helm operation', () => {
  const work = mkdtempSync(join(tmpdir(), 'pulse-readers-'));
  try {
    writeFileSync(join(work, 'kubectl'), `#!/usr/bin/env node
const scenario = process.env.SCENARIO;
const env = {TUIST_PULSE_BACKEND:'greptime',TUIST_PULSE_URL:'http://greptimedb.observability.svc.cluster.local:4000',TUIST_PULSE_TENANT:'public'};
if (scenario === 'Pulse reader') env.TUIST_PULSE_BACKEND='pulse';
if (scenario === 'old URL') env.TUIST_PULSE_URL='http://pulse.observability:4000';
if (scenario === 'wrong database') env.TUIST_PULSE_TENANT='other';
const reader = {metadata:{generation:2},spec:{replicas:2,template:{spec:{containers:[{env:Object.entries(env).map(([name,value])=>({name,value}))}]}}},
  status:{observedGeneration:2,updatedReplicas:2,readyReplicas:2}};
if (scenario === 'old replicas') reader.status.updatedReplicas=1;
if (scenario === 'unready') reader.status.readyReplicas=1;
if (scenario === 'stale') reader.status.observedGeneration=1;
console.log(JSON.stringify({items:scenario === 'absent' ? [] : [reader]}));
`, {mode:0o755});
    writeFileSync(join(work, 'helm'), '#!/bin/sh\nexit 42\n', {mode:0o755});
    const step = execFileSync('yq', ['-r', '.jobs.deploy.steps[] | select(.name == "Replace existing Pulse release only after independent backend qualification").run', '.github/workflows/greptimedb-deployment.yml'], {encoding:'utf8'});
    for (const scenario of ['ready', 'Pulse reader', 'old URL', 'wrong database', 'old replicas', 'unready', 'stale', 'absent']) {
      const result = spawnSync('bash', ['-c', step], {encoding:'utf8', env:{...process.env,
        PATH:`${work}:${process.env.PATH}`, RUNNER_TEMP:work, SCENARIO:scenario}});
      assert.equal(result.status, scenario === 'ready' ? 42 : 1, `${scenario}: ${result.stdout}${result.stderr}`);
    }
  } finally { rmSync(work, {recursive:true, force:true}); }
});

test('explicit staging rollback restores only a known Pulse revision and verifies readiness', () => {
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
if (JSON.stringify(args) !== JSON.stringify(['-n','observability','get','deployment','pulse','-o','json'])) process.exit(99);
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
    assert.equal(job.environment, 'server-k8s-staging');
    assert.equal(job.concurrency.group, 'server-deploy-staging-observability');
    const step = job.steps.find(step => step.name === 'Restore staging Pulse release without touching Greptime data').run;
    for (const [scenario, environment, revision] of [
      ['ready','staging','7'], ['foreign owner','staging','7'], ['foreign namespace','staging','7'],
      ['not a gateway','staging','7'], ['gateway revision','staging','7'], ['failed revision','staging','7'],
      ['history unavailable','staging','7'], ['unready after rollback','staging','7'], ['rollback failure','staging','7'],
      ['ready','staging','8'], ['ready','staging','0'], ['ready','staging','-1'], ['ready','staging','7; exit 0'],
      ['ready','canary','7'], ['ready','production','7']
    ]) {
      const marker = join(work, 'seen');
      rmSync(marker, {force:true});
      const result = spawnSync('bash', ['-c', step], {encoding:'utf8', env:{...process.env,
        PATH:`${work}:${process.env.PATH}`, SCENARIO:scenario, DEPLOY_ENV:environment,
        PULSE_REVISION:revision, ROLLBACK_MARKER:marker}});
      assert.equal(spawnSync('test', ['-f', marker]).status === 0,
        ['ready', 'unready after rollback', 'rollback failure'].includes(scenario) && environment === 'staging' && revision === '7',
        `rollback mutation attempted: ${environment}/${scenario}/${revision}`);
      assert.equal(result.status === 0, scenario === 'ready' && environment === 'staging' && revision === '7',
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
