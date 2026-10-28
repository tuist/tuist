import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
const script = fileURLToPath(new URL('store-credentials.sh', import.meta.url));
for (const existing of [false, true]) {
  test(`isolated login ${existing ? 'updates' : 'creates'} only its environment credential item`, (t) => {
    const dir = mkdtempSync(join(tmpdir(), 'orb-enroll-'));
    t.after(() => rmSync(dir, { recursive: true, force: true }));
    mkdirSync(join(dir, 'bin'));
    writeFileSync(join(dir, 'bin/tuist'), `#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'auth login --url https://canary.tuist.dev' ]]
[[ -z \${TUIST_TOKEN:-} && -z \${TUIST_XDG_CONFIG_HOME:-} ]]
printf '%s' "$XDG_CONFIG_HOME" > "$FIXTURE/config-path"
mkdir -p "$XDG_CONFIG_HOME/tuist/credentials"
echo '{"accessToken":"private-access","refreshToken":"private-refresh","oauthClientID":"cli"}' > "$XDG_CONFIG_HOME/tuist/credentials/canary.tuist.dev.json"
`, { mode: 0o755 });
    writeFileSync(join(dir, 'bin/op'), `#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "$*" >> "$FIXTURE/op-calls"
if [[ "$1 $2" == 'item list' ]]; then
  echo '${existing ? '[{"id":"existing-id","title":"Amp Orb Tuist Credentials"}]' : '[]'}'
else
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == --template ]]; then cp "$2" "$FIXTURE/stored.json"; break; fi
    shift
  done
  # Even if op emits fields, the helper prints only metadata.
  echo '{"id":"id","title":"Amp Orb Tuist Credentials","vault":{"name":"tuist-k8s-canary"},"fields":[{"value":"private-refresh"}]}'
fi
`, { mode: 0o755 });
    const result = spawnSync('bash', [script, 'canary'], {
      env: { ...process.env, PATH: `${dir}/bin:${process.env.PATH}`, FIXTURE: dir,
        TUIST_TOKEN: 'must-not-be-reused', TUIST_XDG_CONFIG_HOME: '/must-not-touch' }, encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stderr);
    assert.doesNotMatch(result.stdout + result.stderr, /private-access|private-refresh/);
    const calls = readFileSync(join(dir, 'op-calls'), 'utf8');
    assert.match(calls, /--vault tuist-k8s-canary/);
    assert.match(calls, existing ? /item edit existing-id/ : /item create/);
    assert.doesNotMatch(calls, /private-access|private-refresh/);
    const item = JSON.parse(readFileSync(join(dir, 'stored.json'), 'utf8'));
    assert.equal(item.title, 'Amp Orb Tuist Credentials');
    assert.deepEqual(JSON.parse(item.fields[0].value), { accessToken: 'private-access', refreshToken: 'private-refresh', oauthClientID: 'cli' });
    assert.equal(existsSync(readFileSync(join(dir, 'config-path'), 'utf8')), false);
  });
}
