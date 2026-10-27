import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const script = fileURLToPath(new URL('./dispatch.sh', import.meta.url));

async function dispatch(overrides = {}, status = 204) {
  const requests = [];
  const server = createServer(async (request, response) => {
    let body = '';
    for await (const chunk of request) body += chunk;
    requests.push({ path: request.url, auth: request.headers.authorization, body: JSON.parse(body) });
    response.writeHead(status).end();
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    const child = spawn('bash', [script], { env: {
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
    assert(!output.includes('orb-secret') && !output.includes('api-secret'));
    return { code, output, requests };
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
}

test('spawn translates the contract without forwarding provider credentials or snapshot IDs', async () => {
  const { code, requests } = await dispatch({ AMP_URL: 'https://amp.example.com', ORB_SNAPSHOT_ID: 'snapshot-id', AMP_ORB_PROVIDER_TOKEN: 'provider-secret' });
  assert.equal(code, 0);
  assert.deepEqual(requests, [{
    path: '/api/accounts/test-team/sandboxes/amp-orbs/amp-thread', auth: 'Bearer api-secret',
    body: { operation: 'spawn', orb_token: 'orb-secret', template: 'default', vcpus: 2, memory_mb: 4096, workspace_gb: 10, amp_url: 'https://amp.example.com' },
  }]);
});

test('pause and delete require no per-Orb token or image', async () => {
  for (const operation of ['pause', 'delete']) {
    const { code, requests } = await dispatch({ ORB_OPERATION: operation, ORB_TOKEN: '', ORB_IMAGE: '' });
    assert.equal(code, 0);
    assert.deepEqual(requests[0].body, { operation });
  }
});

test('refuses unsafe path components, missing tokens, unsupported images and unknown operations before HTTP', async () => {
  for (const overrides of [{ ORB_ID: '../other' }, { TUIST_ACCOUNT: 'a/b' }, { ORB_TOKEN: '' }, { ORB_IMAGE: 'arbitrary:latest' }, { ORB_OPERATION: 'unknown' }]) {
    const { code, requests } = await dispatch(overrides);
    assert.notEqual(code, 0);
    assert.equal(requests.length, 0);
  }
});

test('propagates capacity and authentication failures without retrying or logging the response', async () => {
  for (const status of [401, 403, 409, 503]) {
    const { code, output, requests } = await dispatch({}, status);
    assert.notEqual(code, 0);
    assert.match(output, new RegExp(`HTTP ${status}`));
    assert.equal(requests.length, 1);
  }
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
