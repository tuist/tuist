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

test('Linux staging is warning-only and supplies per-pool holds without extending deploy timeouts', () => {
  const deploy = deployment.jobs.deploy;
  const helm = deploy.steps.find(step => step.name === 'helm upgrade --install');
  assert.equal(deploy['timeout-minutes'], 125);
  assert.equal(helm['timeout-minutes'], 70);
  assert.match(helm.run, /if ! bash \.github\/scripts\/linux-runner-image-prepare\.sh "\$kvm_render" "\$HELM_RELEASE_NAME" "\$NAMESPACE"/);
  assert.match(helm.run, /::warning::Could not check Linux image staging/);
  assert.match(helm.run, /echo '\{"runnersFleetLinux":\{"imageHolds":\{\}\}\}' > "\$linux_staging_values"/);
  assert.match(helm.run, /helm_values_args\+=\(-f "\$linux_staging_values"\)/);
});

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
