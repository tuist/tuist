// Measurement/reporting companion to iteration_benchmark.sh. No cache logic or Cargo orchestration lives here.
import { createHash } from 'node:crypto';
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync, openSync, closeSync, readSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { arch, cpus, platform, release } from 'node:os';
import { fileURLToPath } from 'node:url';
import { setTimeout } from 'node:timers/promises';
import { createServer } from 'node:http';
import { gunzipSync } from 'node:zlib';

const [operation, ...args] = process.argv.slice(2);
const writeJSON = (path, value) => writeFileSync(path, JSON.stringify(value, null, 2) + '\n');
const run = (command, argv = []) => {
  const result = spawnSync(command, argv, { encoding: 'utf8', timeout: 30_000 });
  if (result.error || result.status !== 0) throw new Error(`${command} failed`);
  return result.stdout.trim();
};
const cacheBytes = path => {
  if (!existsSync(path)) return 0;
  let total = 0;
  for (const entry of readdirSync(path, { withFileTypes: true })) {
    const child = join(path, entry.name);
    if (entry.isDirectory()) total += cacheBytes(child);
    else if (entry.isFile()) total += statSync(child).size;
  }
  return total;
};
const remoteJSON = async (path, method = 'GET') => {
  const response = await fetch(`${process.env.TUIST_URL.replace(/\/$/, '')}${path}`, {
    method,
    headers: { Authorization: `Bearer ${process.env.TUIST_TOKEN}` },
    redirect: 'error', signal: AbortSignal.timeout(10_000),
  });
  if (!response.ok) throw new Error(`Fixture API returned ${response.status}`);
  return response.json();
};
const buildsPath = () => {
  const parts = (process.env.TUIST_PROJECT ?? '').split('/');
  if (parts.length !== 2 || parts.some(p => !/^[a-zA-Z0-9_-]+$/.test(p))) throw new Error('Invalid fixture project handle');
  return `/api/projects/${parts.map(encodeURIComponent).join('/')}/cargo/builds`;
};
const reportPath = (root, branch) => join(root, `report-${createHash('sha256').update(branch).digest('hex')}.json`);

