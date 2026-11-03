import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const script = fileURLToPath(new URL('./dispatch.sh', import.meta.url));

async function dispatch(overrides = {}, status = 204, executable = script) {
  const requests = [];
  const server = createServer(async (request, response) => {
    let body = '';
    for await (const chunk of request) body += chunk;
    requests.push({ path: request.url, auth: request.headers.authorization, body: JSON.parse(body) });
    if (request.url.endsWith('/exec')) {
      response.writeHead(200, { 'content-type': 'application/json' }).end('{"exit_code":0}');
    } else {
      const result = typeof status === 'function' ? await status(requests.length) : { status };
      if (result.disconnect) {
        request.socket.destroy();
        return;
      }
      response.writeHead(result.status, result.headers).end(result.body ?? 'private-response-body');
    }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const child = spawn('bash', [executable], { env: {
      PATH: process.env.PATH,
      TUIST_URL: `http://127.0.0.1:${server.address().port}`,
      TUIST_ACCOUNT: 'test-team', TUIST_TOKEN: 'api-secret',
      ORB_ID: 'amp-thread', ORB_OPERATION: 'spawn', ORB_TOKEN: 'orb-secret',
      ORB_IMAGE: 'default', ...overrides,
    } });
    let output = '';
    child.stdout.on('data', data => output += data);
    child.stderr.on('data', data => output += data);
    const code = await new Promise(resolve => child.on('close', resolve));
    assert(!output.includes('orb-secret') && !output.includes('api-secret') && !output.includes('private-response-body'));
    return { code, output, requests };
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

test('spawn translates the contract without forwarding provider credentials', async () => {
  const { code, requests } = await dispatch({ AMP_URL: 'https://amp.example.com', ORB_SNAPSHOT_ID: 'snapshot-id', AMP_ORB_PROVIDER_TOKEN: 'provider-secret' });
  assert.equal(code, 0);
  assert.deepEqual(requests, [{
    path: '/api/accounts/test-team/sandboxes/amp-orbs/amp-thread', auth: 'Bearer api-secret',
    body: { operation: 'spawn', snapshot_id: 'snapshot-id', orb_token: 'orb-secret', template: 'default', vcpus: 2, memory_mb: 4096, workspace_gb: 10, amp_url: 'https://amp.example.com' },
  }]);
});

test('pause and delete require no per-Orb token or image', async () => {
  for (const operation of ['pause', 'delete']) {
    const { code, requests } = await dispatch({ ORB_OPERATION: operation, ORB_TOKEN: '', ORB_IMAGE: '' });
    assert.equal(code, 0);
    assert.deepEqual(requests[0].body, { operation });
  }
});

test('pause forwards the project snapshot to save; delete never does', async () => {
  const pause = await dispatch({ ORB_OPERATION: 'pause', ORB_TOKEN: '', ORB_IMAGE: '', ORB_SNAPSHOT_ID: 'proj_01:a.b-c' });
  assert.equal(pause.code, 0);
  assert.deepEqual(pause.requests[0].body, { operation: 'pause', snapshot_id: 'proj_01:a.b-c' });
  const remove = await dispatch({ ORB_OPERATION: 'delete', ORB_TOKEN: '', ORB_IMAGE: '', ORB_SNAPSHOT_ID: 'snapshot-id' });
  assert.equal(remove.code, 0);
  assert.deepEqual(remove.requests[0].body, { operation: 'delete' });
});

test('live observer works without inheriting any provider AMP_* variables', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'tuist-orb-observer-'));
  const sandbox = '12345678-1234-1234-1234-123456789abc';
  try {
    await writeFile(join(directory, 'state.json'), JSON.stringify({
      sandboxes: [{ id: sandbox, amp_orb_id: 'amp-thread' }],
    }));
    const liveScript = fileURLToPath(new URL('./live-dispatch.sh', import.meta.url));
    const { code, output, requests } = await dispatch({ TUIST_ORB_VALIDATION_DIR: directory }, 204, liveScript);
    assert.equal(code, 0, output);
    assert.equal(requests.length, 2);
    assert.equal(requests[0].body.operation, 'spawn');
    assert.equal(requests[1].path, `/api/accounts/test-team/sandboxes/${sandbox}/exec`);
    assert.equal(requests[1].auth, 'Bearer api-secret');
    assert.equal(requests[1].body.timeout_ms, 15000);
    assert.deepEqual(JSON.parse(await readFile(join(directory, 'spawns.jsonl'), 'utf8')), {
      orb: 'amp-thread', sandbox,
    });
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('refuses unsafe path components, missing tokens, unsupported images and unknown operations before HTTP', async () => {
  for (const overrides of [{ ORB_ID: '../other' }, { TUIST_ACCOUNT: 'a/b' }, { ORB_TOKEN: '' }, { ORB_IMAGE: 'arbitrary:latest' }, { ORB_OPERATION: 'unknown' }, { ORB_SNAPSHOT_ID: '../other' }]) {
    const { code, requests } = await dispatch(overrides);
    assert.notEqual(code, 0);
    assert.equal(requests.length, 0);
  }
});

test('does not retry unmarked HTTP errors or log private response bodies', async () => {
  for (const status of [400, 401, 403, 409, 429, 500, 502, 503]) {
    const { code, output, requests } = await dispatch({}, status);
    assert.notEqual(code, 0);
    assert.match(output, new RegExp(`HTTP ${status}`));
    assert.equal(requests.length, 1);
  }
});

test('explains the account on-node Orb limit without retrying', async () => {
  const { code, output, requests } = await dispatch({}, () => ({ status: 429, headers: { 'X-Tuist-Orb-Refusal': 'sandbox-limit' } }));
  assert.notEqual(code, 0);
  assert.equal(requests.length, 1);
  assert.match(output, /limit of Orbs kept on sandbox nodes/);
  assert.match(output, /paused Orbs count/);
  assert.doesNotMatch(output, /private-response-body/);
});

test('supports an explicitly installed template and allowed shape', async () => {
  const { code, requests } = await dispatch({ ORB_IMAGE: 'amp', TUIST_ORB_TEMPLATE: 'amp', TUIST_ORB_VCPUS: '4', TUIST_ORB_MEMORY_MB: '8192', TUIST_ORB_WORKSPACE_GB: '30' });
  assert.equal(code, 0);
  assert.equal(requests[0].body.template, 'amp');
  assert.equal(requests[0].body.memory_mb, 8192);
  assert.equal(requests[0].body.workspace_gb, 30);
});

test('resolves a refreshable Tuist user token for each job when no fixed token is supplied', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'tuist-orb-auth-'));
  try {
    await writeFile(join(directory, 'tuist'), '#!/bin/sh\n[ "$1 $2 $3" = "auth token --url" ] || exit 1\necho api-secret\n', { mode: 0o755 });
    const { code, requests } = await dispatch({ TUIST_TOKEN: '', PATH: `${directory}:${process.env.PATH}` });
    assert.equal(code, 0);
    assert.equal(requests[0].auth, 'Bearer api-secret');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('managed dispatch rereads the rotated workload token and ignores a requested account', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'tuist-orb-identity-'));
  const identity = join(directory, 'token');
  try {
    for (const token of ['identity-one', 'identity-two']) {
      await writeFile(identity, token);
      const { code, requests, output } = await dispatch({ TUIST_WORKLOAD_TOKEN_FILE: identity, TUIST_ACCOUNT: 'another-account' });
      assert.equal(code, 0, output);
      assert.equal(requests[0].auth, `Bearer ${token}`);
      assert.equal(requests[0].path, '/api/internal/amp-orbs/amp-thread');
      assert(!JSON.stringify(requests[0].body).includes(token));
      assert(!output.includes(token));
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
});

const admission = status => ({ status, headers: { 'X-Tuist-Orb-Retry': 'admission' } });

test('never retries an ambiguous transport failure', async () => {
  const { code, output, requests } = await dispatch({}, () => ({ disconnect: true }));
  assert.notEqual(code, 0);
  assert.equal(requests.length, 1);
  assert(!output.includes('Waiting for sandbox capacity'));
});

test('does not reuse a retry hint from a previous HTTP response', async () => {
  const { code, output, requests } = await dispatch({}, attempt => attempt === 1 ? admission(503) : { status: 503 });
  assert.equal(code, 1);
  assert.equal(requests.length, 2);
  assert.match(output, /failed \(HTTP 503\)/);
});

test('retries explicit admission refusals with the same Orb identity and body', async () => {
  for (const status of [409, 429, 503]) {
    const { code, output, requests } = await dispatch({}, attempt => attempt === 1 ? admission(status) : { status: 204 });
    assert.equal(code, 0, output);
    assert.equal(requests.length, 2);
    assert.deepEqual(requests[0], requests[1]);
    assert.match(output, /Waiting for sandbox capacity/);
  }
});

test('stops at the admission deadline instead of making another request', async () => {
  const { code, output, requests } = await dispatch({ TUIST_ORB_CAPACITY_WAIT_SECONDS: '2' }, () => admission(503));
  assert.equal(code, 1);
  assert.equal(requests.length, 1);
  assert.match(output, /Timed out waiting for sandbox capacity/);
});

test('HTTP time counts against the wait deadline', async () => {
  const { code, output, requests } = await dispatch({ TUIST_ORB_CAPACITY_WAIT_SECONDS: '1' }, async () => {
    await new Promise(resolve => setTimeout(resolve, 1200));
    return admission(503);
  });
  assert.equal(code, 1);
  assert.equal(requests.length, 1);
  assert.match(output, /Timed out waiting/);
  assert(!output.includes('Waiting for sandbox capacity'));
});

test('allows disabling waiting and rejects invalid or extended wait budgets', async () => {
  const { code, requests } = await dispatch({ TUIST_ORB_CAPACITY_WAIT_SECONDS: '0' }, () => admission(429));
  assert.equal(code, 1);
  assert.equal(requests.length, 1);
  for (const value of ['151', '-1', '1.5', 'forever', '99999999999999999', '08']) {
    const result = await dispatch({ TUIST_ORB_CAPACITY_WAIT_SECONDS: value });
    assert.equal(result.code, 1);
    assert.equal(result.requests.length, 0);
  }
});

test('never retries pause/delete or non-admission status codes even with a hint', async () => {
  for (const operation of ['pause', 'delete']) {
    const result = await dispatch({ ORB_OPERATION: operation }, () => admission(503));
    assert.equal(result.code, 1);
    assert.equal(result.requests.length, 1);
  }
  for (const status of [400, 401, 403, 500, 502]) {
    const result = await dispatch({}, () => admission(status));
    assert.equal(result.code, 1);
    assert.equal(result.requests.length, 1);
  }
});

test('reauthenticates each retry with the current workload token', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'tuist-orb-retry-identity-'));
  const identity = join(directory, 'token');
  try {
    await writeFile(identity, 'identity-one');
    const { code, requests, output } = await dispatch({ TUIST_WORKLOAD_TOKEN_FILE: identity }, async attempt => {
      if (attempt === 1) {
        await writeFile(identity, 'identity-two');
        return admission(503);
      }
      return { status: 204 };
    });
    assert.equal(code, 0, output);
    assert.deepEqual(requests.map(request => request.auth), ['Bearer identity-one', 'Bearer identity-two']);
    assert(!output.includes('identity-one') && !output.includes('identity-two'));
  } finally { await rm(directory, { recursive: true, force: true }); }
});
