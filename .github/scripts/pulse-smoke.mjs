// Synthetic OTLP/HTTP protobuf round trips. Credentials and bodies never enter logs.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

// Minimal OTLP wire encoding, limited to length-delimited and fixed64 fields.
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
function fixed(field, value, double = false) {
  const body = Buffer.alloc(8);
  if (double) body.writeDoubleLE(value); else body.writeBigUInt64LE(value);
  return concat(varint(field * 8 + 1), body);
}
const attribute = (key, value) => concat(message(1, key), message(2, message(1, value)));
// Valid raw Snappy block using a single literal (no compression dependency).
function snappy(body) {
  const length = body.length - 1;
  if (length < 60) return concat(varint(body.length), Buffer.from([length << 2]), body);
  const bytes = [];
  let remaining = length;
  do { bytes.push(remaining & 255); remaining >>>= 8; } while (remaining);
  return concat(varint(body.length), Buffer.from([(59 + bytes.length) << 2, ...bytes]), body);
}

let phase = 'configuration';
// Each phase is printed as it starts, so a probe that outlives its deadline
// still shows where it stopped. Only fixed names, never response bodies.
const started = performance.now();
const elapsed = () => `${Math.round((performance.now() - started) / 1000)}s`;
const enter = name => { phase = name; console.log(`${elapsed()}: ${name}`); };
try {
  const base = process.env.PULSE_URL;
  const run = process.env.SMOKE_RUN;
  const environment = process.env.DEPLOY_ENV;
  const ingest = process.env.PULSE_INGEST_URL;
  if (!['staging', 'canary', 'production'].includes(environment)) throw new Error();
  const ttl = environment === 'production' ? 'forever' : '7d';
  // Errors carry more personal data than other telemetry: 90 days in
  // production, matching Atlas's errors_events.
  const errorsTtl = environment === 'production' ? '90d' : '7d';
  const password = readFileSync(process.env.PULSE_AUTH_FILE, 'utf8').trim().replace(/^pilot=/, '');
  if (!base || !password || !/^[a-zA-Z0-9-]+$/.test(run ?? '')) throw new Error();
  const headers = {
    Authorization: `Basic ${Buffer.from(`pilot:${password}`).toString('base64')}`,
    'X-Pulse-DB-Name': 'public',
  };
  const request = async (path, body, extra = {}) => {
    const response = await fetch(`${base}${path}`, {
      headers: { ...headers, ...extra }, method: body === undefined ? 'GET' : 'POST', body,
      signal: AbortSignal.timeout(10000),
    });
    if (response.status !== 200) throw new Error();
    return response;
  };
  const sqlResult = async query => {
    const response = await request(`/v1/sql?${new URLSearchParams({ sql: query })}`);
    const result = await response.json();
    if (result.code !== undefined && result.code !== 0) throw new Error();
    if (!result.output) throw new Error();
    return result;
  };
  // Production keeps its data indefinitely; staging and canary keep 7 days.
  // Never mistake HTTP 200 for SQL success or impose the trial TTL on production.
  enter('database TTL');
  if (process.env.SMOKE_READ_ONLY !== 'true') await sqlResult(`ALTER DATABASE public SET 'ttl' = '${ttl}'`);
  const database = await sqlResult('SHOW CREATE DATABASE public');
  const ddl = database.output[0]?.records?.rows?.[0]?.[1];
  const expected = ttl === 'forever' ? /ttl\s*=\s*'forever'/i : /ttl\s*=\s*'7(?:d|days)'/i;
  if (typeof ddl !== 'string' || !expected.test(ddl)) throw new Error();
  let writerAuthorization;
  let readerAuthorization;
  if (process.env.PULSE_DASHBOARD_AUTH_FILE) {
    enter('scoped identities');
    const provider = readFileSync(process.env.PULSE_DASHBOARD_AUTH_FILE, 'utf8');
    const token = provider.match(/^dashboard:ro=(.+)$/m)?.[1];
    if (!token || !provider.includes(`tuist:wo=${token}\n`)) throw new Error();
    writerAuthorization = `Basic ${Buffer.from(`tuist:${token}`).toString('base64')}`;
    readerAuthorization = `Basic ${Buffer.from(`dashboard:${token}`).toString('base64')}`;
    const scoped = async (username, query) => {
      const response = await fetch(`${base}/v1/sql?${new URLSearchParams({ sql: query })}`, {
        headers: { ...headers, Authorization: `Basic ${Buffer.from(`${username}:${token}`).toString('base64')}` },
        signal: AbortSignal.timeout(10000),
      });
      const result = await response.json().catch(() => ({}));
      return { status: response.status, result };
    };
    const select = await scoped('dashboard', 'SELECT 1');
    if (select.status !== 200 || select.result.output?.[0]?.records?.rows?.[0]?.[0] !== 1) throw new Error();
    // Idempotent, non-destructive mutation: if authorization regresses, fail
    // without changing retention or creating a disposable application table.
    const mutation = await scoped('dashboard', `ALTER DATABASE public SET 'ttl' = '${ttl}'`);
    const read = await scoped('tuist', 'SELECT 1');
    for (const denied of [mutation, read]) {
      if (denied.status !== 403) throw new Error();
    }
  }
  const trace = createHash('sha256').update(run).digest('hex').slice(0, 32);
  const timestamp = BigInt(Date.now()) * 1000000n;
  if (process.env.SMOKE_READ_ONLY !== 'true') {
    // HTTP 200 with a protobuf partial_success body must not count as accepted.
    const write = async (signal, body, extra, legacyPath) => {
      enter(`OTLP ${signal}`);
      const response = await fetch(ingest ? `${ingest}${legacyPath}` : `${base}/v1/otlp/v1/${signal}`, {
        method: 'POST', body, signal: AbortSignal.timeout(10000),
        headers: { ...headers, 'Content-Type': 'application/x-protobuf', ...extra,
          ...(ingest ? { 'X-Pulse-DB-Name': 'forbidden',
            'X-Pulse-Log-Table-Name': 'forbidden',
            'X-Pulse-Pipeline-Name': 'forbidden',
            'X-Pulse-Pipeline-Version': 'forbidden',
            'X-Pulse-Pipeline-Params': 'forbidden' } : {}),
          ...(writerAuthorization ? { Authorization: writerAuthorization } : {}) },
      });
      if (![200, 204].includes(response.status)) throw new Error();
      // OTLP rejects partial_success rather than silently accepting partial loss.
      if ((!ingest || signal === 'traces') && (await response.arrayBuffer()).byteLength !== 0) throw new Error();
    };
    // ExportMetricsRequest.resource_metrics.scope_metrics.metrics.gauge.data_points
    const point = concat(fixed(3, timestamp), fixed(4, 17, true), message(7, attribute('audit_run', run)));
    const metric = concat(message(1, 'pulse_ci_value'), message(5, message(1, point)));
    if (ingest) {
      const label = (name, value) => message(1, concat(message(1, name), message(2, value)));
      const sample = concat(fixed(1, 17, true), Buffer.from([0x10]), varint(timestamp / 1000000n));
      const series = concat(label('__name__', 'pulse_ci_value'), label('audit_run', run), message(2, sample));
      await write('metrics', snappy(message(1, series)), {
        'Content-Encoding': 'snappy', 'X-Prometheus-Remote-Write-Version': '0.1.0',
      }, '/api/v1/write');
    } else await write('metrics', message(1, message(2, message(2, metric))));
    // ExportLogsRequest.resource_logs.scope_logs.log_records
    const resource = message(1, attribute('service.name', 'pulse-ci'));
    const log = concat(fixed(1, timestamp), message(3, 'ERROR'), message(5, message(1, run)), message(9, Buffer.from(trace, 'hex')));
    if (ingest) {
      await write('logs', JSON.stringify({ streams: [{
        stream: {service_name: 'pulse-ci', level: 'error', audit_run: run},
        values: [[timestamp.toString(), run, {trace_id: trace}]],
      }] }), {'Content-Type': 'application/json'}, '/loki/api/v1/push');
      // Collector transport: Loki PushRequest with raw Snappy protobuf and
      // structured metadata, not just the public JSON convenience encoding.
      const seconds = timestamp / 1000000000n;
      const nanos = timestamp % 1000000000n + 1n;
      const time = concat(Buffer.from([0x08]), varint(seconds), Buffer.from([0x10]), varint(nanos));
      const metadata = concat(message(1, 'trace_id'), message(2, trace));
      const entry = concat(message(1, time), message(2, `${run}-pb`), message(3, metadata));
      const stream = concat(message(1, `{service_name="pulse-ci",level="error",audit_run="${run}"}`), message(2, entry));
      await write('logs', snappy(message(1, stream)), {'Content-Encoding': 'snappy'}, '/loki/api/v1/push');
    } else {
      await write('logs', message(1, concat(message(1, resource), message(2, message(2, log)))));
      // Native OTLP creates the canonical fulltext/scope schema FIRST.
      enter('Loki pipeline installation');
      const pipeline = process.env.PULSE_LOKI_PIPELINE;
      if (!pipeline) throw new Error();
      await request('/v1/pipelines/loki_otlp', pipeline, {'Content-Type': 'application/x-yaml'});
      // Errors: the table first, so the pipeline writes into its primary key and
      // retention, then the issue rollup and its flow, then one synthetic Sentry
      // event through the writer identity. Tables created before append mode
      // get it here: distinct events at one timestamp would otherwise merge.
      enter('errors table and pipeline');
      const errorsTable = process.env.PULSE_ERRORS_TABLE;
      const errorsPipeline = process.env.PULSE_ERRORS_PIPELINE;
      const errorIssues = process.env.PULSE_ERROR_ISSUES;
      if (!errorsTable || !errorsPipeline || !errorIssues) throw new Error();
      await sqlResult(errorsTable);
      await sqlResult(`ALTER TABLE errors SET 'append_mode' = 'true'`);
      await sqlResult(`ALTER TABLE errors SET 'ttl' = '${errorsTtl}'`);
      for (const statement of errorIssues.split(/;\s*$/m).filter(text => text.replace(/--.*$/gm, '').trim())) {
        await sqlResult(statement);
      }
      await request('/v1/pipelines/sentry_errors', errorsPipeline, {'Content-Type': 'application/x-yaml'});
      // Release health from Sentry sessions, kept as long as errors. Pulse
      // writes sessions only into this table, never one it creates itself.
      enter('sessions table');
      const sessionsTable = process.env.PULSE_SESSIONS_TABLE;
      if (!sessionsTable) throw new Error();
      await sqlResult(sessionsTable);
      await sqlResult(`ALTER TABLE sessions ADD COLUMN IF NOT EXISTS seq BIGINT UNSIGNED`);
      await sqlResult(`ALTER TABLE sessions ADD COLUMN IF NOT EXISTS updated TIMESTAMP(9)`);
      await sqlResult(`ALTER TABLE sessions SET 'append_mode' = 'true'`);
      await sqlResult(`ALTER TABLE sessions SET 'ttl' = '${errorsTtl}'`);
      enter('errors ingestion');
      const error = await fetch(`${base}/v1/ingest?${new URLSearchParams({db: 'public', table: 'errors', pipeline_name: 'sentry_errors'})}`, {
        method: 'POST', signal: AbortSignal.timeout(10000),
        headers: { ...headers, 'Content-Type': 'application/json', ...(writerAuthorization ? { Authorization: writerAuthorization } : {}) },
        body: JSON.stringify([{service: 'pulse-ci', event: {
          event_id: trace, timestamp: Number(timestamp / 1000n) / 1e6, level: 'error', message: run,
        }}]),
      });
      if (error.status !== 200) throw new Error();
      // Recompute retained hours, even after flow replacement, through the
      // same execution lock as live evaluations. Concurrent arrivals stay dirty.
      enter('error issues recovery');
      await sqlResult(`ADMIN flush_flow('error_issues', true)`);
    }
    // ExportTraceRequest.resource_spans.scope_spans.spans, including an error status.
    const span = concat(message(1, Buffer.from(trace, 'hex')), message(2, Buffer.from(trace.slice(0, 16), 'hex')),
      message(5, run), fixed(7, timestamp), fixed(8, timestamp + 17000000n), message(15, Buffer.from([0x18, 2])));
    await write('traces', message(1, concat(message(1, resource), message(2, message(2, span)))), {
      'X-Pulse-Pipeline-Name': 'pulse_trace_v1',
    }, '/v1/traces');
    if (!ingest) {
      // Symptoms inputs: columns, Flows and tables over the log and trace
      // tables, which now exist (infra/helm/pulse/symptoms.sql). Idempotent.
      phase = 'Symptoms inputs';
      const symptoms = process.env.PULSE_SYMPTOMS_SQL;
      if (!symptoms) throw new Error();
      const statements = symptoms.split(/;\s*$/m)
        .map(statement => statement.replace(/^\s*--.*$/gm, '').trim()).filter(Boolean);
      for (const statement of statements) await sqlResult(statement);
      const expected = statements.map(statement => statement.match(/^CREATE FLOW IF NOT EXISTS (\S+)/)?.[1]).filter(Boolean);
      const created = (await sqlResult('SHOW FLOWS')).output[0]?.records?.rows?.map(row => row[0]) ?? [];
      if (expected.length === 0 || !expected.every(flow => created.includes(flow))) throw new Error();
    }
  }
  if (readerAuthorization) headers.Authorization = readerAuthorization;
  enter('authentication boundary');
  const anonymous = await fetch(`${base}/v1/sql?sql=SELECT%201`, { signal: AbortSignal.timeout(10000) });
  if (anonymous.status !== 401) throw new Error();
  if (ingest) {
    for (const path of ['/api/v1/write', '/loki/api/v1/push', '/v1/traces']) {
      const response = await fetch(`${ingest}${path}`, {method: 'POST', body: '', signal: AbortSignal.timeout(10000)});
      if (response.status !== 401) throw new Error();
      const selection = await fetch(`${ingest}${path}?db=other&table=other`, {
        method: 'POST', body: '', headers, signal: AbortSignal.timeout(10000),
      });
      if (selection.status !== 400) throw new Error();
    }
    for (const path of ['/v1/sql?sql=SELECT%201', '/v1/pipelines/loki_otlp', '/mcp', '/api/v1/query']) {
      const response = await fetch(`${ingest}${path}`, {headers, signal: AbortSignal.timeout(10000)});
      if (response.status !== 404) throw new Error();
    }
  }
  enter('query results');
  const sql = async query => {
    const response = await request(`/v1/sql?${new URLSearchParams({ sql: query })}`);
    const result = await response.json();
    return result.output?.[0]?.records?.rows;
  };
  // Like the metric query's [1h]: production's log table takes tens of
  // millions of rows a day, and an unbounded lookup outlasts the frontend's
  // 30s HTTP timeout. The reread follows within the same deploy.
  const recent = "timestamp > now() - INTERVAL '1 hour'";
  const deadline = performance.now() + Number(process.env.SMOKE_TIMEOUT_SECONDS ?? 120) * 1000;
  let qualified = false;
  let waiting = [];
  let reported = performance.now();
  while (performance.now() < deadline) {
    try {
      const metrics = await (await request(`/v1/prometheus/api/v1/query?${new URLSearchParams({
        // A plain selector only looks back 5 minutes, and the reread follows a
        // drained datanode restart that can take longer than that.
        query: `last_over_time(pulse_ci_value{audit_run="${run}"}[1h])`,
      })}`)).json();
      const logs = await sql(`SELECT body, severity_text, timestamp, resource_attributes, trace_id FROM opentelemetry_logs WHERE body = '${run}' AND ${recent}`);
      const traces = await sql(`SELECT trace_id, span_name, span_status_code, timestamp, service_name, duration_nano FROM opentelemetry_traces WHERE trace_id = '${trace}' AND ${recent}`);
      const protobufLogs = ingest ? await sql(`SELECT body, severity_text, trace_id, resource_attributes FROM opentelemetry_logs WHERE body = '${run}-pb' AND ${recent}`) : null;
      const errors = ingest ? null : await sql(`SELECT title, "level", fingerprint, service FROM errors WHERE event_id = '${trace}'`);
      const errorsDdl = ingest ? null : (await sql('SHOW CREATE TABLE errors'))?.[0]?.[1];
      // Every smoke run's message normalizes to the same issue, so earlier runs
      // in the same hour count too.
      const issueHours = ingest || errors?.length !== 1 ? null :
        await sql(`SELECT events FROM error_issue_hours WHERE "service" = 'pulse-ci' AND fingerprint = '${errors[0][2]}' AND last_seen > now() - INTERVAL '1 hour'`);
      const sessionsDdl = ingest ? null : (await sql('SHOW CREATE TABLE sessions'))?.[0]?.[1];
      const errorsRetention = errorsTtl === '90d' ? /ttl\s*=\s*'(?:90d|90days|2months 29days 2h 52m 48s)'/ : /ttl\s*=\s*'7(?:d|days)'/;
      const checks = {
        metrics: metrics.status === 'success' && metrics.data?.resultType === 'vector' &&
          metrics.data.result.length === 1 && metrics.data.result[0].metric.audit_run === run &&
          Number(metrics.data.result[0].value[1]) === 17,
        logs: logs?.length === 1 && logs[0][0] === run && logs[0][1] === 'ERROR' &&
          logs[0][2] != null && logs[0][3]?.['service.name'] === 'pulse-ci' && logs[0][4] === trace,
        traces: traces?.length === 1 && traces[0][0] === trace && traces[0][1] === run && traces[0][2] === 'STATUS_CODE_ERROR' &&
          traces[0][3] != null && traces[0][4] === 'pulse-ci' && Number(traces[0][5]) === 17000000,
        'protobuf logs': !ingest || (protobufLogs?.length === 1 && protobufLogs[0][1] === 'ERROR' && protobufLogs[0][2] === trace &&
          protobufLogs[0][3]?.['service.name'] === 'pulse-ci'),
        errors: ingest || (errors?.length === 1 && errors[0][0] === run && errors[0][1] === 'error' &&
          /^[0-9a-f]{64}$/.test(errors[0][2]) && errors[0][3] === 'pulse-ci' &&
          typeof errorsDdl === 'string' && errorsRetention.test(errorsDdl) && /append_mode\s*=\s*'true'/.test(errorsDdl)),
        'error issues': ingest || (issueHours?.length >= 1 && issueHours.every(row => Number(row[0]) >= 1)),
        sessions: ingest || (typeof sessionsDdl === 'string' && errorsRetention.test(sessionsDdl)),
      };
      waiting = Object.keys(checks).filter(name => !checks[name]);
      qualified = waiting.length === 0;
      if (qualified) break;
    } catch {
      // Newly created tables can take time to become queryable.
      waiting = ['readable responses'];
    }
    if (performance.now() - reported >= 15000) {
      reported = performance.now();
      console.log(`${elapsed()}: still waiting for ${waiting.join(', ')}`);
    }
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  if (!qualified) {
    phase = `query results, missing ${waiting.join(', ')}`;
    throw new Error();
  }
  console.log(`${elapsed()}: PASS: ${environment} database TTL ${ttl}; configured scoped identities; authenticated PromQL value/label, error log, trace and Sentry error (TTL ${errorsTtl}, append-only) identity and issue rollup; sessions table (TTL ${errorsTtl}); anonymous SQL rejected`);
} catch {
  console.error(`FAIL: Pulse pilot (${phase})`);
  process.exitCode = 1;
}
