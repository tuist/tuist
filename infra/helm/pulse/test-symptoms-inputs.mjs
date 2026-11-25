// Runs loki-otlp.yaml, symptoms.sql and span-edges.sql in a disposable Pulse
// and checks the Symptoms evaluator's inputs: log template keys and masking,
// exception fingerprints that match sentry-errors.yaml's for the same crash,
// the trace and log Flows, and the span-edge query.
//
//   PULSE_URL=http://127.0.0.1:4000 PULSE_AUTH=pilot:secret node test-symptoms-inputs.mjs
//
// Never point it at a managed Pulse: it creates and drops its own tables,
// Flows and pipelines (every name gets a per-run suffix), but writes with the
// given identity. Flows need a flownode: run it against `pulse standalone`.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const directory = new URL('.', import.meta.url);
const base = process.env.PULSE_URL ?? 'http://127.0.0.1:4000';
const authorization = `Basic ${Buffer.from(process.env.PULSE_AUTH ?? 'pilot:secret').toString('base64')}`;
const suffix = `_t${process.pid}`;
const rename = text => text.replace(/\b(opentelemetry_logs|opentelemetry_traces|symptoms_[a-z0-9_]+)\b/g, `$1${suffix}`);
const logs = `opentelemetry_logs${suffix}`;
const traces = `opentelemetry_traces${suffix}`;
const errors = `errors${suffix}`;
const lokiPipeline = `loki_otlp${suffix}`;
const errorsPipeline = `sentry_errors${suffix}`;
const statements = text => text.split(/;\s*$/m)
  .map(statement => statement.replace(/^\s*--.*$/gm, '').trim())
  .filter(Boolean);
const symptomsSql = statements(rename(readFileSync(new URL('symptoms.sql', directory), 'utf8')));
const flows = symptomsSql.map(statement => statement.match(/^CREATE FLOW IF NOT EXISTS (\S+)/)?.[1]).filter(Boolean);
const sinks = [...symptomsSql.join('\n').matchAll(/^(?:SINK TO|CREATE TABLE IF NOT EXISTS) (\S+)/gm)].map(match => match[1]);

async function call(path, { body, contentType, headers = {}, method } = {}) {
  const response = await fetch(`${base}${path}`, {
    method: method ?? (body === undefined ? 'GET' : 'POST'),
    body,
    headers: { Authorization: authorization, ...(contentType ? { 'Content-Type': contentType } : {}), ...headers },
  });
  const text = await response.text();
  assert.ok([200, 204].includes(response.status), `${path}: ${response.status} ${text.slice(0, 2000)}`);
  return text ? JSON.parse(text) : {};
}

async function sql(query) {
  const result = await call(`/v1/sql?${new URLSearchParams({ sql: query })}`);
  const output = result.output[0];
  if (!output.records) return output;
  const names = output.records.schema.column_schemas.map(column => column.name);
  return output.records.rows.map(row => Object.fromEntries(row.map((value, index) => [names[index], value])));
}

// Minimal OTLP/HTTP protobuf, as in .github/scripts/pulse-smoke.mjs.
const concat = (...parts) => Buffer.concat(parts);
function varint(value) {
  value = BigInt(value);
  const bytes = [];
  do { bytes.push(Number(value & 127n) | (value > 127n ? 128 : 0)); value >>= 7n; } while (value);
  return Buffer.from(bytes);
}
const message = (field, value) => {
  const body = typeof value === 'string' ? Buffer.from(value) : value;
  return concat(varint(field * 8 + 2), varint(body.length), body);
};
const fixed = (field, value) => {
  const body = Buffer.alloc(8);
  body.writeBigUInt64LE(value);
  return concat(varint(field * 8 + 1), body);
};
const attribute = (key, value) => message(1, concat(message(1, key), message(2, message(1, value))));
const resource = attributes => message(1, concat(...Object.entries(attributes).map(([key, value]) => attribute(key, value))));
const otlp = (signal, body, headers) => call(`/v1/otlp/v1/${signal}`, {
  body, contentType: 'application/x-protobuf', headers: { 'X-Pulse-DB-Name': 'public', ...headers },
});

