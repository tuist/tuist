import assert from 'node:assert/strict';
import { execFile, spawnSync } from 'node:child_process';
import { createServer } from 'node:http';
import { chmodSync, existsSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const reporter = fileURLToPath(new URL('./iteration_benchmark.mjs', import.meta.url));
const save = (path, value) => writeFileSync(path, JSON.stringify(value));
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const invoke = (...args) => spawnSync(process.execPath, [reporter, ...args], { encoding: 'utf8' });
const temporary = t => {
  const root = mkdtempSync(join(tmpdir(), 'cargo-iteration-test-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  return root;
};

test('sample manifests are isolated across runs, lanes, scenarios and rounds, not modes or phases', t => {
  const root = temporary(t);
  const driver = readFileSync(new URL('./iteration_benchmark.sh', import.meta.url), 'utf8');
  // Exercise the real sample lifecycle and workspace generation without a toolchain or remote service.
  // Replace builds with config snapshots; do not duplicate TAG construction or source-edit orchestration.
  const functions = driver.slice(driver.indexOf('write_workspace() {'), driver.indexOf('\nfor LANE in $LANES;'));
  const result = spawnSync('bash', ['-euc', `${functions}
    CARGO_BINARY=$(command -v true)
    JOBS=1 REPORTER=unused LOCAL_SERVER=http://localhost PROJECT=fixture/iteration SERVER=http://localhost ENDPOINT=http://localhost TOKEN=unused
    node() { :; }
    check_outputs() { :; }
    build() { cp "$WORKSPACE/.cargo/config.toml" "$SAMPLE/$1-config.toml"; }
    for run in run-a run-b; do
      ROOT="$1/$run"
      for LANE in normal no-incremental; do
        for SCENARIO in I5 R1 R3; do
          for ROUND in 1 2; do
            for mode in cargo local remote; do sample "$mode"; done
          done
        done
      done
    done
  `, 'manifest-isolation-test', root], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  const scopes = new Set();
  for (const run of ['run-a', 'run-b']) for (const lane of ['normal', 'no-incremental']) {
    for (const scenario of ['I5', 'R1', 'R3']) for (const round of [1, 2]) {
      let paired;
      for (const mode of ['cargo', 'local', 'remote']) {
        const directory = join(root, run, lane, scenario, `round-${round}`, mode);
        const config = readFileSync(join(directory, 'workspace', '.cargo', 'config.toml'), 'utf8');
        assert.match(config, /^# [^\n]+\n$/, 'Scope must be a comment, not a build-setting change');
        if (paired !== undefined) assert.equal(config, paired, 'Paired configurations must share a scope');
        paired = config;
        const phases = ['measured'];
        if (scenario !== 'R1') phases.push('prime');
        if (scenario === 'I5') phases.push('edited');
        if (mode === 'remote' && lane === 'no-incremental' && scenario === 'R1') phases.push('remote-proof');
        for (const phase of phases) {
          assert.equal(readFileSync(join(directory, `${phase}-config.toml`), 'utf8'), config,
            'Priming, editing, restoration and publication proof must retain the scope');
        }
      }
      assert.ok(!scopes.has(paired), 'Independent samples must not share a prefetch manifest');
      scopes.add(paired);
    }
  }
  assert.equal(scopes.size, 24);
});

test('summary pairs rounds instead of dividing or subtracting aggregate medians', t => {
  const root = temporary(t);
  save(join(root, 'metadata.json'), { settings: 'normal', scenarios: ['I2'], rounds: 3, remote_enabled: false, skipped: [] });
  for (const [configuration, times] of [['cargo', [10, 100, 1000]], ['local', [20, 50, 3000]]]) {
    times.forEach((wall_ms, index) => {
      const directory = join(root, 'normal', 'I2', `round-${index + 1}`, configuration);
      mkdirSync(directory, { recursive: true });
      save(join(directory, 'measured.json'), { settings: 'normal', scenario: 'I2', round: index + 1,
        configuration, wall_ms, status: 0, verified: true });
    });
  }
  assert.equal(invoke('summarize', root).status, 0);
  const row = read(join(root, 'results.json')).rows.find(r => r.key === 'normal/I2/local');
  assert.equal(row.median_ms, 50);
  assert.equal(row.iqr_ms, 1490);
  assert.equal(row.median_paired_delta_ms, 10);
  assert.equal(row.median_paired_ratio, 2);

  rmSync(join(root, 'normal', 'I2', 'round-1', 'local'), { recursive: true });
  assert.notEqual(invoke('summarize', root).status, 0, 'Incomplete comparisons must not produce a successful report');
});

test('summary rejects an entirely missing configuration and unverified results', t => {
  const root = temporary(t);
  save(join(root, 'metadata.json'), { settings: 'normal', scenarios: ['I1'], rounds: 1, remote_enabled: false, skipped: [] });
  const directory = join(root, 'normal', 'I1', 'round-1', 'cargo');
  mkdirSync(directory, { recursive: true });
  const sample = { settings: 'normal', scenario: 'I1', round: 1, configuration: 'cargo', wall_ms: 5, status: 0, verified: true };
  save(join(directory, 'measured.json'), sample);
  assert.match(invoke('summarize', root).stderr, /Missing or duplicate samples/);
  sample.verified = false;
  save(join(directory, 'measured.json'), sample);
  assert.match(invoke('summarize', root).stderr, /unverified sample/);
});

test('failed measurements preserve status and redact credentials', t => {
  const root = temporary(t);
  const token = 'fixture-sensitive-token';
  const result = spawnSync(process.execPath, [reporter, 'measure', root, 'measured', '1', 'normal', 'I1', 'local',
    process.execPath, '-e', 'console.log(process.env.TUIST_TOKEN); process.exit(7)'], {
    env: { ...process.env, TUIST_TOKEN: token, XDG_CACHE_HOME: join(root, 'cache') }, encoding: 'utf8',
  });
  assert.notEqual(result.status, 0);
  const sample = read(join(root, 'measured.json'));
  assert.equal(sample.status, 7);
  assert.equal(sample.verified, false);
  assert.ok(sample.wall_ms > 0);
  assert.equal(readFileSync(join(root, 'measured.log'), 'utf8').trim(), '[REDACTED]');
});

test('production and credential-bearing remote endpoints are rejected', () => {
  assert.notEqual(invoke('endpoints', 'https://tuist.dev', 'http://localhost:9090').status, 0);
  assert.notEqual(invoke('endpoints', 'http://secret@localhost:8080', 'http://localhost:9090').status, 0);
  assert.equal(invoke('endpoints', 'http://localhost:8080', 'http://127.0.0.1:9090').status, 0);
});

test('toolchain resolution bypasses PATH Cargo decorators and rejects wrappers returned by rustup', t => {
  const root = temporary(t);
  const bin = join(root, 'bin');
  mkdirSync(bin);
  const cargo = join(bin, 'cargo');
  writeFileSync(cargo, '#!/bin/sh\nexit 99\n');
  const rustup = join(bin, 'rustup');
  writeFileSync(rustup, `#!/bin/sh\nif [ "$1" = show ]; then echo 'stable-test (default)'; else printf '%s\\n' '${process.execPath}'; fi\n`);
  chmodSync(cargo, 0o755); chmodSync(rustup, 0o755);
  const resolve = () => spawnSync(process.execPath, [reporter, 'toolchain', root], {
    env: { ...process.env, PATH: `${bin}:${process.env.PATH}` }, encoding: 'utf8',
  });
  assert.equal(resolve().status, 0);
  assert.deepEqual(read(join(root, 'toolchain.json')), {
    toolchain: 'stable-test', cargo: process.execPath, rustc: process.execPath,
  });
  writeFileSync(rustup, `#!/bin/sh\nif [ "$1" = show ]; then echo 'stable-test (default)'; else printf '%s\\n' '${cargo}'; fi\n`);
  assert.match(resolve().stderr, /Refusing a non-native cargo wrapper/);
});

const remoteFixture = async t => {
  const root = temporary(t);
  const state = { tokenStatus: 200, detailReads: 0, detail: () => ({ id: 'build-id', status: 'success',
    cache: null, compilations: [], compilations_truncated: false }) };
  // Only the report-observation contract is stubbed here. This is not a remote-cache integration test.
  const server = createServer((request, response) => {
    assert.equal(request.headers.authorization, 'Bearer fixture-token');
    response.setHeader('Content-Type', 'application/json');
    if (request.url.startsWith('/api/cache/token?')) {
      assert.equal(request.method, 'POST');
      assert.equal(new URL(request.url, 'http://localhost').searchParams.get('full_handle'), 'fixture/iteration');
      response.writeHead(state.tokenStatus).end(JSON.stringify({ token: 'private-cache-token', expires_in: 3600 }));
    } else if (request.url.includes('?')) response.end(JSON.stringify({ builds: [{ id: 'build-id' }] }));
    else { state.detailReads++; response.end(JSON.stringify(state.detail(state.detailReads))); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => server.close());
  const env = { ...process.env, TUIST_URL: `http://127.0.0.1:${server.address().port}`,
    TUIST_PROJECT: 'fixture/iteration', TUIST_TOKEN: 'fixture-token' };
  const call = (...args) => promisify(execFile)(process.execPath, [reporter, ...args], { env });
  return { root, state, call, observe: (phase = 'measured') => call('remote-report', root, phase, 'unique-branch') };
};

test('remote restoration requires observed hits and downloads, not just a successful build', async t => {
  const { root, state, call, observe } = await remoteFixture(t);
  save(join(root, 'measured.json'), { settings: 'no-incremental', scenario: 'R3', cache_bytes_before: 0 });
  await call('remote-setup', root, 'measured');
  let cache = { hits: 0, misses: 2, downloaded_bytes: 0, remote_failures: 0, background_upload_failures: 0 };
  state.detail = () => ({ id: 'build-id', status: 'success', cache, compilations: [{}, {}], compilations_truncated: false });
  await assert.rejects(observe(), /did not demonstrate remote reuse/);
  cache = { ...cache, hits: 2, downloaded_bytes: 4096 };
  await observe();
  assert.equal(read(join(root, 'measured.json')).observed_remote_reuse, true);
  cache = { ...cache, remote_failures: 1 };
  await assert.rejects(observe(), /refusing a fallback benchmark/);
});

test('remote cold samples reject unavailable credentials and missing or zero cache decisions', async t => {
  const { root, state, call, observe } = await remoteFixture(t);
  save(join(root, 'measured.json'), { settings: 'no-incremental', scenario: 'R1', cache_bytes_before: 0 });
  state.tokenStatus = 403;
  await assert.rejects(call('remote-setup', root, 'measured'), /Fixture API returned 403/);
  assert.equal(existsSync(join(root, 'measured-remote-setup.json')), false);
  await assert.rejects(observe(), /measured-remote-setup/);
  state.tokenStatus = 200;
  await call('remote-setup', root, 'measured');
  assert.ok(!readFileSync(join(root, 'measured-remote-setup.json'), 'utf8').includes('private-cache-token'));
  const detail = state.detail();
  for (const cache of [null, { hits: 0, misses: 0 }]) {
    state.detail = () => ({ ...detail, cache, compilations: [{}, {}, {}, {}] });
    await assert.rejects(observe(), /Missing cache decisions/);
  }
});

test('remote reports wait for delayed compiler rows, accounting for observed cache hits', async t => {
  const { root, state, call, observe } = await remoteFixture(t);
  save(join(root, 'measured.json'), { settings: 'no-incremental', scenario: 'R3', cache_bytes_before: 0 });
  await call('remote-setup', root, 'measured');
  state.detail = reads => ({ id: 'build-id', status: 'success', compilations_truncated: false,
    cache: { hits: 2, misses: 0, downloaded_bytes: 1024 }, compilations: reads === 1 ? [] : [{}, {}] });
  await observe();
  assert.equal(read(join(root, 'measured.json')).compiler_executions, 2);
});

test('normal incremental reports without transfer evidence remain explicitly remote-configured', async t => {
  const { root, call, observe } = await remoteFixture(t);
  save(join(root, 'measured.json'), { settings: 'normal', scenario: 'I1', round: 1,
    configuration: 'remote', wall_ms: 30, status: 0, verified: true, cache_bytes_before: 10 });
  await call('remote-setup', root, 'measured');
  await observe();
  const remote = read(join(root, 'measured.json'));
  assert.equal(remote.remote_activity, 'unproven');
  save(join(root, 'metadata.json'), { settings: 'normal', scenarios: ['I1'], rounds: 1, remote_enabled: true, skipped: [] });
  rmSync(join(root, 'measured.json'));
  for (const configuration of ['cargo', 'local', 'remote']) {
    const directory = join(root, 'normal', 'I1', 'round-1', configuration);
    mkdirSync(directory, { recursive: true });
    save(join(directory, 'measured.json'), { ...remote, configuration });
  }
  assert.equal(invoke('summarize', root).status, 0);
  const summary = readFileSync(join(root, 'results.md'), 'utf8');
  assert.match(summary, /normal\/I1\/remote-configured/);
  assert.match(summary, /without measured transfer or publication evidence: 1/);
});

test('cold publication requires a separate empty-client restore, even when upload counts are zero', async t => {
  const { root, state, call, observe } = await remoteFixture(t);
  save(join(root, 'measured.json'), { settings: 'no-incremental', scenario: 'R1', cache_bytes_before: 0 });
  await call('remote-setup', root, 'measured');
  state.detail = () => ({ id: 'build-id', status: 'success', compilations_truncated: false,
    cache: { hits: 0, misses: 2, uploaded_bytes: 0 }, compilations: [{}, {}, {}, {}] });
  await observe();
  assert.equal(read(join(root, 'measured.json')).remote_activity, 'unproven');
  save(join(root, 'remote-proof.json'), { settings: 'no-incremental', scenario: 'R1', cache_bytes_before: 0 });
  await call('remote-setup', root, 'remote-proof');
  await assert.rejects(observe('remote-proof'), /did not demonstrate remote reuse/);
  await assert.rejects(call('remote-publication', root), /did not demonstrate remote reuse/);
  state.detail = () => ({ id: 'build-id', status: 'success', compilations_truncated: false,
    cache: { hits: 2, misses: 0, downloaded_bytes: 4096 }, compilations: [{}, {}] });
  await observe('remote-proof');
  await call('remote-publication', root);
  assert.equal(read(join(root, 'measured.json')).observed_remote_publication, true);
});
