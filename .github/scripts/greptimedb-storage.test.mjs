import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

// Reuse the existing transport fixtures against the replacement's exact script
// and each bucket; no network or credentials are involved.
for (const environment of ['staging', 'canary', 'production']) {
  test(`storage safety scenarios for ${environment}`, () => {
    const source = readFileSync('.github/scripts/openobserve-preflight.test.mjs', 'utf8')
      .replaceAll('.github/scripts/openobserve-storage-check.sh', '.github/scripts/greptimedb-storage-check.sh')
      .replace("['openobserve', 'greptimedb']", "['greptimedb']")
      .replaceAll('staging', environment);
    const result = spawnSync(process.execPath, ['--input-type=module', '-e', source], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stdout + result.stderr);
  });
}
