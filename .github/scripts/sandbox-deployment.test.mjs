import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const scripts = dirname(fileURLToPath(import.meta.url));
const root = join(scripts, '../..');
const versionScript = join(scripts, 'sandbox-image-version.sh');
const tagScript = join(scripts, 'sandbox-template-tag.sh');
const image = 'ghcr.io/tuist/tuist-sandbox-template';
const env = { ...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null' };

function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'sandbox-deploy-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function git(dir, ...args) {
  const result = spawnSync('git', args, { cwd: dir, env, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

function repository(t) {
  const dir = fixture(t);
  git(dir, 'init', '-q');
  git(dir, 'config', 'user.email', 'test@example.invalid');
  git(dir, 'config', 'user.name', 'Sandbox test');
  git(dir, 'config', 'commit.gpgsign', 'false');
  return dir;
}

function commit(dir, path, contents) {
  mkdirSync(dirname(join(dir, path)), { recursive: true });
  writeFileSync(join(dir, path), contents);
  git(dir, 'add', path);
  git(dir, 'commit', '-qm', path);
  return git(dir, 'rev-parse', 'HEAD');
}

function version(dir) {
  const result = spawnSync('bash', [versionScript], { cwd: dir, env, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout.trim();
}

test('unrelated server changes reuse the published template version', (t) => {
  const dir = repository(t);
  const sha = commit(dir, 'infra/sandbox-image/Dockerfile', 'FROM scratch');
  commit(dir, 'server/app.ex', 'server change');
  assert.equal(version(dir), `sha-${sha.slice(0, 12)}`);
});

test('image, bootstrap and publisher changes each select a new template', (t) => {
  const dir = repository(t);
  for (const path of ['infra/sandbox-image/Dockerfile', 'infra/sandbox-image/orb-bootstrap.sh', 'infra/amp-orbs/Dockerfile',
    '.github/workflows/sandbox-image.yml', '.github/scripts/sandbox-image-version.sh']) {
    const sha = commit(dir, path, path);
    assert.equal(version(dir), `sha-${sha.slice(0, 12)}`);
  }
});

test('an older deployment selects its own source, not a newer branch or tag', (t) => {
  const dir = repository(t);
  const original = commit(dir, 'infra/sandbox-image/Dockerfile', 'old');
  const target = commit(dir, 'server/app.ex', 'server');
  commit(dir, 'infra/sandbox-image/Dockerfile', 'new');
  git(dir, 'tag', 'newer-template');
  git(dir, 'checkout', '--detach', target);
  assert.equal(version(dir), `sha-${original.slice(0, 12)}`);
});

test('missing template history fails instead of producing an invalid tag', (t) => {
  const dir = repository(t);
  commit(dir, 'server/app.ex', 'no template');
  const result = spawnSync('bash', [versionScript], { cwd: dir, env, encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.equal(result.stdout, '');
});

function selectTag(t, { current = `${image}:sha-aaaaaaaaaaaa`, requested = '', status = '0' } = {}) {
  const dir = fixture(t);
  const calls = join(dir, 'calls');
  writeFileSync(join(dir, 'kubectl'), '#!/bin/sh\nprintf "%s\\n" "$@" > "$CALLS"\nprintf "%s" "$CURRENT_IMAGE"\nexit "$KUBE_STATUS"\n', { mode: 0o755 });
  const result = spawnSync('bash', [tagScript, 'custom-sandboxes', 'custom-sandboxd', `${image}:sha-000000000000`, requested], {
    env: { ...env, PATH: `${dir}:${env.PATH}`, CALLS: calls, CURRENT_IMAGE: current, KUBE_STATUS: status },
    encoding: 'utf8',
  });
  return { ...result, calls };
}

test('published or explicit tag wins even on a first installation', (t) => {
  const result = selectTag(t, { requested: 'sha-bbbbbbbbbbbb', status: '1' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'sha-bbbbbbbbbbbb');
});

test('server-only rollback preserves the live template instead of the chart pin', (t) => {
  const result = selectTag(t);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout.trim(), 'sha-aaaaaaaaaaaa');
  const calls = readFileSync(result.calls, 'utf8');
  assert.match(calls, /-n\ncustom-sandboxes\nget\ndaemonset\ncustom-sandboxd\n/);
  assert.match(calls, /initContainers.*template/);
});

test('missing live template or a failed cluster read blocks a server-only re-promotion', (t) => {
  for (const options of [{ current: '' }, { status: '1' }]) {
    const result = selectTag(t, options);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
  }
});

test('unexpected repositories and mutable or malformed tags fail closed', (t) => {
  for (const options of [
    { current: 'other.invalid/template:sha-aaaaaaaaaaaa' },
    { current: `${image}:latest` },
    { requested: 'latest' },
    { requested: 'sha-abcdef,server.enabled=false' },
  ]) {
    const result = selectTag(t, options);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
  }
});

test('template-only changes enter the same deployable-path gate as server changes', () => {
  const workflow = readFileSync(join(scripts, '../workflows/server-production-deployment.yml'), 'utf8');
  const filter = workflow.match(/deployable_paths=.*?grep -E '([^']+)'/s)?.[1];
  assert.ok(filter, 'production deployment path filter exists');
  for (const path of ['infra/sandbox-image/Dockerfile', 'infra/sandbox-image/orb-bootstrap.sh', 'infra/amp-orbs/Dockerfile',
    '.github/workflows/sandbox-image.yml', '.github/scripts/sandbox-image-version.sh',
    '.github/scripts/sandbox-template-tag.sh', '.github/scripts/sandbox-image-exists.sh', 'server/app.ex',
    'infra/certificate-trust/policy.json', 'infra/certificate-trust/pem-store.sh']) {
    const result = spawnSync('grep', ['-E', filter], { input: `${path}\n`, encoding: 'utf8' });
    assert.equal(result.status, 0, `${path} must trigger deployment`);
  }
  assert.equal(spawnSync('grep', ['-E', filter], { input: 'cli/README.md\n' }).status, 1);
});

test('publisher reuses existing images and builds only on a manifest-not-found response', (t) => {
  const dir = fixture(t);
  writeFileSync(join(dir, 'docker'), '#!/bin/sh\nprintf "%s" "$DOCKER_ERROR" >&2\nexit "$DOCKER_STATUS"\n', { mode: 0o755 });
  for (const [status, error, expected] of [
    ['0', '', 'true'],
    ['1', `ERROR: ${image}:sha-aaaaaaaaaaaa: not found`, 'false'],
    ['1', 'manifest unknown', 'false'],
    ['1', 'unauthorized: authentication required', null],
    ['1', 'dial tcp: network is unreachable', null],
    ['1', 'unexpected status: 503 Service Unavailable', null],
  ]) {
    const result = spawnSync('bash', [join(scripts, 'sandbox-image-exists.sh'), `${image}:sha-aaaaaaaaaaaa`], {
      env: { ...env, PATH: `${dir}:${env.PATH}`, DOCKER_ERROR: error, DOCKER_STATUS: status },
      encoding: 'utf8',
    });
    if (expected === null) {
      assert.notEqual(result.status, 0, error);
      assert.equal(result.stdout, '');
    } else {
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout.trim(), expected);
    }
  }
});

function workflow(name) {
  const result = spawnSync('yq', ['-o=json', '.', join(scripts, '../workflows', name)], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return JSON.parse(result.stdout);
}

test('all production legs require publication and promote the same template', () => {
  const jobs = workflow('server-production-deployment.yml').jobs;
  assert.equal(jobs['build-sandbox-template'].uses, './.github/workflows/sandbox-image.yml');
  assert.equal(jobs['build-sandbox-template'].if, jobs.build.if);
  for (const name of ['canary', 'production', 'production-hotfix']) {
    assert.ok(jobs[name].needs.includes('build-sandbox-template'), name);
    assert.match(jobs[name].if, /needs\.build-sandbox-template\.result == 'success'/, name);
    assert.equal(jobs[name].with.sandbox_template_image_tag, '${{ needs.build-sandbox-template.outputs.image_tag }}', name);
  }
  assert.ok(jobs.production.needs.includes('canary'));
  assert.ok(jobs.production.needs.includes('acceptance-tests'));
  const deploy = workflow('server-deployment.yml');
  assert.ok(deploy.on.workflow_dispatch.inputs.sandbox_template_image_tag);
  assert.ok(deploy.on.workflow_call.inputs.sandbox_template_image_tag);
  assert.match(deploy.jobs['build-sandbox-template'].if, /inputs\.image_tag == ''/);
  assert.match(deploy.jobs['build-sandbox-template'].if, /inputs\.sandbox_template_image_tag == ''/);
  assert.ok(deploy.jobs.deploy.needs.includes('build-sandbox-template'));
  assert.match(deploy.jobs.deploy.if, /needs\.build-sandbox-template\.result == 'success'/);
});

test('PR builds cannot publish; reusable publisher returns the built version', () => {
  const publisher = workflow('sandbox-image.yml');
  assert.equal(publisher.permissions.packages, 'read');
  assert.equal(publisher.jobs.test.permissions, undefined);
  assert.equal(publisher.jobs.build.if, "github.event_name != 'pull_request'");
  assert.equal(publisher.jobs.build.permissions.packages, 'write');
  assert.equal(publisher.jobs.build.needs, 'test');
  assert.equal(publisher.on.workflow_call.outputs.image_tag.value, '${{ jobs.build.outputs.image_tag }}');
  const build = publisher.jobs.build.steps.find((s) => s.uses === 'docker/build-push-action@v6');
  assert.equal(build.if, "steps.existing.outputs.exists != 'true'");
  assert.equal(build.with.tags, '${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ steps.version.outputs.image_tag }}');
});

for (const environment of ['staging', 'canary', 'production', 'disabled']) {
  test(`deployment selects the template correctly in the ${environment} chart`, (t) => {
    const dir = fixture(t);
    const rendered = join(dir, 'render.yaml');
    const overlay = environment === 'disabled' ? 'staging' : environment;
    const chart = join(root, 'infra/helm/tuist');
    const args = ['template', 'custom', chart, '--namespace', `tuist-${overlay}`,
      '-f', `${chart}/values-managed-common.yaml`, '-f', `${chart}/values-managed-${overlay}.yaml`,
      '-f', `${chart}/values-ci.yaml`];
    if (environment === 'disabled') args.push('--set', 'sandboxes.enabled=false', '--set', 'ampOrbProvider.enabled=false');
    const initial = spawnSync('helm', args, { encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
    assert.equal(initial.status, 0, initial.stderr);
    writeFileSync(rendered, initial.stdout);
    const deploy = workflow('server-deployment.yml').jobs.deploy;
    const shell = deploy.steps.find((s) => s.name === 'helm upgrade --install').run;
    // Execute the workflow's actual selector and tag helper against Helm output.
    const selector = shell.slice(shell.indexOf('sandbox_namespace='), shell.indexOf('rm -f "$registry_render"'));
    assert.ok(selector.length > 0);
    const selected = spawnSync('bash', ['-euc', 'add_set() { printf "%s=%s\\n" "$1" "$2"; }\n' + selector], {
      cwd: root,
      env: { ...env, registry_render: rendered, SANDBOX_TEMPLATE_IMAGE_TAG: 'sha-abcdef012345' },
      encoding: 'utf8',
    });
    assert.equal(selected.status, 0, selected.stderr);
    if (environment === 'disabled') {
      assert.equal(selected.stdout, '');
      return;
    }
    assert.equal(selected.stdout.trim(), 'sandboxes.templateImage.tag=sha-abcdef012345');
    const updated = spawnSync('helm', [...args, '--set-string', selected.stdout.trim(), '--show-only', 'templates/sandboxes.yaml'], {
      encoding: 'utf8',
    });
    assert.equal(updated.status, 0, updated.stderr);
    assert.match(updated.stdout, /image: "ghcr.io\/tuist\/tuist-sandbox-template:sha-abcdef012345"/);
    // Both the init container and sandboxd must select the installed version.
    assert.equal((updated.stdout.match(/name: TEMPLATE_TAG\s+value: "sha-abcdef012345"/g) || []).length, 2);
  });
}
