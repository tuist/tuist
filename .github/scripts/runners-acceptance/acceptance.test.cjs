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

for (const [environment, label, count] of [['canary', 'tuist-canary-linux', 4], ['production', 'tuist-linux', 3]]) {
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

const successfulJobs = [
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
        ENVIRONMENT: 'canary', EXPECTED_PROBE_JOBS: '4', MACOS_PICKUP_MINUTES: '15', LINUX_PICKUP_MINUTES: '10' },
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
for (const prefix of ['Linux native ', 'Linux container ']) {
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
test('watchdog accepts all four started probes', () => {
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
