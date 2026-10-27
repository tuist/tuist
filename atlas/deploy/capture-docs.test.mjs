import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { chmod, mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { captureOne, PNG_HEADER } from './capture-docs.mjs';

async function fixture(t, mode = 'success') {
  const root = await mkdtemp(join(tmpdir(), 'atlas capture '));
  t.after(() => rm(root, { recursive: true, force: true }));
  const output = join(root, 'output');
  await mkdir(output);
  const chrome = join(root, 'fake chrome.mjs');
  await writeFile(chrome, `#!/usr/bin/env node
import { writeFileSync } from 'node:fs';
const mode = ${JSON.stringify(mode)};
const args = process.argv.slice(2);
const shot = args.find(arg => arg.startsWith('--screenshot=')).slice('--screenshot='.length);
writeFileSync(shot.replace('.png', '.json'), JSON.stringify(args));
console.error('capture diagnostics');
if (mode === 'failure') process.exit(7);
if (mode === 'hang') {
  writeFileSync(shot.replace('.png', '.pid'), String(process.pid));
  setTimeout(() => {}, 60_000);
} else if (mode !== 'missing') {
  const header = mode === 'invalid' ? Buffer.from('not a png') : Buffer.from('89504e470d0a1a0a', 'hex');
  writeFileSync(shot, Buffer.concat([header, Buffer.alloc(mode === 'incomplete' ? 10 : 1024)]));
}
`);
  await chmod(chrome, 0o700);
  return { output, chrome, temporary: root, name: 'desktop', size: '1440,1100' };
}

test('capture bounds page waits and uses a temporary profile', async t => {
  const options = await fixture(t);
  await captureOne({ ...options, extra: ['--force-dark-mode'] });
  const args = JSON.parse(await readFile(join(options.output, 'desktop.json'), 'utf8'));
  for (const flag of ['--timeout=15000', '--virtual-time-budget=5000', '--disable-dev-shm-usage', '--force-dark-mode']) {
    assert.ok(args.includes(flag));
  }
  assert.ok(args.includes(`--user-data-dir=${join(options.temporary, 'profile-desktop')}`));
  assert.ok((await readFile(join(options.output, 'desktop.png'))).subarray(0, 8).equals(PNG_HEADER));
  assert.match(await readFile(join(options.output, 'desktop.log'), 'utf8'), /capture diagnostics/);
});

test('failed capture removes stale images and preserves diagnostics', async t => {
  const options = await fixture(t, 'failure');
  const shot = join(options.output, 'desktop.png');
  await writeFile(shot, Buffer.concat([PNG_HEADER, Buffer.alloc(1024)]));
  await assert.rejects(captureOne(options), /exit 7.*desktop.log/);
  assert.equal(existsSync(shot), false);
  assert.match(await readFile(join(options.output, 'desktop.log'), 'utf8'), /capture diagnostics/);
});

test('missing, incomplete and invalid images fail', async t => {
  for (const mode of ['missing', 'incomplete', 'invalid']) {
    await t.test(mode, async sub => {
      await assert.rejects(captureOne(await fixture(sub, mode)), /PNG.*desktop.log/);
    });
  }
});

test('timed-out browser is reaped and diagnostics survive', async t => {
  const options = await fixture(t, 'hang');
  await assert.rejects(captureOne({ ...options, timeout: 1000 }), /timeout after 1000ms.*desktop.log/);
  const pid = Number(await readFile(join(options.output, 'desktop.pid'), 'utf8'));
  assert.throws(() => process.kill(pid, 0), { code: 'ESRCH' });
  assert.match(await readFile(join(options.output, 'desktop.log'), 'utf8'), /capture diagnostics/);
});

const macChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const chrome = process.env.ATLAS_CHROME_PATH || spawnSync('which', ['google-chrome'], { encoding: 'utf8' }).stdout?.trim()
  || (existsSync(macChrome) ? macChrome : undefined);
test('real Chrome captures a page with a resource that never completes', { skip: !chrome }, async t => {
  const options = await fixture(t);
  const server = createServer((request, response) => {
    response.writeHead(200, { 'content-type': request.url === '/' ? 'text/html' : 'image/png' });
    if (request.url === '/') response.end('<h1>Atlas documentation</h1><img src="/never.png">');
    else response.flushHeaders();
  });
  await new Promise(accept => server.listen(0, '127.0.0.1', accept));
  t.after(() => new Promise(accept => { server.closeAllConnections(); server.close(accept); }));
  await captureOne({ ...options, chrome, url: `http://127.0.0.1:${server.address().port}/` });
  assert.ok((await readFile(join(options.output, 'desktop.png'))).subarray(0, 8).equals(PNG_HEADER));
});
