import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const hook = fileURLToPath(new URL('./hooks/spawn-runner', import.meta.url));

async function spawnRunner(overrides = {}, status = 202) {
  const requests = [];
  const server = createServer(async (request, response) => {
    let body = '';
    for await (const chunk of request) body += chunk;
    requests.push({ path: request.url, auth: request.headers.authorization, body: JSON.parse(body) });
    response.writeHead(status).end('private-response-body');
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const scratch = await mkdtemp(join(tmpdir(), 'spawn-runner-'));
  try {
    await writeFile(join(scratch, 'identity'), 'workload-secret');
    await writeFile(join(scratch, 'order'), 'work.order.jwt\n');
    const child = spawn('bash', [hook], { env: {
      PATH: process.env.PATH,
      TUIST_URL: `http://127.0.0.1:${server.address().port}`,
      TUIST_WORKLOAD_TOKEN_FILE: join(scratch, 'identity'),
      CLAUDE_RUNNER_WORK_ORDER_FILE: join(scratch, 'order'),
      CLAUDE_RUNNER_ORDER_ID: 'order-1',
      CLAUDE_RUNNER_SESSION_ID: 'session_01abc',
      CLAUDE_RUNNER_ACCOUNT_EMAIL: 'dev@example.com',
      ...overrides,
    } });
    let output = '';
    child.stdout.on('data', data => output += data);
    child.stderr.on('data', data => output += data);
    const code = await new Promise(resolve => child.on('close', resolve));
    for (const secret of ['workload-secret', 'work.order.jwt', 'private-response-body', 'dev@example.com']) {
      assert(!output.includes(secret), `the hook printed ${secret}`);
    }
    return { code, output, requests };
  } finally {
    await rm(scratch, { recursive: true, force: true });
    await new Promise(resolve => server.close(resolve));
  }
}

test('hands the work order to Tuist with the workload identity and nothing else', async () => {
  const { code, requests } = await spawnRunner();
  assert.equal(code, 0);
  assert.deepEqual(requests, [{
    path: '/api/internal/claude-code-runners/spawn',
    auth: 'Bearer workload-secret',
    body: { order_id: 'order-1', session_id: 'session_01abc', work_order: 'work.order.jwt' },
  }]);
});

test('names the session\'s primary repository when there is one', async () => {
  const { code, requests } = await spawnRunner({ CLAUDE_RUNNER_PRIMARY_REPO_URL: 'https://github.com/tuist/tuist' });
  assert.equal(code, 0);
  assert.deepEqual(requests[0].body, {
    order_id: 'order-1', session_id: 'session_01abc', work_order: 'work.order.jwt',
    repository_url: 'https://github.com/tuist/tuist',
  });
});

test('a standby request without a session starts nothing', async () => {
  const { code, requests } = await spawnRunner({ CLAUDE_RUNNER_SESSION_ID: '' });
  assert.equal(code, 0);
  assert.deepEqual(requests, []);
});

test('capacity and transient answers are retryable, refusals block the session', async () => {
  for (const [status, expected] of [[204, 0], [429, 1], [503, 1], [500, 1], [401, 1], [403, 2], [422, 2]]) {
    const { code } = await spawnRunner({}, status);
    assert.equal(code, expected, `HTTP ${status}`);
  }
});

test('an unreachable Tuist is retryable', async () => {
  const { code } = await spawnRunner({ TUIST_URL: 'http://127.0.0.1:9' });
  assert.equal(code, 1);
});
