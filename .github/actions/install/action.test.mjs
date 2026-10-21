import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const action = path.dirname(fileURLToPath(import.meta.url));
function fixture(t) {
  const root = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'tuist-install-')));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const workspace = path.join(root, 'checkout');
  const bin = path.join(root, 'bin');
  fs.mkdirSync(workspace);
  fs.mkdirSync(bin);
  const write = (p, content = '') => {
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, content);
  };
  const executable = (name, content) => {
    write(path.join(bin, name), `#!/bin/bash\nset -eu\n${content}\n`);
    fs.chmodSync(path.join(bin, name), 0o755);
  };
  executable('tuist-cache-volume', 'exit 0');
  executable('swift', 'printf "%s\\n" "${FAKE_SWIFT_VERSION:-Swift 6.3}"');
  executable('xcodebuild', 'printf "%s\\n" "${FAKE_XCODE_VERSION:-Xcode 27}"');
  executable('tuist', `if [[ "$1" == version ]]; then
    echo "\${FAKE_TUIST_VERSION:-4.214.0-canary.36}"
  else
    printf '%s\\0' "$@" > "$CAPTURE_ARGS"
    pwd -P > "$CAPTURE_CWD"
    env > "$CAPTURE_ENV"
    exit "\${FAKE_INSTALL_EXIT:-0}"
  fi`);
  const env = {
    ...process.env, PATH: `${bin}:${process.env.PATH}`, GITHUB_WORKSPACE: workspace,
    RUNNER_OS: 'macOS', RUNNER_ARCH: 'ARM64',
    GITHUB_JOB: 'generate', GITHUB_OUTPUT: path.join(root, 'output'),
    TUIST_INSTALL_PATH: '.', TUIST_INSTALL_CACHE_KEY: '', SWIFTPM_BUILD_DIR: '',
    CAPTURE_ARGS: path.join(root, 'args'), CAPTURE_CWD: path.join(root, 'cwd'),
    CAPTURE_ENV: path.join(root, 'env'),
  };
  const pkg = (relative = '') => {
    const dir = path.join(workspace, relative);
    write(path.join(dir, 'Package.swift'), '// swift-tools-version: 6.0\n');
    write(path.join(dir, 'Package.resolved'), '{"pins":[]}');
    return dir;
  };
  const prepare = (overrides = {}, source = action) => {
    write(env.GITHUB_OUTPUT);
    const result = spawnSync('bash', [path.join(source, 'prepare.sh')], {
      cwd: root, env: { ...env, ...overrides }, encoding: 'utf8',
    });
    const outputs = Object.fromEntries(fs.readFileSync(env.GITHUB_OUTPUT, 'utf8').trim().split('\n')
      .filter(Boolean).map(line => { const i = line.indexOf('='); return [line.slice(0, i), line.slice(i + 1)]; }));
    return { ...result, outputs };
  };
  const install = (outputs, overrides = {}, source = action) => spawnSync('bash', [path.join(source, 'install.sh')], {
    cwd: root, encoding: 'utf8', env: {
      ...env, TUIST_INSTALL_PROJECT_PATH: outputs['project-path'],
      TUIST_INSTALL_SCRATCH_PATH: outputs['scratch-path'],
      TUIST_INSTALL_CACHE_PATH: outputs['cache-path'],
      TUIST_INSTALL_MATERIALIZATION: outputs.materialization, ...overrides,
    },
  });
  return { root, workspace, bin, write, env, pkg, prepare, install };
}
function success(result) { assert.equal(result.status, 0, result.stderr); return result.outputs; }

test('root package and default key survive checkout moves, lock changes and CI metadata', t => {
  const f = fixture(t);
  f.pkg();
  const first = success(f.prepare());
  assert.equal(first['cache-path'], `${f.workspace}/.build/dependency-cache`);
  assert.equal(first.key, 'tuist-install-v1-generate');
  f.write(path.join(f.workspace, 'Package.resolved'), 'changed pins');
  assert.equal(success(f.prepare({ GITHUB_REF: 'another-branch', GITHUB_RUN_ID: '999' })).key, first.key);
  const moved = path.join(f.root, 'other-checkout');
  fs.cpSync(f.workspace, moved, { recursive: true });
  assert.equal(success(f.prepare({ GITHUB_WORKSPACE: moved })).key, first.key);
});

