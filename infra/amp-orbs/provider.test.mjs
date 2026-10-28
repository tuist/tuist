import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
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
  test(`${environment}: isolated credentials, singleton lifecycle and matching published image`, () => {
    const result = render(environment, ['sandboxes.templateImage.tag=sha-abcdef012345']);
    assert.equal(result.status, 0, result.stderr);
    const docs = documents(result.stdout).filter((doc) => doc.metadata?.labels?.['app.kubernetes.io/component'] === 'amp-orb-provider');
    const deployment = docs.find((doc) => doc.kind === 'Deployment');
    const secret = docs.find((doc) => doc.kind === 'ExternalSecret');
    const pvc = docs.find((doc) => doc.kind === 'PersistentVolumeClaim');
    assert.equal(deployment.spec.replicas, 1);
    assert.equal(deployment.spec.strategy.type, 'Recreate');
    const pod = deployment.spec.template.spec;
    assert.equal(pod.automountServiceAccountToken, false);
    assert.equal(pod.nodeSelector['node.cluster.x-k8s.io/pool'], 'general');
    assert.equal(pod.nodeSelector['kubernetes.io/arch'], 'amd64');
    assert.equal(pod.terminationGracePeriodSeconds, 300);
    assert.equal(pod.securityContext.runAsUser, 10001);
    const container = pod.containers[0];
    assert.equal(container.image, 'ghcr.io/tuist/tuist-sandbox-template:sha-abcdef012345-provider');
    assert.equal(container.securityContext.readOnlyRootFilesystem, true);
    const env = Object.fromEntries(container.env.map(({ name, value }) => [name, value]));
    assert.equal(env.TUIST_URL, environment === 'production' ? 'https://tuist.dev' : `https://${environment}.tuist.dev`);
    assert.equal(env.TUIST_ACCOUNT, 'tuist');
    assert.equal(env.ORB_IMAGE, 'default');
    assert.equal(secret.spec.secretStoreRef.name, 'onepassword');
    assert.deepEqual(secret.spec.data.map((item) => item.remoteRef.key), ['Amp Orb Provider/password', 'Amp Orb Tuist Credentials/password']);
    assert.equal(pod.volumes.find((volume) => volume.name === 'credentials').secret.secretName, secret.spec.target.name);
    assert.equal(pod.volumes.find((volume) => volume.name === 'state').persistentVolumeClaim.claimName, pvc.metadata.name);
    assert.equal(pvc.metadata.annotations['helm.sh/resource-policy'], 'keep');
    assert.equal(pvc.spec.storageClassName, 'hcloud-volumes');
    assert.equal(docs.some((doc) => ['Role', 'ClusterRole', 'Service'].includes(doc.kind)), false);
  });
}
test('disabled provider renders no resources or secret dependency', () => {
  const result = render('staging', ['ampOrbProvider.enabled=false']);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(documents(result.stdout).some((doc) => doc.metadata?.labels?.['app.kubernetes.io/component'] === 'amp-orb-provider'), false);
});
test('provider cannot be enabled without the sandbox substrate', () => {
  const result = render('staging', ['sandboxes.enabled=false']);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /requires sandboxes.enabled/);
});
test('non-managed secret mode requires an explicitly supplied Secret', () => {
  const result = render('staging', ['ampOrbProvider.externalSecret.enabled=false']);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /requires existingSecret/);
  const valid = render('staging', ['ampOrbProvider.externalSecret.enabled=false', 'ampOrbProvider.existingSecret=my-provider']);
  assert.equal(valid.status, 0, valid.stderr);
  const docs = documents(valid.stdout).filter((doc) => doc.metadata?.labels?.['app.kubernetes.io/component'] === 'amp-orb-provider');
  assert.equal(docs.some((doc) => doc.kind === 'ExternalSecret'), false);
});
test('provider publication is part of the existing deployment barrier and PR builds are private', () => {
  const workflow = documents(readFileSync(`${root}.github/workflows/sandbox-image.yml`, 'utf8'))[0];
  const build = workflow.jobs.build.steps.find((step) => step.name === 'Publish provider');
  assert.equal(build.with.tags, '${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ steps.version.outputs.image_tag }}-provider');
  assert.equal(build.if, "steps.existing-provider.outputs.exists != 'true'");
  assert.equal(workflow.jobs.build.needs, 'test');
  assert.equal(workflow.permissions.packages, 'read');
  assert.equal(workflow.jobs.build.if, "github.event_name != 'pull_request'");
  const testBuild = workflow.jobs.test.steps.find((step) => step.name === 'Validate provider build');
  assert.equal(testBuild.with.push, false);
  assert.equal(testBuild.with.load, true);
  assert.ok(workflow.on.pull_request.paths.includes('infra/amp-orbs/**'));
});

test('self-host defaults do not enable a managed credential consumer', () => {
  const values = documents(readFileSync(`${chart}/values.yaml`, 'utf8'))[0];
  assert.equal(values.ampOrbProvider.enabled, false);
  assert.equal(values.ampOrbProvider.externalSecret.enabled, false);
  assert.equal(values.ampOrbProvider.existingSecret, '');
});
