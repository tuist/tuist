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
