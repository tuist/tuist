// Runs sentry-errors.yaml in a disposable Pulse and checks the stored rows:
// Atlas-compatible fingerprints for every case in sentry-errors-cases.json,
// scrubbing, that distinct events at one timestamp are all kept, that resent
// events count once, and the issue lifecycle rollup (error-issues.sql).
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
const issuesTable = `error_issue_hours_test_${process.pid}`;
const flow = `error_issues_test_${process.pid}`;
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

// Personal data the grouping cases don't cover; its fingerprint is not pinned.
const token = 'tuist_0190a0b1-c2d3-7e4f-8a9b-0c1d2e3f4a5b_Zx9y8W7v';
const scrubEvent = {
  event_id: 'feedfacefeedfacefeedfacefeedface',
  timestamp: 1794651331,
  message: `GET https://ci:hunter2@tuist.dev/api/runs?token=s3cr3t&page=2 from 2001:db8:85a3::8a2e:370:7334 and fe80:0:0:0:202:b3ff:fe1e:8329 with Basic dXNlcjpwYXNzd29yZA== and ${token} at 12:30:45 in kura::cache::store`,
  breadcrumbs: [{ category: 'http', message: 'GET /api/projects?session=abc123' }],
  extra: { remote_ip: 'edge-7', client_ip: 'edge-8', users: [{ name: 'Jane', password: 'p' }], counts: [1, 2] },
  tags: { 'x-forwarded-for': 'edge-9', ip: 'edge-10', zip_code: '08001' },
};
// Two events of one issue at the same timestamp are two events.
const sameTime = ['c', 'd'].map(id => ({ event_id: id.repeat(32), timestamp: 1794651340.25, message: 'Same instant' }));
// Recent events for the issue rollup, which covers the last day: a new issue,
// and one that occurred nine days ago (written straight into the rollup below,
// since the flow does not read that far back) and has now regressed.
const now = Date.now() / 1000;
const fresh = { event_id: 'e'.repeat(32), timestamp: now - 60, message: 'Fresh failure' };
const freshAgain = { event_id: 'f'.repeat(32), timestamp: now - 30, message: 'Fresh failure' };
const returning = { event_id: 'ab'.repeat(16), timestamp: now - 10, message: 'Returning failure' };
const events = [...cases.map(({ event }) => event), scrubEvent, ...sameTime, fresh, freshAgain, returning];

const ingest = () => call(`/v1/ingest?${new URLSearchParams({ db: 'public', table, pipeline_name: pipelineName })}`, {
  body: JSON.stringify(events.map(event => ({ service: 'server', event }))),
  contentType: 'application/json',
});