test('keys separate jobs and package locations, not toolchains or manifest contents', t => {
  const f = fixture(t);
  f.pkg();
  const key = success(f.prepare()).key;
  assert.equal(success(f.prepare({ GITHUB_JOB: 'test' })).key, 'tuist-install-v1-test');
  assert.equal(success(f.prepare({ FAKE_SWIFT_VERSION: 'Swift 7', FAKE_XCODE_VERSION: 'Xcode 28' })).key, key);
  f.write(path.join(f.workspace, 'Package.swift'), 'changed package structure');
  assert.equal(success(f.prepare()).key, key);
  f.pkg('apps/ios app');
  f.write(path.join(f.workspace, 'apps/ios app', 'Tuist.swift'));
  assert.equal(success(f.prepare({ TUIST_INSTALL_PATH: 'apps/ios app' })).key, 'tuist-install-v1-generate-apps/ios-app');
  f.pkg('Tuist');
  assert.equal(success(f.prepare()).key, 'tuist-install-v1-generate-Tuist');
  assert.notEqual(f.prepare({ GITHUB_JOB: 'j'.repeat(200) }).status, 0);
});

test('Tuist package takes precedence; nested input locates the project root', t => {
  const f = fixture(t);
  f.pkg();
  const pkg = f.pkg('Tuist');
  fs.mkdirSync(path.join(f.workspace, 'Sources'));
  const result = success(f.prepare({ TUIST_INSTALL_PATH: 'Sources' }));
  assert.equal(result['scratch-path'], `${pkg}/.build`);
  assert.equal(result['project-path'], `${f.workspace}/Sources`);
});

for (const marker of ['Tuist.swift', 'tuist.toml', 'Plugin.swift', '.git/HEAD']) {
  test(`root lookup recognizes ${marker}`, t => {
    const f = fixture(t);
    const pkg = f.pkg('app');
    f.write(path.join(pkg, marker));
    fs.mkdirSync(path.join(pkg, 'Sources'));
    assert.equal(success(f.prepare({ TUIST_INSTALL_PATH: 'app/Sources' }))['scratch-path'], `${pkg}/.build`);
  });
}

test('custom keys and shell-like paths remain literal; install forwards forced scratch/cache flags', t => {
  const f = fixture(t);
  const dir = 'app spaces $(touch injected);*';
  const pkg = f.pkg(dir);
  f.write(path.join(pkg, 'Tuist.swift'));
  const outputs = success(f.prepare({ TUIST_INSTALL_PATH: dir, TUIST_INSTALL_CACHE_KEY: 'shared/workspace-v2' }));
  assert.equal(outputs.key, 'shared/workspace-v2');
  success(f.install(outputs, {
    TUIST_INSTALL_ACTION_PATH: '/runner/random/action',
    APPLICATION_INPUT: 'preserve-me', GITHUB_TOKEN: 'fixture-token',
  }));
  const environment = fs.readFileSync(f.env.CAPTURE_ENV, 'utf8');
  assert.doesNotMatch(environment, /^TUIST_INSTALL_/m);
  assert.match(environment, /^APPLICATION_INPUT=preserve-me$/m);
  assert.match(environment, /^GITHUB_TOKEN=fixture-token$/m);
  assert.deepEqual(fs.readFileSync(f.env.CAPTURE_ARGS, 'utf8').split('\0').slice(0, -1), [
    'install', '--path', pkg, '--force-resolved-versions', '--scratch-path', `${pkg}/.build`,
    '--cache-path', `${pkg}/.build/dependency-cache`, '--cached-directory-materialization=symlink',
  ]);
  assert.equal(fs.readFileSync(f.env.CAPTURE_CWD, 'utf8').trim(), pkg);
  assert.equal(fs.existsSync(path.join(f.root, 'injected')), false);
  assert.equal(fs.existsSync(path.join(pkg, 'injected')), false);
  assert.equal(f.install(outputs, { FAKE_INSTALL_EXIT: '42' }).status, 42);
});

test('missing manifests, missing lockfiles, escaped paths and scratch overrides fail before attachment', t => {
  const f = fixture(t);
  assert.notEqual(f.prepare().status, 0);
  f.pkg();
  fs.rmSync(path.join(f.workspace, 'Package.resolved'));
  assert.match(f.prepare().stderr, /Commit Package.resolved/);
  f.pkg();
  assert.match(f.prepare({ TUIST_INSTALL_PATH: '..' }).stderr, /inside GITHUB_WORKSPACE/);
  assert.match(f.prepare({ SWIFTPM_BUILD_DIR: 'elsewhere' }).stderr, /Unset SWIFTPM_BUILD_DIR/);
  const outputs = success(f.prepare());
  assert.notEqual(f.install(outputs, { SWIFTPM_BUILD_DIR: 'elsewhere' }).status, 0);
});