const now = BigInt(Date.now()) * 1000000n - 2000000000n;
const second = 1000000000n;
const hex = (seed, length) => seed.repeat(length).slice(0, length);
// Span kinds and status codes as OTLP numbers: SERVER 2, CLIENT 3; ERROR 2.
function span({ service, version, trace, id, parent, name, kind, start, millis, error }) {
  const body = concat(
    message(1, Buffer.from(trace, 'hex')), message(2, Buffer.from(id, 'hex')),
    parent ? message(4, Buffer.from(parent, 'hex')) : Buffer.alloc(0),
    message(5, name), Buffer.from([0x30, kind]), fixed(7, start), fixed(8, start + BigInt(Math.round(millis * 1e6))),
    error ? message(15, Buffer.from([0x18, 2])) : Buffer.alloc(0));
  return message(1, concat(resource({ 'service.name': service, ...(version ? { 'service.version': version } : {}) }),
    message(2, message(2, body))));
}

// An Elixir crash as Logger writes it, and the Sentry event the Elixir SDK
// sends for it: frames oldest first, none in-app, modules as Elixir atoms.
const crash = [
  'Task #PID<0.4321.0> started from Tuist.Worker terminating',
  '** (Ecto.NoResultsError) expected at least one result but got none in query 42',
  'for project 0x1f3a',
  '    (ecto 3.12.5) lib/ecto/repo/queryable.ex:164: Ecto.Repo.Queryable.one!/3',
  '    (tuist 0.1.0) lib/tuist/projects.ex:88: anonymous fn/2 in Tuist.Projects.get_project!/1',
  '    (elixir 1.18.4) lib/task/supervised.ex:101: Task.Supervised.invoke_mfa/2',
].join('\n');
const crashEvent = {
  event_id: hex('a1', 32), level: 'error', platform: 'elixir',
  exception: { values: [{
    type: 'Ecto.NoResultsError', value: 'expected at least one result but got none in query 42\nfor project 0x1f3a',
    stacktrace: { frames: [
      { module: 'Elixir.Task.Supervised', function: 'Task.Supervised.invoke_mfa/2', filename: 'lib/task/supervised.ex', lineno: 101, in_app: false },
      { module: 'Elixir.Tuist.Projects', function: 'anonymous fn/2 in Tuist.Projects.get_project!/1', filename: 'lib/tuist/projects.ex', lineno: 88, in_app: false },
      { module: 'Elixir.Ecto.Repo.Queryable', function: 'Ecto.Repo.Queryable.one!/3', filename: 'lib/ecto/repo/queryable.ex', lineno: 164, in_app: false },
    ] },
  }] },
};
const exit = [
  '** (RuntimeError) timed out waiting for the runner',
  '    (stdlib 6.2) gen_server.erl:1142: :gen_server.call/3',
  '    (tuist 0.1.0) lib/tuist/runners.ex:120: Tuist.Runners.dispatch/2',
].join('\n');
const exitEvent = {
  event_id: hex('b2', 32), level: 'error', platform: 'elixir',
  exception: [{
    type: 'RuntimeError', value: 'timed out waiting for the runner',
    stacktrace: { frames: [
      { module: 'Elixir.Tuist.Runners', function: 'Tuist.Runners.dispatch/2', filename: 'lib/tuist/runners.ex', lineno: 120, in_app: false },
      { module: 'gen_server', function: ':gen_server.call/3', filename: 'gen_server.erl', lineno: 1142, in_app: false },
    ] },
  }],
};

const consoleLine = (metadata, text) => `16:31:14.680 request_id=GA1b2c3 ${metadata} [error] ${text}`;
const failure = (project, account, ip, millis) => `Failed to fetch project ${project} for account ${account} from ${ip}: ` +
  `status=503 "upstream timeout" #PID<0.12${project % 10}.0> %{id: ${project}, name: %{first: "x"}} ` +
  `at /Users/runner/work/tuist/tuist/Sources/Run${project}.swift user u${project}@example.com hash deadbeef${project} ` +
  `code=E1001 HTTP/1.1 502 took ${millis}ms at 2026-11-16T16:31:${10 + project % 40}.123Z`;
