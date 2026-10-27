const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');

const root = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
const documents = execFileSync('yq', ['ea', '-o=json', '-I=0', '.', path.join(root, 'infra/k8s/mgmt/etcd-snapshot.yaml')], { encoding: 'utf8' }).trim().split('\n').map(JSON.parse);
const cronjob = documents.find(d => d.kind === 'CronJob');
const identity = documents.find(d => d.apiVersion === 'talos.dev/v1alpha1');

test('snapshot uses only the rotating backup identity and can run on any control-plane node', () => {
  assert.deepEqual(identity.spec.roles, ['os:etcd:backup']);
  const pod = cronjob.spec.jobTemplate.spec.template.spec;
  assert.equal(pod.automountServiceAccountToken, false);
  assert.equal(pod.hostNetwork, undefined);
  assert.deepEqual(pod.nodeSelector, { 'node-role.kubernetes.io/control-plane': '' });
  assert.equal(pod.volumes.find(v => v.name === 'talosconfig').secret.secretName, identity.metadata.name);
  assert.ok(pod.initContainers[0].args.includes('--talosconfig=/talosconfig/config'));
  assert.ok(pod.initContainers[0].args.includes('--nodes=$(NODE_IP)'));
  assert.equal(pod.initContainers[0].env[0].valueFrom.fieldRef.fieldPath, 'status.hostIP');
  assert.equal(pod.securityContext.runAsNonRoot, true);
  for (const c of [...pod.initContainers, ...pod.containers]) {
    assert.equal(c.securityContext.allowPrivilegeEscalation, false);
    assert.equal(c.securityContext.readOnlyRootFilesystem, true);
    assert.deepEqual(c.securityContext.capabilities.drop, ['ALL']);
  }
});

const fakeKubectl = `#!/usr/bin/env node
const fs = require('node:fs');
const dir = process.env.MGMT_TEST_DIR;
const state = JSON.parse(fs.readFileSync(dir + '/state.json'));
const args = process.argv.slice(2);
fs.appendFileSync(dir + '/calls.jsonl', JSON.stringify(args) + '\\n');
const out = x => console.log(JSON.stringify(x));
let ns;
if (args[0] === '-n') { ns = args[1]; args.splice(0, 2); }
const [action, kind, name] = args;
if (action === 'get' && kind === 'cronjob') {
  const c = state.cronjob;
  if (state.scenario === 'legacy') c.spec.jobTemplate.spec.template.spec.volumes[0].secret.secretName = 'talos-snapshotter-config';
  out(c);
} else if (action === 'get' && kind === 'nodes') {
  const items = ['tuist-mgmt', 'tuist-mgmt-2', 'tuist-mgmt-3'].map(name => ({metadata:{name},spec:{},status:{conditions:[{type:'Ready',status:'True'}]}}));
  if (state.scenario === 'unready') items[1].status.conditions[0].status = 'False';
  if (state.scenario === 'ghost') items.push({metadata:{name:'talos-sif-xr2'},spec:{},status:{conditions:[{type:'Ready',status:'True'}]}});
  out({items});
} else if (action === 'get' && kind === 'daemonset') {
  const count = state.scenario === 'ghost' ? 4 : 3;
  out({metadata:{generation:2},status:{observedGeneration:2,desiredNumberScheduled:count,updatedNumberScheduled:count,numberReady:state.scenario === 'tailscale-down' ? 2 : count,numberAvailable:count}});
} else if (action === 'get' && kind === 'secret') {
  console.log('secret/' + name);
} else if (action === 'get' && kind.includes(',')) {
  out({items:state.scenario === 'reference' && ns === 'mgmt-system' ? [{kind:'CronJob',spec:{secretName:'tailscale-state'}}] : []});
} else if (action === 'create' && kind === 'job') {
  out({apiVersion:'batch/v1',kind:'Job',metadata:{name,namespace:ns},spec:state.cronjob.spec.jobTemplate.spec});
} else if (action === 'create' && kind === '-f') {
  const job = JSON.parse(fs.readFileSync(0, 'utf8'));
  fs.appendFileSync(dir + '/jobs.jsonl', JSON.stringify(job) + '\\n');
  console.log('created');
} else if (action === 'wait') {
  if (state.scenario === 'upload-failed' && args.some(a => a.includes('tuist-mgmt-2'))) process.exit(1);
} else if (action === 'delete' && kind === 'secret') {
  console.log('deleted ' + name);
} else { throw Error('unexpected kubectl command: ' + args.join(' ')); }
`;

function run(script, scenario, args = []) {
  fs.mkdirSync(path.join(root, 'tmp'), { recursive: true });
  const dir = fs.mkdtempSync(path.join(root, 'tmp/mgmt-followups-test-'));
  try {
    fs.writeFileSync(path.join(dir, 'kubectl'), fakeKubectl, { mode: 0o755 });
    fs.writeFileSync(path.join(dir, 'state.json'), JSON.stringify({ scenario, cronjob }));
    const result = spawnSync('bash', [path.join(__dirname, script), ...args], {
      env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, MGMT_TEST_DIR: dir },
      encoding: 'utf8', timeout: 15000,
    });
    const readLines = file => fs.existsSync(path.join(dir, file)) ? fs.readFileSync(path.join(dir, file), 'utf8').trim().split('\n').map(JSON.parse) : [];
    return { result, calls: readLines('calls.jsonl'), jobs: readLines('jobs.jsonl') };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}
const deletes = calls => calls.filter(c => c.includes('delete'));

test('legacy credential deletion follows successful uploads from all three nodes', () => {
  const { result, calls, jobs } = run('verify-etcd-snapshot.sh', 'healthy', ['--delete-legacy-credential']);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(jobs.length, 3);
  assert.deepEqual(jobs.map(j => j.spec.template.spec.nodeSelector['kubernetes.io/hostname']), ['tuist-mgmt', 'tuist-mgmt-2', 'tuist-mgmt-3']);
  assert.equal(deletes(calls).length, 1);
  assert.equal(calls.at(-1)[4], 'talos-snapshotter-config');
});
for (const scenario of ['legacy', 'unready', 'upload-failed']) {
  test(`backup verification preserves the old credential when ${scenario}`, () => {
    const { result, calls } = run('verify-etcd-snapshot.sh', scenario, ['--delete-legacy-credential']);
    assert.notEqual(result.status, 0);
    assert.equal(deletes(calls).length, 0);
  });
}
test('backup verification alone does not remove credentials', () => {
  const { result, calls } = run('verify-etcd-snapshot.sh', 'healthy');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(deletes(calls).length, 0);
});
test('Tailscale cleanup planning makes no mutations', () => {
  const { result, calls } = run('cleanup-ha-secrets.sh', 'healthy');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(deletes(calls).length, 0);
});
test('Tailscale cleanup deletes exactly the three obsolete names', () => {
  const { result, calls } = run('cleanup-ha-secrets.sh', 'healthy', ['--apply']);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(deletes(calls).map(c => [c[1], c[4]]), [
    ['mgmt-system', 'tailscale-oauth'], ['mgmt-system', 'tailscale-state'],
    ['mgmt-tailscale', 'tailscale-state-talos-sif-xr2'],
  ]);
});
for (const scenario of ['unready', 'tailscale-down', 'reference', 'ghost']) {
  test(`Tailscale cleanup refuses deletion when ${scenario}`, () => {
    const { result, calls } = run('cleanup-ha-secrets.sh', scenario, ['--apply']);
    assert.notEqual(result.status, 0);
    assert.equal(deletes(calls).length, 0);
  });
}
