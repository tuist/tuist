const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const yaml = require('js-yaml');

const root = path.resolve(__dirname, '../../..');
const workflow = yaml.load(fs.readFileSync(path.join(root, '.github/workflows/runners-acceptance.yml'), 'utf8'));
const cascade = yaml.load(fs.readFileSync(path.join(root, '.github/workflows/server-production-deployment.yml'), 'utf8'));
const deployment = yaml.load(fs.readFileSync(path.join(root, '.github/workflows/server-deployment.yml'), 'utf8'));

test('Linux staging waits and fails closed in canary; other environments preserve background holds', () => {
  const deploy = deployment.jobs.deploy;
  const helm = deploy.steps.find(step => step.name === 'helm upgrade --install');
  assert.equal(deploy['timeout-minutes'], 125);
  assert.equal(helm['timeout-minutes'], 70);
  assert.match(helm.run, /if ! bash \.github\/scripts\/linux-runner-image-prepare\.sh "\$kvm_render" "\$HELM_RELEASE_NAME" "\$NAMESPACE"/);
  assert.match(helm.run, /::warning::Could not check Linux image staging/);
  assert.match(helm.run, /echo '\{"runnersFleetLinux":\{"imageHolds":\{\}\}\}' > "\$linux_staging_values"/);
  assert.match(helm.run, /helm_values_args\+=\(-f "\$linux_staging_values"\)/);
  assert.match(helm.run, /export LINUX_IMAGE_STAGING_WAIT_SECONDS=0\s+if \[ "\$TARGET_ENVIRONMENT" = "canary" \]; then\s+export LINUX_IMAGE_STAGING_WAIT_SECONDS=300/);
  assert.match(helm.run, /if ! bash \.github\/scripts\/linux-runner-image-prepare[^\n]+; then\s+if \[ "\$TARGET_ENVIRONMENT" = "canary" \]; then\s+echo '[^']+'\s+exit 1/);
});

for (const environment of ['canary', 'production']) {
  for (const failure of [false, true]) {
    test(`${environment} image preparation handles failure=${failure}`, () => {
      const work = fs.mkdtempSync(path.join(os.tmpdir(), 'image-prepare-caller-'));
      try {
        fs.mkdirSync(path.join(work, '.github/scripts'), { recursive: true });
        fs.writeFileSync(path.join(work, '.github/scripts/linux-runner-image-prepare.sh'),
          `echo "$LINUX_IMAGE_STAGING_WAIT_SECONDS" > "$TEST_MODE"\n${failure ? 'exit 1' : `echo '{"runnersFleetLinux":{"imageHolds":{}}}'`}\n`);
        const helm = deployment.jobs.deploy.steps.find(step => step.id === 'deploy-chart').run;
        const start = helm.indexOf('if [ -f .github/scripts/linux-runner-image-prepare.sh ]; then');
        const end = helm.indexOf('rm -f "$kvm_render"', start);
        assert.ok(start >= 0 && end > start);
        const result = spawnSync('bash', ['-c', `set -euo pipefail\nhelm_values_args=()\n${helm.slice(start, end)}\ncat "$linux_staging_values"`], {
          cwd: work, encoding: 'utf8', env: { ...process.env, TARGET_ENVIRONMENT: environment, TEST_MODE: path.join(work, 'mode'),
            TMPDIR: work, kvm_render: 'unused', HELM_RELEASE_NAME: 'tuist', NAMESPACE: 'canary' },
        });
        assert.equal(fs.readFileSync(path.join(work, 'mode'), 'utf8').trim(), environment === 'canary' ? '300' : '0');
        assert.equal(result.status !== 0, failure && environment === 'canary');
        if (failure && environment === 'canary') assert.match(result.stdout, /stopping before the Helm upgrade/);
        else assert.match(result.stdout, /"imageHolds":\{\}/);
      } finally {
        fs.rmSync(work, { recursive: true, force: true });
      }
    });
  }
}