if (operation === 'toolchain') {
  const [root] = args;
  const toolchain = run('rustup', ['show', 'active-toolchain']).split(' (')[0];
  if (!toolchain || toolchain.includes('/')) throw new Error('A named rustup toolchain is required');
  const tools = { toolchain };
  for (const name of ['cargo', 'rustc']) {
    const path = run('rustup', ['which', '--toolchain', toolchain, name]);
    if (!isAbsolute(path) || !(statSync(path).mode & 0o111)) throw new Error(`Invalid native ${name} executable`);
    const fd = openSync(path, 'r');
    const magic = Buffer.alloc(4);
    try { readSync(fd, magic, 0, 4, 0); } finally { closeSync(fd); }
    if (!['7f454c46', 'cffaedfe', 'cefaedfe', 'cafebabe'].includes(magic.toString('hex')))
      throw new Error(`Refusing a non-native ${name} wrapper`);
    tools[name] = path;
  }
  writeJSON(join(root, 'toolchain.json'), tools);
} else if (operation === 'endpoints') {
  for (const value of args) {
    const url = new URL(value);
    if (!['http:', 'https:'].includes(url.protocol) || !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)
        || url.username || url.password) throw new Error('Remote endpoints must be isolated loopback URLs without credentials');
  }
} else if (operation === 'metadata') {
  const [root, binary, rounds, jobs, settings, scenarios, remote] = args;
  const fixture = fileURLToPath(new URL('.', import.meta.url));
  const revision = spawnSync('git', ['-C', fixture, 'rev-parse', 'HEAD'], { encoding: 'utf8' });
  const xcode = platform() === 'darwin' ? run('xcodebuild', ['-version']) : null;
  writeJSON(join(root, 'metadata.json'), {
    version: 1, created_at: new Date().toISOString(), rounds: Number(rounds), jobs: Number(jobs),
    settings, scenarios: scenarios.split(','), remote_enabled: remote === '1',
    skipped: remote === '1' || !scenarios.split(',').includes('R3') ? [] : [{ scenario: 'R3', reason: 'Remote fixture not configured' }],
    platform: platform(), architecture: arch(), os_release: release(), cpu: cpus()[0]?.model,
    toolchain: JSON.parse(readFileSync(join(root, 'toolchain.json'), 'utf8')),
    cargo: run(process.env.TUIST_CARGO_EXECUTABLE, ['--version']), rustc: run(process.env.RUSTC, ['-vV']), tuist: run(binary, ['version']),
    tuist_sha256: createHash('sha256').update(readFileSync(binary)).digest('hex'),
    repository_revision: revision.status === 0 ? revision.stdout.trim() : null,
    driver_sha256: Object.fromEntries(['iteration_benchmark.sh', 'iteration_benchmark.mjs'].map(name =>
      [name, createHash('sha256').update(readFileSync(join(fixture, name))).digest('hex')])),
    xcode,
    node: process.version,
    local_server_mode: 'Fixture reporting receiver, no configured remote cache; not production server ingestion',
    loader_environment_names: Object.keys(process.env).filter(k => k.startsWith('LD_') || k.startsWith('DYLD_')),
    limits: ['Synthetic workload, not a real application speedup claim', 'OS page cache uncontrolled',
      'Local reporting uses a fixture receiver, not production server ingestion',
      'Dependency-unit counts, CPU and peak memory are not measured',
      'No cross-worker qualification', 'Seven rounds do not establish p95 latency'],
  });
} else if (operation === 'local-server') {
  const [root] = args;
  const server = createServer(async (request, response) => {
    response.setHeader('Content-Type', 'application/json');
    try {
      if (request.method === 'GET' && request.url === '/.well-known/tuist.json') {
        response.end(JSON.stringify({ network_trusted_report_publishing: false, network_trusted_cache_access: false }));
      } else if (request.method === 'GET' && request.url === '/api/cache/endpoint') {
        response.end(JSON.stringify({ endpoint: null }));
      } else if (request.method === 'GET' && request.url === '/api/metadata/limits') {
        response.setHeader('x-tuist-custom-metadata-max-values', '20');
        response.end('{}');
      } else if (request.method === 'POST' && request.url === '/api/projects/fixture/iteration/cargo/builds'
          && request.headers.authorization === 'Bearer fixture-local-only') {
        const chunks = [];
        let size = 0;
        for await (const chunk of request) {
          size += chunk.length;
          if (size > 8_000_000) throw new Error('Oversized fixture report');
          chunks.push(chunk);
        }
        let body = Buffer.concat(chunks);
        if (request.headers['content-encoding'] === 'gzip') body = gunzipSync(body, { maxOutputLength: 8_000_000 });
        const report = JSON.parse(body);
        writeJSON(reportPath(root, report.git_branch), report);
        response.writeHead(201).end(JSON.stringify({ id: report.id }));
      } else {
        response.writeHead(404).end(JSON.stringify({ message: 'No fixture route' }));
      }
    } catch {
      response.writeHead(400).end(JSON.stringify({ message: 'Invalid fixture report' }));
    }
  });
  server.listen(0, '127.0.0.1', () => writeFileSync(join(root, 'local-server-url'), `http://127.0.0.1:${server.address().port}`));
} else if (operation === 'measure') {
  const [directory, phase, round, settings, scenario, configuration, command, ...argv] = args;
  const log = join(directory, `${phase}.log`);
  const before = cacheBytes(process.env.XDG_CACHE_HOME);
  const fd = openSync(log, 'w', 0o600);
  const started = process.hrtime.bigint();
  const result = spawnSync(command, argv, { stdio: ['ignore', fd, fd], timeout: 600_000, killSignal: 'SIGKILL' });
  const elapsed = Number(process.hrtime.bigint() - started) / 1e6;
  closeSync(fd);
  // Sanitization and all accounting stay outside the measured interval. Never persist a supplied token in logs.
  let text = readFileSync(log, 'utf8');
  if (process.env.TUIST_TOKEN) text = text.replaceAll(process.env.TUIST_TOKEN, '[REDACTED]');
  writeFileSync(log, text);
  writeJSON(join(directory, `${phase}.json`), {
    round: Number(round), settings, scenario, configuration, phase, wall_ms: elapsed,
    status: result.status, signal: result.signal, error: result.error?.code ?? null,
    command: [configuration === 'cargo' ? 'cargo' : 'tuist', ...argv],
    cache_bytes_before: before, cache_bytes_after: cacheBytes(process.env.XDG_CACHE_HOME),
    verified: false,
  });
  if (result.error || result.status !== 0) throw new Error(`Build failed; inspect ${log}`);
} else if (operation === 'remote-setup') {
  const [directory, phase] = args;
  const token = await remoteJSON(`/api/cache/token?full_handle=${encodeURIComponent(process.env.TUIST_PROJECT)}`, 'POST');
  if (typeof token.token !== 'string' || !token.token || !(token.expires_in > 0))
    throw new Error('Remote cache credentials unavailable; refusing a fallback benchmark');
  // Never retain the purpose-bound token. This checks credentials, not REAPI connectivity or command activity.
  writeJSON(join(directory, `${phase}-remote-setup.json`), { credentials_available: true });
} else if (operation === 'remote-report' || operation === 'local-report') {
  const [directory, phase, branch, root] = args;
  const path = join(directory, `${phase}.json`);
  const sample = JSON.parse(readFileSync(path, 'utf8'));
  if (operation === 'remote-report'
      && !JSON.parse(readFileSync(join(directory, `${phase}-remote-setup.json`), 'utf8')).credentials_available)
    throw new Error('Remote cache credentials were not checked');
  const units = phase === 'prime' || phase === 'remote-proof' ? 4 : phase === 'edited' ? 1
    : { I1: 0, I2: 1, I3: 3, I5: 1, R1: 4, R2: 4, R3: 4 }[sample.scenario];
  const complete = detail => {
    if (detail.compilations_truncated || detail.status !== 'success') throw new Error('Incomplete or failed fixture build report');
    const cache = detail.cache;
    if (cache && (cache.remote_failures > 0 || cache.background_upload_failures > 0))
      throw new Error('Remote fixture failed; refusing a fallback benchmark');
    const hits = cache?.hits ?? 0;
    if (!Number.isInteger(units) || !Number.isInteger(hits) || hits < 0 || hits > units)
      throw new Error('Invalid controlled-workspace cache observations');
    if (operation === 'remote-report' && sample.settings === 'no-incremental' && units === 4
        && !(hits + (cache?.misses ?? 0) > 0))
      throw new Error('Missing cache decisions; refusing a fallback benchmark');
    const requiresRemoteReuse = sample.settings === 'no-incremental'
      && (phase === 'remote-proof' || (phase === 'measured' && sample.scenario === 'R3'));
    if (requiresRemoteReuse && !(sample.cache_bytes_before === 0 && hits > 0 && cache?.downloaded_bytes > 0))
      throw new Error('Restore did not demonstrate remote reuse with an empty client cache');
    if (detail.compilations.length > units - hits) throw new Error('Unexpected compiler observations');
    return detail.compilations.length === units - hits;
  };
  let detail;
  if (operation === 'local-report') {
    detail = JSON.parse(readFileSync(reportPath(root, branch), 'utf8'));
    if (!complete(detail)) throw new Error('Missing compiler observations');
  }
  let ready = operation === 'local-report';
  for (let attempt = 0; operation === 'remote-report' && attempt < 40; attempt++) {
    const list = await remoteJSON(`${buildsPath()}?git_branch=${encodeURIComponent(branch)}`);
    if (list.builds.length > 1) throw new Error('Multiple reports for a single benchmark command');
    if (list.builds.length === 1) {
      detail = await remoteJSON(`${buildsPath()}/${encodeURIComponent(list.builds[0].id)}`);
      if (complete(detail)) { ready = true; break; }
    }
    await setTimeout(1000);
  }
  if (!ready) throw new Error('Missing or incomplete fixture compiler observations');
  const cache = detail.cache;
  sample.build_id = detail.id;
  sample.cache = cache;
  sample.compiler_executions = detail.compilations.length;
  sample.observed_remote_reuse = sample.cache_bytes_before === 0 && cache?.hits > 0 && cache?.downloaded_bytes > 0;
  if (operation === 'remote-report') sample.remote_activity = cache?.downloaded_bytes > 0 || cache?.uploaded_bytes > 0
    ? 'observed' : 'unproven';
  if (phase === 'measured' && sample.scenario === 'R2' && sample.settings === 'no-incremental'
      && platform() === 'darwin' && arch() === 'arm64' && !(cache?.hits > 0)) throw new Error('R2 did not demonstrate local reuse');
  writeJSON(path, sample);
} else if (operation === 'remote-publication') {
  const [directory] = args;
  const proof = JSON.parse(readFileSync(join(directory, 'remote-proof.json'), 'utf8'));
  if (!proof.observed_remote_reuse) throw new Error('Cold publication did not demonstrate remote reuse');
  const path = join(directory, 'measured.json');
  const sample = JSON.parse(readFileSync(path, 'utf8'));
  sample.observed_remote_publication = true;
  sample.remote_activity = 'publication-verified-by-restore';
  writeJSON(path, sample);
} else if (operation === 'verified') {
  const path = join(args[0], 'measured.json');
  const sample = JSON.parse(readFileSync(path, 'utf8'));
  sample.verified = true;
  writeJSON(path, sample);
} else if (operation === 'summarize') {
  const root = args[0];
  const metadata = JSON.parse(readFileSync(join(root, 'metadata.json'), 'utf8'));
  const samples = [];
  const visit = path => {
    for (const entry of readdirSync(path, { withFileTypes: true })) {
      // Only traverse the driver-owned result hierarchy, never caches, source trees or target directories.
      const child = join(path, entry.name);
      if (entry.isFile() && entry.name === 'measured.json') samples.push(JSON.parse(readFileSync(child, 'utf8')));
      else if (entry.isDirectory() && /^(normal|no-incremental|I[1235]|R[123]|round-[0-9]+|cargo|local|remote)$/.test(entry.name)) visit(child);
    }
  };
  visit(root);
  const quantile = (values, fraction) => {
    const sorted = [...values].sort((a, b) => a - b);
    const index = (sorted.length - 1) * fraction;
    const low = Math.floor(index), weight = index - low;
    return sorted[low] * (1 - weight) + sorted[Math.ceil(index)] * weight;
  };
  const groups = new Map();
  for (const sample of samples) {
    if (!sample.verified || sample.status !== 0) throw new Error('Refusing to summarize an unverified sample');
    if (sample.configuration === 'remote' && sample.settings === 'no-incremental' && sample.scenario === 'R1'
        && !sample.observed_remote_publication) throw new Error('Unverified remote cold publication');
    const key = `${sample.settings}/${sample.scenario}/${sample.configuration}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(sample);
  }
  const lanes = metadata.settings === 'all' ? ['normal', 'no-incremental'] : [metadata.settings];
  for (const lane of lanes) for (const scenario of metadata.scenarios) {
    if (metadata.skipped.some(s => s.scenario === scenario)) continue;
    const configurations = scenario === 'R3' ? ['cargo', 'remote']
      : metadata.remote_enabled && scenario !== 'R2' ? ['cargo', 'local', 'remote'] : ['cargo', 'local'];
    for (const configuration of configurations) {
      const key = `${lane}/${scenario}/${configuration}`;
      const group = groups.get(key) ?? [];
      if (group.length !== metadata.rounds || new Set(group.map(s => s.round)).size !== metadata.rounds)
        throw new Error(`Missing or duplicate samples for ${key}`);
    }
  }
  const rows = [...groups].sort(([a], [b]) => a.localeCompare(b)).map(([key, group]) => {
    if (group.length !== metadata.rounds) throw new Error(`Incomplete rounds for ${key}`);
    const deltas = [], ratios = [];
    for (const sample of group) {
      const baseline = samples.find(s => s.settings === sample.settings && s.scenario === sample.scenario
        && s.round === sample.round && s.configuration === 'cargo');
      if (!baseline) throw new Error(`Missing paired baseline for ${key}`);
      deltas.push(sample.wall_ms - baseline.wall_ms);
      ratios.push(sample.wall_ms / baseline.wall_ms);
    }
    const times = group.map(s => s.wall_ms);
    const median = quantile(times, 0.5);
    return { key, samples: group.length, median_ms: median,
      iqr_ms: quantile(times, 0.75) - quantile(times, 0.25),
      median_paired_delta_ms: quantile(deltas, 0.5), median_paired_ratio: quantile(ratios, 0.5) };
  });
  writeJSON(join(root, 'results.json'), { metadata, rows, samples });
  const lines = ['# Cargo iteration benchmark results', '',
    'Synthetic controlled workspace. Ratios greater than 1 mean slower than ordinary Cargo.',
    'Local reporting uses a fixture receiver; remote reporting uses the real server. Observed cache counters are in results.json.', '',
    '| Settings / scenario / configuration | n | Median ms | IQR ms | Paired Δ ms | Paired ratio |',
    '| --- | ---: | ---: | ---: | ---: | ---: |',
    ...rows.map(r => `| ${r.key.replace(/\/remote$/, '/remote-configured')} | ${r.samples} | ${r.median_ms.toFixed(1)} | ${r.iqr_ms.toFixed(1)} | ${r.median_paired_delta_ms.toFixed(1)} | ${r.median_paired_ratio.toFixed(3)} |`),
    '', `Remote-configured samples without measured transfer or publication evidence: ${samples.filter(s => s.configuration === 'remote' && s.remote_activity === 'unproven').length}. These are not proof of remote execution or reuse.`,
    '', ...metadata.skipped.map(s => `Skipped ${s.scenario}: ${s.reason}.`), ''];
  writeFileSync(join(root, 'results.md'), lines.join('\n'));
  process.stdout.write(lines.join('\n'));
} else {
  throw new Error(`Unknown reporter operation: ${operation}`);
}
