// Runs sentry-errors.yaml in a disposable Pulse and checks the stored rows:
// Atlas-compatible fingerprints for every case in sentry-errors-cases.json,
// scrubbing, and that resent events merge instead of double-counting.
//
//   PULSE_URL=http://127.0.0.1:4000 PULSE_AUTH=pilot:secret node test-sentry-errors.mjs
//
// Never point it at a managed Pulse: it creates and drops its own table and
// pipeline, but writes with the given identity.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const directory = new URL('.', import.meta.url);
const base = process.env.PULSE_URL ?? 'http://127.0.0.1:4000';
const authorization = `Basic ${Buffer.from(process.env.PULSE_AUTH ?? 'pilot:secret').toString('base64')}`;
const table = `errors_test_${process.pid}`;
const pipelineName = `sentry_errors_test_${process.pid}`;
const cases = JSON.parse(readFileSync(new URL('sentry-errors-cases.json', directory), 'utf8'));

async function call(path, { body, contentType } = {}) {
  const response = await fetch(`${base}${path}`, {
    method: body === undefined ? 'GET' : 'POST',
    body,
    headers: { Authorization: authorization, ...(contentType ? { 'Content-Type': contentType } : {}) },
  });
  const text = await response.text();
  assert.equal(response.status, 200, `${path}: ${text.slice(0, 2000)}`);
  return JSON.parse(text);
}

async function sql(query) {
  const result = await call(`/v1/sql?${new URLSearchParams({ sql: query })}`);
  const output = result.output[0];
  if (!output.records) return output;
  const names = output.records.schema.column_schemas.map(column => column.name);
  return output.records.rows.map(row => Object.fromEntries(row.map((value, index) => [names[index], value])));
}

const ingest = () => call(`/v1/ingest?${new URLSearchParams({ db: 'public', table, pipeline_name: pipelineName })}`, {
  body: JSON.stringify(cases.map(({ event }) => ({ service: 'server', event }))),
  contentType: 'application/json',
});

try {
  await sql(readFileSync(new URL('errors.sql', directory), 'utf8').replace('"errors"', `"${table}"`));
  await call(`/v1/pipelines/${pipelineName}`, {
    body: readFileSync(new URL('sentry-errors.yaml', directory), 'utf8'),
    contentType: 'application/x-yaml',
  });
  await ingest();
  const rows = await sql(`SELECT * FROM ${table}`);
  assert.equal(rows.length, cases.length);

  for (const { name, fingerprint, level, event } of cases) {
    const eventId = event.event_id.replaceAll('-', '').toLowerCase().padStart(32, '0');
    const row = rows.find(candidate => candidate.event_id === eventId);
    assert.ok(row, `${name}: stored`);
    assert.equal(row.fingerprint, fingerprint, `${name}: Atlas fingerprint`);
    assert.equal(row.level, level, `${name}: level`);
    assert.equal(row.service, 'server');
  }

  // Credentials, contact details and addresses never reach storage, while the
  // fields readers group and link by survive.
  const stored = JSON.stringify(rows);
  for (const secret of ['jane@example.com', '203.0.113.9', '10.1.2.3', 'abc.def', 'sk_live_1', 'session=1', 'token=abc', '"secret"', 'Bearer', 'phoenix']) {
    assert.ok(!stored.includes(secret), `stored rows leak ${secret}`);
  }
  const first = rows.find(row => row.event_id === '2d9f1c3e4b5a4c6d8e7f0a1b2c3d4e5f');
  const event = typeof first.event === 'string' ? JSON.parse(first.event) : first.event;
  assert.equal(first.account_handle, 'tuist');
  assert.equal(first.trace_id, '0af7651916cd43dd8448eb211c80319c');
  assert.equal(first.culprit, 'get_project!/1 at lib/tuist/projects.ex:88');
  assert.equal(first.title, 'Ecto.NoResultsError: expected at least one result but got none in query 42 for user [REDACTED]');
  assert.equal(BigInt(first.timestamp), 1794651330123456000n);
  assert.deepEqual(event.request, { method: 'GET', url: 'https://tuist.dev/api/projects/7' });
  assert.equal(event.extra['nested.password'], '[Filtered]');
  assert.equal(event.extra.api_key, '[Filtered]');
  assert.equal(event.tags.session_id, '[Filtered]');
  assert.equal(event.contexts['trace.trace_id'], '0af7651916cd43dd8448eb211c80319c');
  assert.equal(event.user, undefined);
  assert.deepEqual(event.exception[0].frames.map(frame => frame.function), ['handle/2', 'get_project!/1', 'get!/3']);
  assert.ok(event.exception[0].frames.every(frame => !('vars' in frame)));

  // SDK retries resend identical events; rows with the same issue and
  // timestamp merge on read.
  const timestamped = cases.filter(({ event }) => event.timestamp !== undefined).length;
  await ingest();
  const [{ total }] = await sql(`SELECT count(*) AS total FROM ${table}`);
  assert.equal(total, 2 * cases.length - timestamped);
  console.log(`PASS: ${cases.length} Sentry events grouped like Atlas, scrubbed, and resends merged`);
} finally {
  await sql(`DROP TABLE IF EXISTS ${table}`).catch(() => {});
  await fetch(`${base}/v1/pipelines/${pipelineName}?version=`, { method: 'DELETE', headers: { Authorization: authorization } }).catch(() => {});
}