try {
  await sql(readFileSync(new URL('errors.sql', directory), 'utf8').replace('"errors"', `"${table}"`));
  // The deployment's statements, one at a time, on this run's tables.
  const issues = readFileSync(new URL('error-issues.sql', directory), 'utf8')
    .replaceAll('"error_issue_hours"', `"${issuesTable}"`).replace('"error_issues"', `"${flow}"`).replace('"errors"', `"${table}"`);
  for (const statement of issues.split(/;\s*$/m).filter(text => text.replace(/--.*$/gm, '').trim())) await sql(statement);
  await call(`/v1/pipelines/${pipelineName}`, {
    body: readFileSync(new URL('sentry-errors.yaml', directory), 'utf8'),
    contentType: 'application/x-yaml',
  });
  await ingest();
  const rows = await sql(`SELECT * FROM ${table}`);
  assert.equal(rows.length, events.length);

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
  for (const secret of ['jane@example.com', '203.0.113.9', '10.1.2.3', 'abc.def', 'sk_live_1', 'session=1', 'token=abc', '"secret"', 'Bearer', 'phoenix',
    'hunter2', 's3cr3t', 'page=2', '2001:db8', '8a2e:370:7334', 'fe80:0:0', 'dXNlcjpwYXNzd29yZA', token, 'abc123', 'edge-', 'Jane']) {
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

  const scrubbed = rows.find(row => row.event_id === scrubEvent.event_id);
  const scrubbedEvent = typeof scrubbed.event === 'string' ? JSON.parse(scrubbed.event) : scrubbed.event;
  assert.match(scrubbedEvent.message, /tuist\.dev\/api\/runs\[REDACTED\] from \[REDACTED\]/);
  assert.match(scrubbedEvent.message, /at 12:30:45 in kura::cache::store$/);
  assert.equal(scrubbedEvent.breadcrumbs[0].message, 'GET /api/projects[REDACTED]');
  for (const key of ['remote_ip', 'client_ip', 'users']) assert.equal(scrubbedEvent.extra[key], '[Filtered]', key);
  assert.deepEqual(scrubbedEvent.extra.counts, [1, 2]);
  assert.equal(scrubbedEvent.tags['x-forwarded-for'], '[Filtered]');
  assert.equal(scrubbedEvent.tags.ip, '[Filtered]');
  assert.equal(scrubbedEvent.tags.zip_code, '08001');

  assert.equal(rows.filter(row => row.title === 'Same instant').length, 2, 'same-timestamp events both stored');

  // SDK retries resend identical events. The table keeps every row, and
  // readers count distinct event IDs.
  await ingest();
  const [{ total, distinct }] = await sql(`SELECT count(*) AS total, count(DISTINCT event_id) AS "distinct" FROM ${table}`);
  assert.equal(total, 2 * events.length);
  assert.equal(distinct, events.length);

  // Issue lifecycle: the regressed issue's earlier occurrence, then a flush,
  // which the deployment also runs, recomputes the last day.
  const fingerprintOf = title => rows.find(row => row.title === title).fingerprint;
  const day = 86400;
  await sql(`INSERT INTO ${issuesTable} ("service", fingerprint, first_seen, last_seen, events, time_window) VALUES ` +
    `('server', '${fingerprintOf('Returning failure')}', to_timestamp_seconds(${Math.floor(now - 9 * day)}), ` +
    `to_timestamp_seconds(${Math.floor(now - 9 * day)}), 4, date_bin('1 hour'::INTERVAL, to_timestamp_seconds(${Math.floor(now - 9 * day)})))`);
  await sql(`ADMIN flush_flow('${flow}')`);
  const lifetime = await sql(`SELECT "service", fingerprint, sum(events) AS events FROM ${issuesTable} GROUP BY "service", fingerprint`);
  const eventsOf = title => Number(lifetime.find(row => row.fingerprint === fingerprintOf(title))?.events);
  assert.equal(eventsOf('Fresh failure'), 2, 'resends count once in the rollup');
  assert.equal(eventsOf('Returning failure'), 5, 'the rollup keeps earlier occurrences');
  // Older than the flow's day: not in the rollup.
  assert.ok(!lifetime.some(row => row.fingerprint === fingerprintOf('Same instant')));
  const newIssues = await sql(`SELECT fingerprint FROM ${issuesTable} GROUP BY "service", fingerprint ` +
    `HAVING min(first_seen) > now() - INTERVAL '1 day'`);
  // Cases without a timestamp occurred at ingestion, so they are new too.
  const firstSeen = newIssues.map(row => row.fingerprint);
  assert.ok(firstSeen.includes(fingerprintOf('Fresh failure')), 'a first sighting is new');
  assert.ok(!firstSeen.includes(fingerprintOf('Returning failure')), 'an earlier sighting is not new');
  const regressed = await sql(`SELECT fingerprint FROM ${issuesTable} GROUP BY "service", fingerprint ` +
    `HAVING max(last_seen) > now() - INTERVAL '1 day' ` +
    `AND max(CASE WHEN last_seen <= now() - INTERVAL '1 day' THEN last_seen END) < now() - INTERVAL '8 days'`);
  assert.deepEqual(regressed.map(row => row.fingerprint), [fingerprintOf('Returning failure')]);
  console.log(`PASS: ${cases.length} Sentry events grouped like Atlas, ${events.length} scrubbed, resends counted once, and issues rolled up`);
} finally {
  await sql(`DROP FLOW IF EXISTS ${flow}`).catch(() => {});
  await sql(`DROP TABLE IF EXISTS ${issuesTable}`).catch(() => {});
  await sql(`DROP TABLE IF EXISTS ${table}`).catch(() => {});
  await fetch(`${base}/v1/pipelines/${pipelineName}?version=`, { method: 'DELETE', headers: { Authorization: authorization } }).catch(() => {});
}
