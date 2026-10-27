#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { closeSync, openSync } from 'node:fs';
import { mkdir, readFile, unlink } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const PNG_HEADER = Buffer.from('89504e470d0a1a0a', 'hex');

function killGroup(pid) {
  if (!pid) return;
  try {
    process.kill(-pid, 'SIGKILL');
  } catch (error) {
    if (error.code !== 'ESRCH') throw error;
  }
}

export async function captureOne({ output, chrome, temporary, name, size, extra = [],
  url = 'https://localhost:18443/docs/self-hosting', timeout = 30_000 }) {
  await mkdir(output, { recursive: true });
  const screenshot = join(output, `${name}.png`);
  const log = join(output, `${name}.log`);
  await unlink(screenshot).catch(error => { if (error.code !== 'ENOENT') throw error; });
  const diagnostics = openSync(log, 'w', 0o600);
  let child;
  try {
    child = spawn(chrome, [
      '--headless', '--no-sandbox', '--disable-gpu',
      '--disable-dev-shm-usage', '--disable-background-networking',
      '--ignore-certificate-errors', '--hide-scrollbars',
      '--no-first-run', '--no-default-browser-check',
      '--timeout=15000', '--virtual-time-budget=5000',
      `--user-data-dir=${join(temporary, `profile-${name}`)}`,
      `--window-size=${size}`, `--screenshot=${screenshot}`, ...extra, url,
    ], { stdio: ['ignore', diagnostics, diagnostics], detached: true });
    let timedOut = false;
    const status = await new Promise((accept, reject) => {
      const timer = setTimeout(() => { timedOut = true; killGroup(child.pid); }, timeout);
      child.once('error', error => { clearTimeout(timer); reject(error); });
      child.once('close', code => { clearTimeout(timer); accept(code); });
    });
    const fail = reason => { throw new Error(`Chrome did not capture ${name} (${reason}); see ${log}`); };
    if (timedOut) fail(`timeout after ${timeout}ms`);
    if (status !== 0) fail(`exit ${status}`);
    const image = await readFile(screenshot).catch(error => {
      if (error.code === 'ENOENT') fail('missing PNG');
      throw error;
    });
    if (image.length < 1000 || !image.subarray(0, PNG_HEADER.length).equals(PNG_HEADER)) fail('incomplete or invalid PNG');
  } finally {
    killGroup(child?.pid);
    closeSync(diagnostics);
  }
}

async function main() {
  const [directory, chrome, temporary] = process.argv.slice(2);
  if (process.argv.length !== 5) throw new Error('Usage: capture-docs.mjs OUTPUT CHROME TEMPORARY');
  for (const [name, size, extra] of [
    ['desktop', '1440,1100', []], ['mobile', '390,844', []], ['dark', '1440,1100', ['--force-dark-mode']],
  ]) await captureOne({ output: resolve(directory), chrome, temporary, name, size, extra });
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
