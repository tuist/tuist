import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

test('live gate requires all recent real signals and excludes every CI run', () => {
  const work = mkdtempSync(join(tmpdir(), 'greptime-live-'));
  try {
    writeFileSync(join(work, 'dashboard'), 'dashboard:ro=synthetic-test-password\n');
    writeFileSync(join(work, 'preload.mjs'), String.raw`
import assert from 'node:assert/strict';
let ticks = 0;
Date.now = () => ++ticks <= 3 ? 1800000000000 : 1800000600000;
globalThis.setTimeout = callback => { callback(); };
globalThis.fetch = async (input, options) => {
  assert.equal(options.headers['X-Greptime-DB-Name'], 'public');
  const url = new URL(input);
  const scenario = process.env.SCENARIO;
  if (scenario === 'HTTP failure') return new Response('sensitive upstream body', {status:503});
  if (url.pathname.includes('/prometheus/')) {
    return Response.json({status:'success',data:{result:scenario === 'missing metrics' ? [] : [{value:[0,'1']}]}});
  }
  const sql = url.searchParams.get('sql');
  assert.match(sql, /timestamp >= '20/);
  assert.match(sql, /!= 'greptimedb-ci'/);
  if (sql.includes('opentelemetry_logs')) {
    assert.match(sql, /json_get_string\(resource_attributes/);
    assert.match(sql, /service.name/);
    assert.ok(!sql.includes('body NOT LIKE'));
  }
  const absent = scenario === 'missing logs' && sql.includes('opentelemetry_logs') ||
    scenario === 'missing traces' && sql.includes('opentelemetry_traces');
  return Response.json(scenario === 'SQL failure' ? {code:1000,error:'sensitive upstream body'} :
    {output:[{records:{rows:[[absent ? 0 : 1]]}}]});
};
`);
    for (const scenario of ['success', 'missing metrics', 'missing logs', 'missing traces', 'HTTP failure', 'SQL failure']) {
      const result = spawnSync(process.execPath, ['--import', join(work, 'preload.mjs'), '.github/scripts/greptimedb-live-smoke.mjs'], {
        encoding: 'utf8', timeout: 10000,
        env: {...process.env, SCENARIO: scenario, GREPTIMEDB_URL: 'http://synthetic.invalid',
          GREPTIMEDB_DASHBOARD_AUTH_FILE: join(work, 'dashboard')},
      });
      assert.equal(result.status, scenario === 'success' ? 0 : 1, `${scenario}: ${result.stdout}${result.stderr}`);
      assert.ok(!(result.stdout + result.stderr).includes('sensitive upstream body'));
      assert.ok(!(result.stdout + result.stderr).includes('synthetic-test-password'));
    }
  } finally { rmSync(work, {recursive:true, force:true}); }
});