test('newlines and invalid volume keys cannot inject step outputs', t => {
  const f = fixture(t);
  f.pkg();
  for (const key of ['bad\nkey=override', 'x'.repeat(201), '$(touch injected)', '-bad']) {
    const result = f.prepare({ TUIST_INSTALL_CACHE_KEY: key });
    assert.notEqual(result.status, 0);
    assert.deepEqual(result.outputs, {});
  }
  assert.notEqual(f.prepare({ TUIST_INSTALL_PATH: 'app\nkey=x' }).status, 0);
});

test('CLI versions without consolidated manifest caching fail; supported releases pass', t => {
  const f = fixture(t);
  f.pkg();
  for (const version of ['4.213.99', '4.214.0-canary.35', 'unexpected output']) {
    assert.notEqual(f.prepare({ FAKE_TUIST_VERSION: version }).status, 0);
  }
  for (const version of ['4.214.0-canary.36', '4.214.0-canary.100', '4.214.0', '4.215.0', '5.0.0']) {
    success(f.prepare({ FAKE_TUIST_VERSION: version }));
  }
});

test('standalone package works outside the source checkout and never overwrites existing output', t => {
  const f = fixture(t);
  f.pkg();
  const output = path.join(f.root, 'standalone action');
  const pack = () => spawnSync('bash', [path.join(action, 'scripts/package.sh'), output], { encoding: 'utf8' });
  success(pack());
  assert.deepEqual(fs.readdirSync(output).sort(), ['LICENSE.md', 'README.md', 'SOURCE_COMMIT', 'action.yml', 'install.sh', 'prepare.sh']);
  assert.match(fs.readFileSync(path.join(output, 'SOURCE_COMMIT'), 'utf8'), /^[a-f0-9]{40}\n$/);
  success(f.install(success(f.prepare({}, output)), {}, output));
  assert.notEqual(pack().status, 0);
});

test('auto uses the volume client with symlinks; otherwise GitHub archives with copies', t => {
  const f = fixture(t);
  f.pkg();
  const volume = success(f.prepare());
  assert.equal(volume.backend, 'volume');
  assert.equal(volume.materialization, 'symlink');
  assert.equal(volume['archive-key'], '');
  fs.rmSync(path.join(f.bin, 'tuist-cache-volume'));
  const archive = success(f.prepare());
  assert.equal(archive.backend, 'github');
  assert.equal(archive.materialization, 'copy');
  assert.equal(archive['archive-path'], './.build');
  success(f.install(archive));
  assert.match(fs.readFileSync(f.env.CAPTURE_ARGS, 'utf8'), /--cached-directory-materialization=copy\0/);
  assert.doesNotMatch(fs.readFileSync(f.env.CAPTURE_ENV, 'utf8'), /^TUIST_INSTALL_/m);
});

test('archive save key includes lockfile and platform; restore prefix survives pin changes', t => {
  const f = fixture(t);
  f.pkg('app');
  f.write(path.join(f.workspace, 'app/Tuist.swift'));
  fs.rmSync(path.join(f.bin, 'tuist-cache-volume'));
  const inputs = { TUIST_INSTALL_PATH: 'app', TUIST_INSTALL_CACHE_KEY: 'shared' };
  const first = success(f.prepare(inputs));
  assert.equal(first['archive-path'], './app/.build');
  assert.equal(first['archive-prefix'], 'tuist-install-github-v1-macOS-ARM64-shared-');
  assert.ok(first['archive-key'].startsWith(first['archive-prefix']));
  f.write(path.join(f.workspace, 'app/Package.resolved'), 'updated pins');
  const next = success(f.prepare(inputs));
  assert.notEqual(next['archive-key'], first['archive-key']);
  assert.equal(next['archive-prefix'], first['archive-prefix']);
  assert.notEqual(success(f.prepare({ ...inputs, RUNNER_ARCH: 'X64' }))['archive-prefix'], first['archive-prefix']);
  assert.notEqual(success(f.prepare({ ...inputs, RUNNER_OS: 'Linux' }))['archive-prefix'], first['archive-prefix']);
  const moved = path.join(f.root, 'another-checkout');
  fs.cpSync(f.workspace, moved, { recursive: true });
  const restored = success(f.prepare({ ...inputs, GITHUB_WORKSPACE: moved }));
  assert.equal(restored['archive-key'], next['archive-key']);
  assert.equal(restored['archive-path'], next['archive-path']);
});

test('archive paths escape glob characters in literal package directories', t => {
  const f = fixture(t);
  f.pkg('app[1]*?');
  f.write(path.join(f.workspace, 'app[1]*?/Tuist.swift'));
  fs.rmSync(path.join(f.bin, 'tuist-cache-volume'));
  assert.equal(success(f.prepare({ TUIST_INSTALL_PATH: 'app[1]*?' }))['archive-path'], './app[[]1[]][*][?]/.build');
});
