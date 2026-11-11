import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

test('replacement preflight preserves owner/selector/ESO and fails closed on conflicts/capacity', () => {
  const work = mkdtempSync(join(tmpdir(), 'greptime-preflight-'));
  try {
    const yaml = execFileSync('helm', ['template','pulse','infra/helm/greptimedb-ingest','-n','observability']);
    writeFileSync(join(work, 'gateway.yaml'), yaml);
    const objects = JSON.parse(execFileSync('yq', ['ea','-o=json','-I=0','[.]','-'], {input:yaml}));
    for (const object of objects) {
      object.metadata.annotations = {'meta.helm.sh/release-name':'pulse','meta.helm.sh/release-namespace':'observability'};
      object.metadata.labels = {...object.metadata.labels,'app.kubernetes.io/managed-by':'Helm'};
    }
    writeFileSync(join(work,'objects.json'), JSON.stringify(objects));
    writeFileSync(join(work,'kubectl'), `#!/usr/bin/env node
const fs = require('node:fs');
const objects = JSON.parse(fs.readFileSync(process.env.FIXTURE + '/objects.json'));
const args = process.argv.slice(2);
const at = args.indexOf('get');
if (at < 0 || args.some(arg => /^secrets?$/.test(arg))) process.exit(99);
const key = args[at + 1];
const scenario = process.env.SCENARIO;
let value;
if (key === 'nodes') value = {items:[{metadata:{name:'general'},status:{allocatable:{cpu:scenario === 'capacity' ? '0' : '10',memory:'32Gi',pods:'100'},conditions:[{type:'Ready',status:'True'}]}}]};
else if (key === 'pods') value = {items:[]};
else if (key === 'deployments') value = {items:scenario === 'extra pool' ? [{metadata:{name:'pulse-ingest',annotations:{'meta.helm.sh/release-name':'pulse'}}}] : []};
else {
  const [kind, inlineName] = key.split('/');
  const name = inlineName || args[at + 2];
  const kinds = {deployment:'Deployment',service:'Service',ingress:'Ingress',serviceaccount:'ServiceAccount',externalsecret:'ExternalSecret',configmap:'ConfigMap'};
  value = objects.find(item => item.kind === kinds[kind] && item.metadata.name === name);
  if (kind === 'configmap') { if (scenario !== 'config conflict') process.exit(0); value.metadata.annotations['meta.helm.sh/release-name'] = 'other'; }
  if (!value) process.exit(98);
  if (scenario === 'owner') value.metadata.annotations['meta.helm.sh/release-name'] = 'other';
  if (scenario === 'selector' && kind === 'deployment') value.spec.selector.matchLabels['app.kubernetes.io/name'] = 'other';
  if (kind === 'externalsecret') {
    for (const source of value.spec.data) {
      source.remoteRef = {conversionStrategy:'Default',decodingStrategy:'None',metadataPolicy:'None',nullBytePolicy:'Ignore',...source.remoteRef};
    }
    if (scenario === 'conversion') value.spec.data[0].remoteRef.conversionStrategy = 'Unicode';
    if (scenario === 'decoding') value.spec.data[0].remoteRef.decodingStrategy = 'Base64';
    if (scenario === 'metadata') value.spec.data[0].remoteRef.metadataPolicy = 'Fetch';
    if (scenario === 'null byte') value.spec.data[0].remoteRef.nullBytePolicy = 'Replace';
    if (scenario === 'source') value.spec.data[0].remoteRef.key = 'other/password';
  }
  if (scenario === 'ESO' && kind === 'externalsecret') value.spec.target.template.data['pulse-password'] = 'changed';
}
if (args.includes('name')) process.stdout.write(value.metadata.name); else process.stdout.write(JSON.stringify(value));
`, {mode:0o755});
    for (const scenario of ['success','owner','selector','ESO','conversion','decoding','metadata','null byte','source','extra pool','capacity','config conflict']) {
      const result = spawnSync('bash', ['.github/scripts/greptimedb-replacement-preflight.sh',join(work,'gateway.yaml')], {
        encoding:'utf8', env:{...process.env,PATH:`${work}:${process.env.PATH}`,FIXTURE:work,SCENARIO:scenario},
      });
      assert.equal(result.status === 0, scenario === 'success', `${scenario}: ${result.stdout}${result.stderr}`);
    }
  } finally { rmSync(work,{recursive:true,force:true}); }
});