for (const [environment, label, count] of [['canary', 'tuist-canary-linux', 9], ['production', 'tuist-linux', 3]]) {
  test(`${environment} plans native and container Linux probes in the watchdog count`, () => {
    const work = fs.mkdtempSync(path.join(os.tmpdir(), 'runner-plan-'));
    try {
      const output = path.join(work, 'output');
      execFileSync('bash', ['-c', workflow.jobs.plan.steps[0].run], {
        env: { ...process.env, ENVIRONMENT: environment, GITHUB_OUTPUT: output },
      });
      const values = Object.fromEntries(fs.readFileSync(output, 'utf8').trim().split('\n').map(line => {
        const split = line.indexOf('=');
        return [line.slice(0, split), line.slice(split + 1)];
      }));
      assert.equal(JSON.parse(values.linux)[0].label, label);
      assert.equal(Number(values.probe_jobs), count);
      for (const [id, prefix] of [['linux', 'Linux native '], ['linux-container', 'Linux container ']]) {
        const job = workflow.jobs[id];
        assert.ok(job.name.startsWith(prefix));
        assert.deepEqual(job.needs, 'plan');
        assert.equal(job.strategy.matrix.target, '${{ fromJSON(needs.plan.outputs.linux) }}');
        assert.equal(job['runs-on'], '${{ matrix.target.label }}');
        assert.equal(job.if, undefined, 'required Linux coverage cannot silently skip');
        assert.notEqual(job['continue-on-error'], true);
      }
      assert.ok(workflow.jobs['linux-container'].container.image.startsWith('ubuntu:22.04@sha256:'));
    } finally {
      fs.rmSync(work, { recursive: true, force: true });
    }
  });
}

test('production promotion requires canary runners acceptance', () => {
  assert.ok(cascade.jobs['runners-acceptance'].needs.includes('canary'));
  assert.ok(cascade.jobs.production.needs.includes('runners-acceptance'));
  assert.match(cascade.jobs.production.if, /needs\.runners-acceptance\.result == 'success'/);
  const step = cascade.jobs['runners-acceptance'].steps.find(step => step.run?.includes('runners-acceptance/gate.sh'));
  assert.equal(step.env.ENVIRONMENT, 'canary');
});

const dockerPhases = ['cold', 'warm-layers', 'changed-source', 'same-size-write', 'verify-final'];
const successfulJobs = [
  ...dockerPhases.map(phase => ({ name: `Linux Docker cache ${phase} / Build`, conclusion: 'success' })),
  { name: 'macOS rack (canary)', conclusion: 'success' },
  { name: 'macOS cache volumes (canary)', conclusion: 'success' },
  { name: 'Linux native default (canary)', conclusion: 'success' },
  { name: 'Linux container default (canary)', conclusion: 'success' },
].map((job, index) => ({ ...job, id: index + 1, status: 'completed', labels: ['canary'],
  created_at: '2026-01-01T00:00:00Z', started_at: '2026-01-01T00:00:01Z' }));

function runScript(script, jobs, conclusion = 'success') {
  const work = fs.mkdtempSync(path.join(os.tmpdir(), 'runner-gate-'));
  try {
    fs.writeFileSync(path.join(work, 'jobs.json'), JSON.stringify({ jobs }));
    fs.writeFileSync(path.join(work, 'gh'), `#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'workflow run '*) ;;
  'run list '*) echo 42 ;;
  *'--jq .status') echo completed ;;
  *'--jq .conclusion') echo "$TEST_CONCLUSION" ;;
  'run cancel '*) touch "$TEST_WORK/cancelled" ;;
  *check-runs*) ;;
  api*) cat "$TEST_WORK/jobs.json" ;;
  *) echo "Unexpected gh call: $*" >&2; exit 1 ;;
esac
`, { mode: 0o755 });
    const result = spawnSync('bash', [path.join(__dirname, script)], {
      encoding: 'utf8', timeout: 5000,
      env: { ...process.env, PATH: `${work}:${process.env.PATH}`, TEST_WORK: work,
        TEST_CONCLUSION: conclusion, GITHUB_REPOSITORY: 'tuist/tuist',
        GITHUB_RUN_ID: '42', GITHUB_RUN_ATTEMPT: '1', GITHUB_STEP_SUMMARY: path.join(work, 'summary'),
        DOCKER_CACHE_PROBES: 'true', ENVIRONMENT: 'canary', EXPECTED_LINUX_IMAGE: 'ghcr.io/tuist/tuist-linux-runner@sha256:' + 'a'.repeat(64), EXPECTED_PROBE_JOBS: '9', MACOS_PICKUP_MINUTES: '15', LINUX_PICKUP_MINUTES: '10' },
    });
    assert.equal(result.error, undefined, result.error?.message);
    return { ...result, cancelled: fs.existsSync(path.join(work, 'cancelled')) };
  } finally {
    fs.rmSync(work, { recursive: true, force: true });
  }
}

