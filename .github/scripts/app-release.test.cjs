const assert = require('node:assert/strict');
const { test } = require('node:test');
const { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { spawnSync } = require('node:child_process');
const yaml = require('js-yaml');

const workflow = yaml.load(readFileSync(join(__dirname, '../workflows/app-release.yml'), 'utf8'));

function condition(job, event, results = {}, cancelled = false) {
  const expression = workflow.jobs[job].if.replace(/\.([\w]+-[\w-]+)/g, '["$1"]');
  const needs = Object.fromEntries(['check-releases', 'release-app', 'release-ios', 'release-android'].map(name => [name, {
    result: results[name] || 'success', outputs: { 'app-should-release': 'true' },
  }]));
  return Function('github', 'needs', 'always', 'cancelled', `return (${expression})`)(
    { event_name: event }, needs, () => true, () => cancelled,
  );
}

test('manual hotfix skips both stores but publishes only after macOS succeeds', () => {
  assert.equal(condition('release-ios', 'workflow_dispatch'), false);
  assert.equal(condition('release-android', 'workflow_dispatch'), false);
  const skipped = { 'release-ios': 'skipped', 'release-android': 'skipped' };
  assert.equal(condition('publish-app', 'workflow_dispatch', skipped), true);
  for (const name of ['check-releases', 'release-app']) {
    for (const result of ['failure', 'cancelled', 'skipped']) {
      assert.equal(condition('publish-app', 'workflow_dispatch', { ...skipped, [name]: result }), false);
    }
  }
  assert.equal(condition('publish-app', 'workflow_dispatch', skipped, true), false);
});

test('ordinary push retains all three platform gates', () => {
  assert.equal(condition('release-ios', 'push'), true);
  assert.equal(condition('release-android', 'push'), true);
  assert.equal(condition('publish-app', 'push'), true);
  for (const name of ['release-app', 'release-ios', 'release-android']) {
    for (const result of ['failure', 'cancelled', 'skipped']) {
      assert.equal(condition('publish-app', 'push', { [name]: result }), false);
    }
  }
});

test('build and publisher pin source with explicit release-token fallback', () => {
  for (const job of ['release-app', 'publish-app']) {
    const checkout = workflow.jobs[job].steps.find(step => step.uses === 'actions/checkout@v4');
    assert.equal(checkout.with.ref, '${{ needs.check-releases.outputs.source-sha }}');
  }
  const publish = workflow.jobs['publish-app'].steps.find(step => step.name === 'Create App GitHub Release');
  assert.equal(publish.with.target_commitish, '${{ needs.check-releases.outputs.source-sha }}');
  assert.equal(publish.with.token, '${{ secrets.TUIST_RELEASE_GITHUB_TOKEN || github.token }}');
  assert.match(workflow.jobs['check-releases'].if, /github.ref == 'refs\/heads\/main'/);
});

test('all app releases retain the legacy main concurrency lock without cancellation', () => {
  assert.equal(workflow.concurrency.group, 'app-release-refs/heads/main');
  assert.equal(workflow.concurrency['cancel-in-progress'], false);
});

test('actual pre-publication guard refetches the merged tip and rejects unmerged or replaced source', () => {
  const directory = mkdtempSync(join(tmpdir(), 'app-source-guard-'));
  try {
    const git = (...args) => {
      const result = spawnSync('git', args, { cwd: directory, encoding: 'utf8' });
      assert.equal(result.status, 0, result.stderr);
      return result.stdout.trim();
    };
    git('init', '--quiet');
    git('config', 'user.name', 'Fixture');
    git('config', 'user.email', 'fixture@example.invalid');
    git('commit', '--quiet', '--allow-empty', '-m', 'Stable');
    const base = git('rev-parse', 'HEAD');
    git('commit', '--quiet', '--allow-empty', '-m', 'TLS backport');
    const source = git('rev-parse', 'HEAD');
    git('init', '--quiet', '--bare', join(directory, 'remote.git'));
    git('remote', 'add', 'origin', join(directory, 'remote.git'));
    const branch = 'releases/app-0.27.1';
    git('push', 'origin', `${base}:refs/heads/${branch}`);
    const steps = workflow.jobs['publish-app'].steps;
    const index = steps.findIndex(step => step.name === 'Revalidate merged hotfix source and tag');
    assert.equal(steps[index + 1].name, 'Create App GitHub Release');
    const run = () => spawnSync('bash', ['-e', '-c', steps[index].run], {
      cwd: directory, encoding: 'utf8',
      env: { ...process.env, SOURCE_SHA: source, RELEASE_BRANCH: branch, RELEASE_TAG: 'app@0.27.2', RUNNER_TEMP: directory },
    });
    assert.notEqual(run().status, 0, 'Unmerged hotfix must not publish');
    git('push', 'origin', `${source}:refs/heads/${branch}`);
    const merged = run();
    assert.equal(merged.status, 0, merged.stderr);
    git('push', '--force', 'origin', `${base}:refs/heads/${branch}`);
    assert.notEqual(run().status, 0, 'Replaced remote tip must not use a stale fetched tip');
    git('push', 'origin', '--delete', branch);
    assert.notEqual(run().status, 0, 'Deleted remote branch must fail closed');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

test('actual appcast gate rejects stale, mismatched, unsigned or missing payload metadata', () => {
  const directory = mkdtempSync(join(tmpdir(), 'appcast-gate-'));
  try {
    mkdirSync(join(directory, 'app/build/artifacts'), { recursive: true });
    writeFileSync(join(directory, 'app/Project.swift'), '"CFBundleVersion": "1793260800",');
    writeFileSync(join(directory, 'app/build/artifacts/Tuist.dmg'), 'fixture');
    const item = (version, build, url = `https://github.com/tuist/tuist/releases/download/app@${version}/Tuist.dmg`, length = 7, signature = 'fixture-signature') => `
      <item><sparkle:shortVersionString>${version}</sparkle:shortVersionString><sparkle:version>${build}</sparkle:version>
      <enclosure url="${url}" length="${length}" sparkle:edSignature="${signature}"/></item>`;
    const candidate = item('0.27.2', 1793260800);
    const older = item('0.27.1', 1791997442);
    const run = items => {
      writeFileSync(join(directory, 'app/appcast.xml'), `<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>${items}</channel></rss>`);
      const script = workflow.jobs['release-app'].steps.find(step => step.name === 'Validate Sparkle appcast').run;
      return spawnSync('bash', ['-e', '-c', script], { cwd: directory, env: { ...process.env, RELEASE_TAG: 'app@0.27.2' }, encoding: 'utf8' });
    };
    const valid = run(candidate + older);
    assert.equal(valid.status, 0, valid.stderr);
    for (const items of [older, candidate + candidate, item('0.27.2', 1793260799),
      item('0.27.2', 1793260800, 'https://example.invalid/wrong.dmg'),
      item('0.27.2', 1793260800, undefined, 8), item('0.27.2', 1793260800, undefined, 7, ''),
      candidate + item('0.28.0', 1793260801), candidate + item('0.28.0', 1791997443)]) {
      assert.notEqual(run(items).status, 0, items);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