const lines = [
  { stream: { service_name: 'tuist-server' }, line: consoleLine('method=GET', failure(4821, 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d', '10.0.0.12', '12.5')) },
  { stream: { service_name: 'tuist-server' }, line: consoleLine('method=POST', failure(77, 'f0e1d2c3-b4a5-4968-8776-655443322110', '2001:db8:85a3::8a2e:370:7334', 3)) },
  { stream: { service_name: 'kura-eu-west' }, line: JSON.stringify({ timestamp: '2026-11-16T10:00:00.123Z', level: 'WARN', target: 'kura::backfill::pass', message: 'backfill pass completed', peer: '10.0.0.3', absent: 3 }) },
  { stream: { service_name: 'kura-eu-west' }, line: JSON.stringify({ timestamp: '2026-11-16T10:00:01.123Z', level: 'WARN', target: 'kura::backfill::pass', message: 'backfill pass completed', peer: '10.0.0.4', absent: 9 }) },
  { stream: { service_name: 'kura-eu-west' }, line: JSON.stringify({ level: 'WARN', target: 'kura::store', message: 'backfill pass completed' }) },
  { stream: { service_name: 'tuist-server', level: 'info' }, line: 'Dispatched job 91 to runner r-1', metadata: { mfa: 'Tuist.Runners.dispatch/2', file: 'lib/tuist/runners.ex', line: '120' } },
  { stream: { service_name: 'tuist-server', level: 'info' }, line: 'Runner pool empty, queued', metadata: { mfa: 'Tuist.Runners.dispatch/2', file: 'lib/tuist/runners.ex', line: '120' } },
  { stream: { service_name: 'tuist-server', level: 'error' }, line: crash },
  { stream: { service_name: 'tuist-server', level: 'error' }, line: exit },
  { stream: { service_name: 'tuist-processor' }, line: "can't reach it, won't retry 'job-9'" },
];
// Credentials in log lines: a JWT, a Bearer token, a long base64 token and an
// AWS-style secret key (slashes, no + or =) never reach the stored body or
// template; an absolute path of the same shape stays.
const jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4ifQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c';
const bearer = 'tuist_9f8e7d6c-5b4a_3c2d1e0f';
const base64 = 'dGhpcyBpcyBhIHZlcnkgbG9uZyBzZWNyZXQgdG9rZW4gdmFsdWU+/xyz==';
const awsSecret = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';
const absolutePath = '/Users/Runner/Library/Caches/Tuist4Build9Products';
const tokenLines = [
  { stream: { service_name: 'tuist-cache' }, line: consoleLine('method=GET', `rejected token ${jwt} for cache`) },
  { stream: { service_name: 'tuist-cache' }, line: consoleLine('method=GET', `upstream sent Authorization: Bearer ${bearer} twice`) },
  { stream: { service_name: 'tuist-cache' }, line: consoleLine('method=GET', `signed key ${base64} expired`) },
  { stream: { service_name: 'tuist-cache' }, line: consoleLine('method=GET', `aws secret ${awsSecret} rejected`) },
  { stream: { service_name: 'tuist-cache' }, line: consoleLine('method=GET', `cached in ${absolutePath} today`) },
];
const secrets = [jwt, bearer, base64, awsSecret];
lines.push(...tokenLines);

const cleanup = async () => {
  for (const flow of flows) await sql(`DROP FLOW IF EXISTS ${flow}`).catch(() => {});
  for (const table of [...sinks, logs, traces, `${traces}_operations`, `${traces}_services`, errors]) await sql(`DROP TABLE IF EXISTS ${table}`).catch(() => {});
  for (const pipeline of [lokiPipeline, errorsPipeline]) {
    await fetch(`${base}/v1/pipelines/${pipeline}?version=`, { method: 'DELETE', headers: { Authorization: authorization } }).catch(() => {});
  }
};

try {
  // Production order: native OTLP creates both tables, then the deployment
  // smoke installs the pipeline and runs symptoms.sql.
  await otlp('logs', message(1, concat(resource({ 'service.name': 'pulse-ci' }),
    message(2, message(2, concat(fixed(1, now), message(3, 'INFO'), message(5, message(1, 'native'))))))),
  { 'X-Pulse-Log-Table-Name': logs });
  const trace = hex('0af7651916cd43dd', 32);
  const spans = [
    span({ service: 'tuist-server', version: '4.1.0', trace, id: hex('1', 16), name: 'GET /api/projects/:id', kind: 2, start: now - second, millis: 5 }),
    span({ service: 'tuist-server', version: '4.1.0', trace, id: hex('2', 16), parent: hex('1', 16), name: 'tuist.repo.query', kind: 3, start: now - second + 1000000n, millis: 0.4 }),
    span({ service: 'tuist-server', version: '4.1.0', trace, id: hex('3', 16), parent: hex('1', 16), name: 'POST /cache', kind: 3, start: now - second + 2000000n, millis: 120, error: true }),
    span({ service: 'kura-eu-west', version: '0.9.0', trace, id: hex('4', 16), parent: hex('3', 16), name: 'POST /cache', kind: 2, start: now - second + 3000000n, millis: 90000, error: true }),
    span({ service: 'kura-eu-west', version: '0.9.0', trace, id: hex('5', 16), parent: hex('3', 16), name: 'POST /cache', kind: 2, start: now - second + 4000000n, millis: 1.2 }),
  ];
  // The first span creates the table without service.version, as in a fresh
  // environment; symptoms.sql must still create every Flow. Flows do not
  // backfill, so it is counted only if a later span lands in its window.
  await otlp('traces', span({ service: 'pulse-ci', trace: hex('ff', 32), id: hex('9', 16), name: 'smoke', kind: 2, start: now - 3n * second, millis: 17 }),
    { 'X-Pulse-Pipeline-Name': 'pulse_trace_v1', 'X-Pulse-Trace-Table-Name': traces });
  await call(`/v1/pipelines/${lokiPipeline}`, { body: readFileSync(new URL('loki-otlp.yaml', directory), 'utf8'), contentType: 'application/x-yaml' });
  for (const statement of symptomsSql) await sql(statement);
  for (const table of sinks) {
    const [ddl] = await sql(`SHOW CREATE TABLE ${table}`);
    assert.match(ddl['Create Table'], /ttl\s*=\s*'(?:35d|35days|1month 4days 13h 26m 24s)'/i, `${table}: TTL`);
  }
  // Running the provisioning again changes nothing.
  for (const statement of symptomsSql) await sql(statement);

  for (const body of spans) {
    await otlp('traces', body, { 'X-Pulse-Pipeline-Name': 'pulse_trace_v1', 'X-Pulse-Trace-Table-Name': traces });
  }
  await call('/v1/loki/api/v1/push', {
    body: JSON.stringify({ streams: lines.map(({ stream, line, metadata }, index) => ({
      stream, values: [[String(now + BigInt(index) * 1000n), line, ...(metadata ? [metadata] : [])]],
    })) }),
    contentType: 'application/json',
    headers: { 'X-Pulse-DB-Name': 'public', 'X-Pulse-Pipeline-Name': lokiPipeline, 'X-Pulse-Log-Table-Name': logs },
  });

  const rows = await sql(`SELECT body, "service", "level", template_key, "template", exception_fp, severity_text, resource_attributes FROM ${logs} ORDER BY "timestamp"`);
  const row = text => rows.find(candidate => candidate.body === text);
  assert.equal(rows.length, lines.length + 1);
  // The native OTLP row keeps its schema and gets none of the new columns.
  assert.deepEqual(Object.entries(row('native')).filter(([key, value]) => ['service', 'template_key'].includes(key) && value != null), []);

  // Console lines: level from the [level] tag, every variable masked, the
  // status and error codes kept, and one key for both values.
  const [first, again] = [row(lines[0].line), row(lines[1].line)];
  assert.equal(first.service, 'tuist-server');
  assert.equal(first.level, 'error');
  assert.equal(first.template, 'Failed to fetch project <n> for account <uuid> from <ip>: status=503 <str> <term> <map> ' +
    'at <path> user <email> hash <hex> code=E1001 HTTP/1.1 502 took <n>ms at <ts>');
  assert.equal(again.template, first.template);
  assert.equal(again.template_key, first.template_key);
  assert.match(first.template_key, /^text:[0-9a-f]{16}$/);
  // Body, labels and severity are unchanged for existing readers.
  assert.equal(first.body, lines[0].line);
  assert.equal(first.resource_attributes['service.name'], 'tuist-server');

  // JSON lines: the message and the tracing target make the template.
  const [kura, kuraAgain, otherTarget] = [row(lines[2].line), row(lines[3].line), row(lines[4].line)];
  assert.equal(kura.level, 'warning');
  assert.equal(kura.template, 'backfill pass completed');
  assert.equal(kuraAgain.template_key, kura.template_key);
  assert.notEqual(otherTarget.template_key, kura.template_key);

  // Logger metadata names the call site, whatever the message says.
  const [dispatched, empty] = [row(lines[5].line), row(lines[6].line)];
  assert.match(dispatched.template_key, /^code:[0-9a-f]{16}$/);
  assert.equal(empty.template_key, dispatched.template_key);
  assert.equal(dispatched.level, 'info');
  assert.equal(row(lines[9].line).template, "can't reach it, won't retry <str>");

  // Tokens are masked in the stored line and the template.
  const cacheRows = rows.filter(candidate => candidate.service === 'tuist-cache');
  assert.equal(cacheRows.length, tokenLines.length);
  const pathRow = cacheRows.find(candidate => candidate.body.includes('cached in'));
  assert.ok(pathRow.body.includes(absolutePath), `body masks an absolute path: ${pathRow.body}`);
  const tokenRows = cacheRows.filter(candidate => candidate !== pathRow);
  for (const tokenRow of tokenRows) {
    for (const secret of secrets) {
      for (const part of secret.split('.')) {
        assert.ok(!tokenRow.body.includes(part), `body keeps a token: ${tokenRow.body}`);
        assert.ok(!tokenRow.template.includes(part), `template keeps a token: ${tokenRow.template}`);
      }
    }
  }
  assert.deepEqual(tokenRows.map(tokenRow => tokenRow.template).sort(), [
    'aws secret <token> rejected',
    'rejected token <token> for cache',
    'signed key <token> expired',
    'upstream sent Authorization: Bearer <token> twice',
  ]);
  assert.ok(tokenRows.some(tokenRow => tokenRow.body.endsWith('[error] rejected token <token> for cache')));

  // A crash in the logs and its Sentry event share one fingerprint.
  await sql(readFileSync(new URL('errors.sql', directory), 'utf8').replace('"errors"', `"${errors}"`));
  await call(`/v1/pipelines/${errorsPipeline}`, { body: readFileSync(new URL('sentry-errors.yaml', directory), 'utf8'), contentType: 'application/x-yaml' });
  await call(`/v1/ingest?${new URLSearchParams({ db: 'public', table: errors, pipeline_name: errorsPipeline })}`, {
    body: JSON.stringify([crashEvent, exitEvent].map(event => ({ service: 'tuist-server', event }))), contentType: 'application/json',
  });
  const issues = await sql(`SELECT event_id, fingerprint FROM ${errors}`);
  const fingerprint = id => issues.find(issue => issue.event_id === id).fingerprint;
  // Independent anchor: equality alone could let both pipelines drift from
  // Atlas's type|function|module|normalized-message contract.
  assert.equal(fingerprint(crashEvent.event_id), 'd257aae35ea052f66029d8957d4d1b5827f16b161b28f0b6c5709d4dede6d983');
  assert.equal(row(crash).exception_fp, fingerprint(crashEvent.event_id));
  assert.equal(row(exit).exception_fp, fingerprint(exitEvent.event_id));
  assert.notEqual(row(crash).exception_fp, row(exit).exception_fp);
  assert.equal(row(crash).template, 'Task <term> started from Tuist.Worker terminating');
  assert.equal(first.exception_fp, null);

  // Flows.
  for (const flow of flows) await sql(`ADMIN FLUSH_FLOW('${flow}')`);
  const counts = await sql(`SELECT service_name, span_kind, span_name, service_version, span_count, error_count FROM symptoms_trace_counts_1m${suffix} WHERE service_name <> 'pulse-ci' ORDER BY service_name, span_name, span_kind`);
  const summed = Object.values(counts.reduce((totals, entry) => {
    const key = [entry.service_name, entry.span_kind, entry.span_name, entry.service_version].join('|');
    totals[key] ??= { ...entry, span_count: 0, error_count: 0 };
    totals[key].span_count += entry.span_count;
    totals[key].error_count += entry.error_count;
    return totals;
  }, {}));
  assert.deepEqual(summed.map(entry => [entry.service_name, entry.span_kind, entry.span_name, entry.service_version, entry.span_count, entry.error_count]), [
    ['kura-eu-west', 'SPAN_KIND_SERVER', 'POST /cache', '0.9.0', 2, 1],
    ['tuist-server', 'SPAN_KIND_SERVER', 'GET /api/projects/:id', '4.1.0', 1, 0],
    ['tuist-server', 'SPAN_KIND_CLIENT', 'POST /cache', '4.1.0', 1, 1],
    ['tuist-server', 'SPAN_KIND_CLIENT', 'tuist.repo.query', '4.1.0', 1, 0],
  ]);
  const latency = await sql(`SELECT span_name, service_name, latency_bucket, span_count FROM symptoms_trace_latency_5m${suffix} WHERE service_name <> 'pulse-ci' ORDER BY latency_bucket`);
  // 0.4 ms -> 0, 1.2 ms -> 1, 5 ms -> 16, 120 ms -> 50, 90 s -> 115.
  assert.deepEqual(latency.map(entry => entry.latency_bucket), [0, 1, 16, 50, 115]);
  const templates = await sql(`SELECT "service", "level", template_key, sum(line_count) AS lines FROM symptoms_log_counts_1m${suffix} GROUP BY "service", "level", template_key`);
  assert.equal(templates.find(entry => entry.template_key === first.template_key).lines, 2);
  assert.equal(templates.find(entry => entry.template_key === dispatched.template_key).lines, 2);
  assert.equal(templates.length, 12);
  const totals = await sql(`SELECT "service", sum(line_count) AS lines FROM symptoms_log_totals_1m${suffix} GROUP BY "service" ORDER BY "service"`);
  assert.deepEqual(totals.map(entry => [entry.service, Number(entry.lines)]), [['kura-eu-west', 3], ['tuist-cache', 5], ['tuist-processor', 1], ['tuist-server', 6]]);

  // Span edges for the hour holding the spans: a read-only query, which the
  // dashboard identity may run, so the evaluator needs no write credential.
  const hour = new Date(Number((now - second) / 1000000n));
  hour.setUTCMinutes(0, 0, 0);
  const edgesSql = rename(readFileSync(new URL('span-edges.sql', directory), 'utf8').replace(/^--.*\n/gm, ''))
    .replaceAll('{{hour_start}}', hour.toISOString());
  assert.match(edgesSql.trim(), /^SELECT\b/, 'span-edges.sql must stay a read');
  const edges = (await sql(edgesSql))
    .map(edge => [edge.caller_service, edge.caller_span_name, edge.callee_service, edge.callee_span_name, Number(edge.edge_count)])
    .sort((a, b) => `${a[2]}\0${a[3]}`.localeCompare(`${b[2]}\0${b[3]}`));
  assert.deepEqual(edges, [
    ['tuist-server', 'POST /cache', 'kura-eu-west', 'POST /cache', 2],
    ['tuist-server', 'GET /api/projects/:id', 'tuist-server', 'POST /cache', 1],
    ['tuist-server', 'GET /api/projects/:id', 'tuist-server', 'tuist.repo.query', 1],
  ]);

  // Asymmetric normalization regression: these expected hashes come from
  // explicit canonical keys, not either pipeline's output. Two different
  // values of each type must group together, while different messages must
  // stay distinct. The key prefixes are:
  // RuntimeError|Tuist.Worker.run/1|Elixir.Tuist.Worker|
  const normalizationCases = [
    {
      // Sync <uuid> for <email> at <date> calling <url>
      fingerprint: 'f423bbe5f83fc45d55c8fc6f0e5ca6b5bf2fb7aee16f9c3974550df607b00cb7',
      values: [
        'Sync 0190a0b1-c2d3-7e4f-8a9b-0c1d2e3f4a5b for ops@example.com at 2026-11-20T08:15:00Z calling https://api.example.com/v1/runs/42?page=3',
        'Sync 7F1E2D3C-4B5A-4968-8776-655443322110 for dev@tuist.dev at 2026-11-21 09:00:01 calling http://localhost:8080/v1/runs/7',
      ],
    },
    {
      // Build <git_sha> on <ip> took <float>s; trace <hex>, buffer <hex> at attempt <int>
      fingerprint: '335c966cc039d27a7fe3b355ebd071e75da1cdaaa45c6b7ee7bc9b5f00a80e65',
      values: [
        'Build 3f2a9c1e5d7b8a6c4e2f0a1b3c5d7e9f1a2b3c4d on 10.0.12.7 took 12.5s; trace 4bf92f3577b34da6a3ce929d0e0e4736, buffer 0x7ffd at attempt 3',
        'Build 1234567890abcdef1234567890abcdef12345678 on 192.168.1.42 took 0.25s; trace abcdef0123456789, buffer 0XDEAD at attempt 99',
      ],
    },
  ];
  let regressionIndex = 0;
  for (const testCase of normalizationCases) {
    for (const value of testCase.values) {
      const event = {
        event_id: (++regressionIndex).toString(16).padStart(32, '0'),
        exception: { values: [{ type: 'RuntimeError', value, stacktrace: { frames: [{
          module: 'Elixir.Tuist.Worker', function: 'Tuist.Worker.run/1', filename: 'lib/tuist/worker.ex', lineno: 42, in_app: false,
        }] } }] },
      };
      const line = `** (RuntimeError) ${value}\n    (tuist 0.1.0) lib/tuist/worker.ex:42: Tuist.Worker.run/1`;
      await call('/v1/loki/api/v1/push', {
        body: JSON.stringify({ streams: [{ stream: { service_name: 'tuist-regression', level: 'error' },
          values: [[String(now + BigInt(regressionIndex) * second), line]] }] }),
        contentType: 'application/json',
        headers: { 'X-Pulse-DB-Name': 'public', 'X-Pulse-Pipeline-Name': lokiPipeline, 'X-Pulse-Log-Table-Name': logs },
      });
      await call(`/v1/ingest?${new URLSearchParams({ db: 'public', table: errors, pipeline_name: errorsPipeline })}`, {
        body: JSON.stringify([{ service: 'tuist-regression', event }]), contentType: 'application/json',
      });
      const [log] = await sql(`SELECT exception_fp FROM ${logs} WHERE "service" = 'tuist-regression' ORDER BY "timestamp" DESC LIMIT 1`);
      const [error] = await sql(`SELECT fingerprint FROM ${errors} WHERE event_id = '${event.event_id}'`);
      assert.equal(log.exception_fp, testCase.fingerprint, `Loki: ${value}`);
      assert.equal(error.fingerprint, testCase.fingerprint, `Sentry: ${value}`);
    }
  }
  console.log(`PASS: ${regressionIndex} typed-normalization crashes match independent fingerprint anchors`);
  console.log(`PASS: ${lines.length} log lines keyed and masked (${secrets.length} with tokens), 2 crashes fingerprinted like their Sentry events, ${flows.length} Flows and the span-edge table`);
} finally {
  await cleanup();
}