test('gate accepts a complete successful run', () => {
  assert.equal(runScript('gate.sh', successfulJobs).status, 0);
});
for (const prefix of ['Linux native ', 'Linux container ', ...dockerPhases.map(phase => `Linux Docker cache ${phase} / Build`)]) {
  for (const state of ['missing', 'skipped', 'failure']) {
    test(`gate rejects ${state} ${prefix.trim()} even with a successful aggregate conclusion`, () => {
      const jobs = state === 'missing'
        ? successfulJobs.filter(job => !job.name.startsWith(prefix))
        : successfulJobs.map(job => job.name.startsWith(prefix) ? { ...job, conclusion: state } : job);
      const result = runScript('gate.sh', jobs);
      assert.notEqual(result.status, 0);
      assert.match(result.stdout, /Linux acceptance/);
    });
  }
}
test('gate preserves aggregate workflow failures', () => {
  assert.notEqual(runScript('gate.sh', successfulJobs, 'failure').status, 0);
});
test('watchdog accepts all nine started probes', () => {
  const result = runScript('dispatch-watchdog.sh', successfulJobs);
  assert.equal(result.status, 0);
  assert.equal(result.cancelled, false);
});
test('watchdog fails and cancels when only the Linux container probe never starts', () => {
  const jobs = successfulJobs.map(job => job.name.startsWith('Linux container ')
    ? { ...job, status: 'queued', conclusion: null, started_at: null } : job);
  const result = runScript('dispatch-watchdog.sh', jobs);
  assert.notEqual(result.status, 0);
  assert.equal(result.cancelled, true);
  assert.match(result.stdout, /Linux container/);
});

test('Docker phases are sequential, canary-only, and use one immutable workflow revision', () => {
  let previous = 'linux-container';
  for (const phase of dockerPhases) {
    const job = workflow.jobs[`docker-${phase}`];
    assert.equal(job.name, `Linux Docker cache ${phase}`);
    assert.ok(job.needs.includes(previous));
    assert.equal(job.if, "inputs.environment == 'canary'");
    assert.equal(job.uses, './.github/workflows/runners-docker-cache-probe.yml');
    assert.equal(job.with.phase, phase);
    assert.equal(job.with.expected_linux_image, '${{ inputs.expected_linux_image }}');
    assert.notEqual(job['continue-on-error'], true);
    previous = `docker-${phase}`;
  }
  assert.ok(workflow.jobs['docker-cold'].needs.includes('linux'));
  assert.equal(workflow.concurrency['cancel-in-progress'], false);
});

test('candidate digest flows from the intended deploy image through the gate', () => {
  assert.equal(deployment.on.workflow_call.outputs.linux_runner_image.value, '${{ jobs.deploy.outputs.linux_runner_image }}');
  assert.equal(deployment.jobs.deploy.outputs.linux_runner_image, '${{ steps.deploy-chart.outputs.linux_runner_image }}');
  const helm = deployment.jobs.deploy.steps.find(step => step.id === 'deploy-chart');
  assert.match(helm.run, /echo "linux_runner_image=ghcr.io\/tuist\/tuist-linux-runner@\$\{linux_runner_image_digest\}" >> "\$GITHUB_OUTPUT"/);
  const gate = cascade.jobs['runners-acceptance'].steps.find(step => step.run?.endsWith('gate.sh'));
  assert.equal(gate.env.EXPECTED_LINUX_IMAGE, '${{ needs.canary.outputs.linux_runner_image }}');
});

