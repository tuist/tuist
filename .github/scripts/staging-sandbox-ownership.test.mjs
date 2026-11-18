import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

test('staging ownership repair preserves identity and fails closed without exposing raw output', () => {
  const work = mkdtempSync(join(tmpdir(), 'sandbox-ownership-'));
  const uid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const secret = 'synthetic-credential-must-not-appear';
  try {
    writeFileSync(join(work, 'kubectl'), `#!/usr/bin/env node
const fs = require('node:fs');
const path = process.env.FIXTURE;
const args = process.argv.slice(2);
if (args.includes('secret') || !args.includes(process.env.RESOURCE_NAME) || !args.includes('tuist-sandboxes')) process.exit(99);
if (args.includes('get')) {
  if (process.env.SCENARIO === 'read failure') {
    process.stdout.write(process.env.SYNTHETIC_SECRET);
    process.stderr.write(process.env.SYNTHETIC_SECRET);
    process.exit(1);
  }
  process.stdout.write(fs.readFileSync(path + '/identity.json'));
} else if (args.includes('patch')) {
  fs.writeFileSync(path + '/mutation', 'attempted');
  const value = JSON.parse(fs.readFileSync(path + '/identity.json'));
  const patch = JSON.parse(fs.readFileSync(args[args.indexOf('--patch-file') + 1]));
  if (process.env.SCENARIO === 'race') value.metadata.resourceVersion = '456';
  for (const op of patch) {
    const key = op.path.split('/').at(-1);
    if (op.op === 'test' && value.metadata[key] !== op.value) {
      process.stderr.write(process.env.SYNTHETIC_SECRET);
      process.exit(1);
    }
    if (op.op === 'add') value.metadata[key] = op.value;
  }
  if (process.env.SCENARIO === 'tampered result') value.automountServiceAccountToken = true;
  value.metadata.resourceVersion = '457';
  fs.writeFileSync(path + '/identity.json', JSON.stringify(value));
  process.stdout.write(process.env.SYNTHETIC_SECRET);
} else process.exit(98);
`, { mode: 0o755 });
    for (const scenario of ['inspect', 'repair', 'already owned', 'wrong uid', 'foreign release',
      'foreign namespace', 'foreign manager', 'controller', 'token policy', 'production', 'race',
      'read failure', 'tampered result', 'role', 'rolebinding', 'daemonset-runners', 'daemonset-rack',
      'wrong role permissions', 'wrong binding subject', 'wrong workload identity', 'all repair']) {
      rmSync(join(work, 'mutation'), { force: true });
      const identity = {
        apiVersion: 'v1', kind: 'ServiceAccount', automountServiceAccountToken: false,
        metadata: { name: 'tuist-macos-sandboxd', namespace: 'tuist-sandboxes', uid,
          resourceVersion: '123', labels: { retained: 'yes' }, annotations: { private: secret } },
        imagePullSecrets: [{ name: 'existing-reference' }],
      };
      let resource = 'serviceaccount';
      if (scenario === 'role' || scenario === 'wrong role permissions') {
        resource = 'role';
        identity.kind = 'Role';
        identity.metadata.name = 'tuist-tuist-macos-sandbox-reader';
        identity.rules = [{ apiGroups: [''], resources: ['pods'], verbs: [scenario === 'role' ? 'get' : '*'] }];
      } else if (scenario === 'rolebinding' || scenario === 'wrong binding subject') {
        resource = 'rolebinding';
        identity.kind = 'RoleBinding';
        identity.metadata.name = 'tuist-tuist-macos-sandbox-reader';
        identity.subjects = [{ kind: 'ServiceAccount', name: scenario === 'rolebinding' ? 'tuist-server' : 'other', namespace: 'tuist-staging' }];
        identity.roleRef = { apiGroup: 'rbac.authorization.k8s.io', kind: 'Role', name: identity.metadata.name };
      } else if (scenario.startsWith('daemonset-') || scenario === 'wrong workload identity') {
        resource = scenario.startsWith('daemonset-') ? scenario : 'daemonset-rack';
        identity.kind = 'DaemonSet';
        identity.metadata.name = `tuist-macos-sandboxd-${resource.slice('daemonset-'.length)}`;
        identity.spec = { selector: { matchLabels: { 'tuist.dev/macos-sandbox-role': 'control',
          'tuist.dev/macos-sandbox-fleet': resource.slice('daemonset-'.length) } },
          template: { spec: { serviceAccountName: scenario === 'wrong workload identity' ? 'other' : 'tuist-macos-sandboxd' } } };
      }
      if (scenario === 'already owned') {
        identity.metadata.labels['app.kubernetes.io/managed-by'] = 'Helm';
        identity.metadata.annotations['meta.helm.sh/release-name'] = 'tuist';
        identity.metadata.annotations['meta.helm.sh/release-namespace'] = 'tuist-staging';
      }
      if (scenario === 'foreign release') identity.metadata.annotations['meta.helm.sh/release-name'] = 'other';
      if (scenario === 'foreign namespace') identity.metadata.annotations['meta.helm.sh/release-namespace'] = 'other';
      if (scenario === 'foreign manager') identity.metadata.labels['app.kubernetes.io/managed-by'] = 'other';
      if (scenario === 'controller') identity.metadata.ownerReferences = [{ uid: 'controller' }];
      if (scenario === 'token policy') identity.automountServiceAccountToken = true;
      writeFileSync(join(work, 'identity.json'), JSON.stringify(identity));
      const result = spawnSync('bash', ['.github/scripts/staging-sandbox-ownership.sh'], {
        encoding: 'utf8', env: { ...process.env, PATH: `${work}:${process.env.PATH}`, FIXTURE: work,
          SCENARIO: scenario, SYNTHETIC_SECRET: secret, MODE: scenario === 'inspect' ? 'inspect' : 'repair',
          RESOURCE: scenario === 'all repair' ? 'all' : resource, RESOURCE_NAME: identity.metadata.name,
          DEPLOY_ENV: scenario === 'production' ? 'production' : 'staging',
          EXPECTED_UID: scenario === 'wrong uid' ? 'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee' : uid },
      });
      const repaired = ['repair', 'already owned', 'role', 'rolebinding', 'daemonset-runners', 'daemonset-rack'].includes(scenario);
      assert.equal(result.status === 0, scenario === 'inspect' || repaired, `${scenario}: ${result.stderr}`);
      assert.equal(existsSync(join(work, 'mutation')),
        repaired || ['race', 'tampered result'].includes(scenario), scenario);
      assert.equal((result.stdout + result.stderr).includes(secret), false, scenario);
      if (repaired) {
        const after = JSON.parse(readFileSync(join(work, 'identity.json')));
        assert.equal(after.metadata.uid, uid);
        assert.equal(after.metadata.annotations.private, secret);
        assert.equal(after.metadata.labels.retained, 'yes');
        assert.equal(after.metadata.labels['app.kubernetes.io/managed-by'], 'Helm');
        assert.equal(after.metadata.annotations['meta.helm.sh/release-name'], 'tuist');
        assert.equal(after.metadata.annotations['meta.helm.sh/release-namespace'], 'tuist-staging');
        delete after.metadata;
        delete identity.metadata;
        assert.deepEqual(after, identity);
      }
    }
  } finally { rmSync(work, { recursive: true, force: true }); }
});
