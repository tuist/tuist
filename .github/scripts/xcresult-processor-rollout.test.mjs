import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import yaml from 'js-yaml';

const workflow = yaml.load(readFileSync(new URL('../workflows/server-deployment.yml', import.meta.url), 'utf8'));
const rollout = Object.values(workflow.jobs).flatMap(job => job.steps ?? [])
  .find(step => step.name === 'xcresult processor rollout');

test('a failed processor rollout blocks canary promotion, not staging', () => {
  assert.equal(rollout['continue-on-error'], "${{ inputs.environment != 'canary' }}");
  assert.match(rollout.if, /inputs.environment != 'production'/);
});

for (const status of [0, 1]) {
  test(`the real rollout shell ${status === 0 ? 'accepts readiness' : 'fails when the processor is not Ready'}`, (t) => {
    const dir = mkdtempSync(join(tmpdir(), 'xcresult-rollout-'));
    t.after(() => rmSync(dir, { recursive: true, force: true }));
    writeFileSync(join(dir, 'kubectl'), `#!/bin/sh
case "$*" in *"rollout status"*) exit ${status} ;; esac
`, { mode: 0o755 });
    const result = spawnSync('bash', ['--noprofile', '--norc', '-e', '-o', 'pipefail', '-c', rollout.run], {
      env: { ...process.env, PATH: `${dir}:${process.env.PATH}`, NAMESPACE: 'canary-test',
        XCRESULT_PROCESSOR_DEPLOYMENT: 'processor-test', GITHUB_STEP_SUMMARY: join(dir, 'summary') },
      encoding: 'utf8', timeout: 5000,
    });
    assert.equal(result.status, status, result.stderr);
    if (status === 1) assert.match(readFileSync(join(dir, 'summary'), 'utf8'), /xcresult processor not Ready/);
  });
}