test('publication windows cannot make the watchdog finish before cache probes appear', () => {
  const windows = dockerPhases.map(phase => ({ ...successfulJobs[0], name: `Linux Docker cache ${phase} / Publication window` }));
  // Including windows alongside a queued real probe must still fail dispatch.
  const jobs = [...successfulJobs.map(job => job.name === 'Linux Docker cache verify-final / Build'
    ? { ...job, status: 'queued', conclusion: null, started_at: null } : job), ...windows];
  const result = runScript('dispatch-watchdog.sh', jobs);
  assert.notEqual(result.status, 0);
  assert.equal(result.cancelled, true);
  assert.match(result.stdout, /verify-final/);
});

test('canary enables only the acceptance pool; production remains disabled', () => {
  const values = file => yaml.load(fs.readFileSync(path.join(root, 'infra/helm/tuist', file), 'utf8'));
  const canary = values('values-managed-canary.yaml').runnersFleetLinux.cacheVolumes;
  assert.equal(canary.enabled, true);
  assert.equal(canary.dockerCache.enabled, true);
  assert.deepEqual(canary.dockerCache.pools, ['tuist-tuist-runner-pool-linux-2vcpu-8gb']);
  assert.equal(values('values-managed-production.yaml').runnersFleetLinux.cacheVolumes.dockerCache.enabled, false);
});

