import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const script = fileURLToPath(new URL('./gradle-patch-release.sh', import.meta.url));

test('stable patches require the next version and merged, Gradle-only stable source', () => {
  const dir = mkdtempSync(join(tmpdir(), 'gradle-patch-'));
  const remote = join(dir, 'remote');
  const repo = join(dir, 'repo');
  mkdirSync(remote);
  mkdirSync(repo);
  function git(...args) {
    const result = spawnSync('git', args, { cwd: repo, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    return result.stdout.trim();
  }
  function commit(path, message) {
    writeFileSync(join(repo, path), message);
    git('add', '.');
    git('commit', '-qm', message);
    return git('rev-parse', 'HEAD');
  }
  let source;
  function plan(overrides = {}) {
    const output = join(dir, 'output');
    writeFileSync(output, '');
    const result = spawnSync('bash', [script], {
      cwd: repo, encoding: 'utf8',
      env: { ...process.env, GITHUB_EVENT_NAME: 'workflow_dispatch', GITHUB_REF: 'refs/heads/main',
        SOURCE_SHA: source, PATCH_VERSION: '0.18.1', GITHUB_OUTPUT: output, ...overrides },
    });
    return { ...result, output: readFileSync(output, 'utf8') };
  }
  function rejected(overrides = {}) {
    const result = plan(overrides);
    assert.notEqual(result.status, 0, result.stdout);
    assert.equal(result.output, '', 'Rejected plans must not enable publication');
  }
  try {
    git('init', '--bare', remote);
    git('init', '-b', 'main');
    git('config', 'user.email', 'fixture@example.invalid');
    git('config', 'user.name', 'Fixture');
    git('remote', 'add', 'origin', remote);
    mkdirSync(join(repo, 'gradle'));
    const stable = commit('gradle/plugin', 'stable');
    git('tag', 'gradle@0.18.0');
    git('push', '-q', 'origin', 'main', '--tags');
    git('switch', '-c', 'releases/gradle-0.18.x');
    source = stable;
    rejected(); // Missing release branch on origin.
    git('push', '-q', 'origin', 'HEAD');
    rejected(); // No patch source yet.
    source = commit('gradle/plugin', 'fix(gradle): TLS');
    rejected(); // Unmerged PR source is not the release branch head.
    git('push', '-q', 'origin', 'HEAD');
    const accepted = plan();
    assert.equal(accepted.status, 0, accepted.stderr);
    assert.equal(accepted.output, `gradle-should-release=true\ngradle-next-version=gradle@0.18.1\ngradle-next-version-number=0.18.1\nsource-sha=${source}\n`);
    for (const PATCH_VERSION of ['', '0.18.0', '0.18.2', '0.19.0', '1.0.0', 'gradle@0.18.1',
      '0.18.1-rc.1', '0.18.1+build', '00.18.1', '0.18.1\nextra', '$(echo injected)']) {
      rejected({ PATCH_VERSION });
    }
    for (const SOURCE_SHA of ['', source.slice(0, 12), 'main', stable, 'f'.repeat(40), `${source}\nextra`]) {
      rejected({ SOURCE_SHA });
    }
    rejected({ GITHUB_EVENT_NAME: 'push' });
    rejected({ GITHUB_REF: 'refs/heads/releases/gradle-0.18.x' });
    rejected({ GITHUB_REF: 'refs/heads/feature' });
    const validSource = source;
    source = commit('unrelated', 'unrelated source');
    git('push', '-q', 'origin', 'HEAD');
    rejected(); // Even a release branch cannot bring unrelated main code.
    git('reset', '--hard', validSource);
    git('push', '-q', '--force', 'origin', 'HEAD');
    source = validSource;
    git('checkout', '--orphan', 'unrelated-history');
    git('rm', '-rf', '.');
    mkdirSync(join(repo, 'gradle'));
    source = commit('gradle/plugin', 'not based on stable');
    git('push', '-q', '--force', 'origin', 'HEAD:releases/gradle-0.18.x');
    rejected(); // Gradle-only files do not substitute for stable ancestry.
    git('push', '-q', '--force', 'origin', `${validSource}:releases/gradle-0.18.x`);
    source = validSource;
    // A tag published between planning and release invalidates the old plan.
    git('--git-dir', remote, 'tag', 'gradle@0.18.1', source);
    rejected();
    assert.equal(plan({ PATCH_VERSION: '0.18.2' }).status, 1, 'No new source after the new stable tag');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
