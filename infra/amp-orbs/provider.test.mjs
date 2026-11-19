import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
const root = fileURLToPath(new URL('../../', import.meta.url));
const chart = `${root}infra/helm/tuist`;
function render(environment, settings = []) {
  const args = ['template', 'custom', chart, '--namespace', `tuist-${environment}`];
  if (environment !== 'self-hosted') args.push('-f', `${chart}/values-managed-common.yaml`, '-f', `${chart}/values-managed-${environment}.yaml`);
  args.push('-f', `${chart}/values-ci.yaml`);
  for (const setting of settings) args.push('--set', setting);
  return spawnSync('helm', args, { encoding: 'utf8', maxBuffer: 12 * 1024 * 1024 });
}
function documents(yaml) {
  const result = spawnSync('yq', ['-o=json', '-I=0', '.'], { input: yaml, encoding: 'utf8', maxBuffer: 12 * 1024 * 1024 });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim().split('\n').map((line) => JSON.parse(line)).filter(Boolean);
}
for (const environment of ['staging', 'canary', 'production']) {
  test(`${environment}: account integrations have scoped provisioning and no fixed credentials`, () => {
    const result = render(environment, ['sandboxes.templateImage.tag=sha-abcdef012345']);
    assert.equal(result.status, 0, result.stderr);
    const docs = documents(result.stdout);
    const amp = docs.filter(d => d.metadata?.labels?.['app.kubernetes.io/component'] === 'amp-orb-provider');
    assert.equal(amp.some(d => ['ExternalSecret', 'PersistentVolumeClaim', 'Deployment'].includes(d.kind)), false);
    const role = amp.find(d => d.kind === 'Role');
    assert.equal(role.metadata.namespace, 'tuist-amp-orbs');
    assert.ok(role.rules.every(r => !r.resources.includes('*') && !r.verbs.includes('*')));
    assert.ok(role.rules.some(r => r.resources.includes('deployments')));
    const server = docs.find(d => d.kind === 'Deployment' && d.metadata.labels?.['app.kubernetes.io/component'] === 'server');
    const env = Object.fromEntries(server.spec.template.spec.containers[0].env.map(e => [e.name, e.value]));
    assert.equal(env.TUIST_AMP_PROVIDER_IMAGE, 'ghcr.io/tuist/tuist-sandbox-template:sha-abcdef012345-provider');
    assert.equal(env.TUIST_AMP_PROVIDER_NAMESPACE, role.metadata.namespace);
    assert.equal(env.TUIST_AMP_PROVIDER_URL, environment === 'production' ? 'https://tuist.dev' : `https://${environment}.tuist.dev`);
    assert.doesNotMatch(result.stdout, /Amp Orb Tuist Credentials|Amp Orb Provider\/password|TUIST_ACCOUNT/);
  });
}
test('disabled provider has no provisioning resources', () => {
  const result = render('staging', ['ampOrbProvider.enabled=false']);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(documents(result.stdout).some(d => d.metadata?.labels?.['app.kubernetes.io/component'] === 'amp-orb-provider'), false);
});
test('requires the sandbox substrate', () => {
  const result = render('staging', ['sandboxes.enabled=false']);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /requires sandboxes.enabled/);
});
test('self-hosted defaults require no Amp credential', () => {
  const result = render('self-hosted', ['server.license.key=fixture-license']);
  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stdout, /TUIST_AMP_PROVIDER_/);
});