test('probe rejects an older candidate image before any build', () => {
  const probe = yaml.load(fs.readFileSync(path.join(root, '.github/workflows/runners-docker-cache-probe.yml'), 'utf8'));
  const check = probe.jobs.build.steps.find(step => step.name === 'Require candidate runner and mounted cache');
  const result = spawnSync('bash', ['-c', check.run], {
    encoding: 'utf8', env: { ...process.env, EXPECTED_LINUX_IMAGE: 'candidate@sha256:new', TUIST_RUNNER_IMAGE: 'candidate@sha256:old' },
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stdout, /Acceptance ran on candidate@sha256:old, expected candidate@sha256:new/);
});

const productionQualification = yaml.load(fs.readFileSync(path.join(root, '.github/workflows/runners-docker-cache-production.yml'), 'utf8'));

test('production qualification is manual and stops the five-phase chain on failure', () => {
  assert.deepEqual(Object.keys(productionQualification.on), ['workflow_dispatch']);
  assert.deepEqual(productionQualification.permissions, { contents: 'read' });
  assert.equal(productionQualification.concurrency['cancel-in-progress'], false);
  let previous = 'validate';
  for (const phase of dockerPhases) {
    const job = productionQualification.jobs[phase];
    assert.ok([job.needs].flat().includes(previous));
    assert.ok([job.needs].flat().includes('validate'));
    assert.equal(job.uses, './.github/workflows/runners-docker-cache-probe.yml');
    assert.equal(job.with.phase, phase);
    assert.equal(job.with.runner_label, '${{ inputs.runner_label }}');
    assert.equal(job.with.expected_linux_image, '${{ inputs.expected_linux_image }}');
    assert.equal(job.with.environment_name, 'production');
    assert.equal(job.if, undefined); // Default success dependency; never always().
    assert.notEqual(job['continue-on-error'], true);
    previous = phase;
  }
});

const productionInputs = {
  REPOSITORY: 'tuist/tuist', SOURCE_REF: 'refs/heads/main', DEFAULT_BRANCH: 'main',
  RUN_ATTEMPT: '1', RUNNER_LABEL: 'tuist-linux-large',
  EXPECTED_LINUX_IMAGE: `ghcr.io/tuist/tuist-linux-runner@sha256:${'a'.repeat(64)}`,
};
for (const [name, overrides, succeeds] of [
  ['qualified production input', {}, true],
  ['default production profile', { RUNNER_LABEL: 'tuist-linux' }, true],
  ['canary profile', { RUNNER_LABEL: 'tuist-canary-linux' }, false],
  ['empty profile', { RUNNER_LABEL: '' }, false],
  ['runner expression injection', { RUNNER_LABEL: 'tuist-linux; exit 0' }, false],
  ['mutable image tag', { EXPECTED_LINUX_IMAGE: 'ghcr.io/tuist/tuist-linux-runner:latest' }, false],
  ['empty image', { EXPECTED_LINUX_IMAGE: '' }, false],
  ['other image repository', { EXPECTED_LINUX_IMAGE: `ghcr.io/other/runner@sha256:${'a'.repeat(64)}` }, false],
  ['untrusted branch', { SOURCE_REF: 'refs/heads/experiment' }, false],
  ['tag', { SOURCE_REF: 'refs/tags/main' }, false],
  ['fork repository', { REPOSITORY: 'fork/tuist' }, false],
  ['rerun', { RUN_ATTEMPT: '2' }, false],
]) {
  test(`production preflight: ${name}`, () => {
    const result = spawnSync('bash', ['-c', productionQualification.jobs.validate.steps[0].run], {
      encoding: 'utf8', env: { ...process.env, ...productionInputs, ...overrides },
    });
    assert.equal(result.status === 0, succeeds, result.stderr);
  });
}

test('partial production rerun fails even when the original validation job is not rerun', () => {
  const probe = yaml.load(fs.readFileSync(path.join(root, '.github/workflows/runners-docker-cache-probe.yml'), 'utf8'));
  const check = probe.jobs.build.steps.find(step => step.name === 'Require candidate runner and mounted cache');
  const result = spawnSync('bash', ['-c', check.run], {
    encoding: 'utf8', env: { ...process.env, EXPECTED_LINUX_IMAGE: productionInputs.EXPECTED_LINUX_IMAGE,
      QUALIFICATION_ENVIRONMENT: 'production', GITHUB_RUN_ATTEMPT: '2' },
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stdout, /Start a fresh qualification run/);
});

test('reusable probe preserves canary defaults and pins checkout to the dispatch commit', () => {
  const probe = yaml.load(fs.readFileSync(path.join(root, '.github/workflows/runners-docker-cache-probe.yml'), 'utf8'));
  assert.equal(probe.on.workflow_call.inputs.runner_label.default, 'tuist-canary-linux');
  assert.equal(probe.on.workflow_call.inputs.environment_name.default, 'canary');
  assert.equal(probe.jobs.build['runs-on'], '${{ inputs.runner_label }}');
  assert.equal(probe.jobs.build.steps.find(step => step.uses === 'actions/checkout@v4').with.ref, '${{ github.sha }}');
});

for (const mounted of [true, false]) {
  test(`candidate probe requires a real mount: mounted=${mounted}`, () => {
    const work = fs.mkdtempSync(path.join(os.tmpdir(), 'docker-probe-'));
    try {
      const probe = yaml.load(fs.readFileSync(path.join(root, '.github/workflows/runners-docker-cache-probe.yml'), 'utf8'));
      const check = probe.jobs.build.steps.find(step => step.name === 'Require candidate runner and mounted cache');
      const state = path.join(work, 'state.json');
      fs.writeFileSync(state, JSON.stringify({ mounted, reason: 'denied', token: 'must-not-log' }));
      const result = spawnSync('bash', ['-c', check.run.replaceAll('/home/runner/.tuist-docker.json', state)], {
        encoding: 'utf8', env: { ...process.env, EXPECTED_LINUX_IMAGE: 'candidate', TUIST_RUNNER_IMAGE: 'candidate', GITHUB_STEP_SUMMARY: path.join(work, 'summary') },
      });
      assert.equal(result.status === 0, mounted);
      if (!mounted) {
        assert.match(result.stdout, /Docker cache is not mounted/);
        assert.match(result.stdout, /denied/);
      }
      assert.doesNotMatch(result.stdout, /must-not-log/);
    } finally {
      fs.rmSync(work, { recursive: true, force: true });
    }
  });
}
