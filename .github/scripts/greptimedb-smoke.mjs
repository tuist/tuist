// Synthetic OTLP/HTTP protobuf round trips. Credentials and bodies never enter logs.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

// Minimal OTLP wire encoding, limited to length-delimited and fixed64 fields.
const concat = (...parts) => Buffer.concat(parts);
function varint(value) {
  const bytes = [];
  do { bytes.push((value & 127) | (value > 127 ? 128 : 0)); value >>>= 7; } while (value);
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

let phase = 'configuration';
try {
  const base = process.env.GREPTIMEDB_URL;
  const run = process.env.SMOKE_RUN;
  const password = readFileSync(process.env.GREPTIMEDB_AUTH_FILE, 'utf8').trim().replace(/^pilot=/, '');
  if (!base || !password || !/^[a-zA-Z0-9-]+$/.test(run ?? '')) throw new Error();
  const headers = {
    Authorization: `Basic ${Buffer.from(`pilot:${password}`).toString('base64')}`,
    'X-Greptime-DB-Name': 'public',
  };
  const request = async (path, body, extra = {}) => {
    const response = await fetch(`${base}${path}`, {
      headers: { ...headers, ...extra }, method: body === undefined ? 'GET' : 'POST', body,
      signal: AbortSignal.timeout(10000),
    });
    if (response.status !== 200) throw new Error();
    return response;
  };
  const trace = createHash('sha256').update(run).digest('hex').slice(0, 32);
  const timestamp = BigInt(Date.now()) * 1000000n;
  if (process.env.SMOKE_READ_ONLY !== 'true') {
    // HTTP 200 with a protobuf partial_success body must not count as accepted.
    const write = async (signal, body, extra) => {
      phase = `OTLP ${signal}`;
      const response = await request(`/v1/otlp/v1/${signal}`, body, { 'Content-Type': 'application/x-protobuf', ...extra });
      if ((await response.arrayBuffer()).byteLength !== 0) throw new Error();
    };
    // ExportMetricsRequest.resource_metrics.scope_metrics.metrics.gauge.data_points
    const point = concat(fixed(3, timestamp), fixed(4, 17, true), message(7, attribute('audit_run', run)));
    const metric = concat(message(1, 'greptimedb_ci_value'), message(5, message(1, point)));
    await write('metrics', message(1, message(2, message(2, metric))));
    // ExportLogsRequest.resource_logs.scope_logs.log_records
    const log = concat(fixed(1, timestamp), message(3, 'ERROR'), message(5, message(1, run)));
    await write('logs', message(1, message(2, message(2, log))));
    // ExportTraceRequest.resource_spans.scope_spans.spans, including an error status.
    const span = concat(message(1, Buffer.from(trace, 'hex')), message(2, Buffer.from(trace.slice(0, 16), 'hex')),
      message(5, run), fixed(7, timestamp), fixed(8, timestamp + 17000000n), message(15, Buffer.from([0x18, 2])));
    const resource = message(1, attribute('service.name', 'greptimedb-ci'));
    await write('traces', message(1, concat(message(1, resource), message(2, message(2, span)))), {
      'X-Greptime-Pipeline-Name': 'greptime_trace_v1',
    });
  }
  phase = 'authentication boundary';
  const anonymous = await fetch(`${base}/v1/sql?sql=SELECT%201`, { signal: AbortSignal.timeout(10000) });
  if (anonymous.status !== 401) throw new Error();
  phase = 'query results';
  const sql = async query => {
    const response = await request(`/v1/sql?${new URLSearchParams({ sql: query })}`);
    const result = await response.json();
    return result.output?.[0]?.records?.rows;
  };
  const deadline = performance.now() + Number(process.env.SMOKE_TIMEOUT_SECONDS ?? 120) * 1000;
  let qualified = false;
  while (performance.now() < deadline) {
    try {
      const metrics = await (await request(`/v1/prometheus/api/v1/query?${new URLSearchParams({
        query: `greptimedb_ci_value{audit_run="${run}"}`,
      })}`)).json();
      const logs = await sql(`SELECT body, severity_text FROM opentelemetry_logs WHERE body = '${run}'`);
      const traces = await sql(`SELECT trace_id, span_name, span_status_code FROM opentelemetry_traces WHERE trace_id = '${trace}'`);
      qualified = metrics.status === 'success' && metrics.data?.resultType === 'vector' &&
        metrics.data.result.length === 1 && metrics.data.result[0].metric.audit_run === run &&
        Number(metrics.data.result[0].value[1]) === 17 &&
        logs?.length === 1 && logs[0][0] === run && logs[0][1] === 'ERROR' &&
        traces?.length === 1 && traces[0][0] === trace && traces[0][1] === run && traces[0][2] === 'STATUS_CODE_ERROR';
      if (qualified) break;
    } catch { /* Newly created tables can take time to become queryable. */ }
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  if (!qualified) throw new Error();
  console.log('PASS: authenticated PromQL value/label, error log and trace identity; anonymous SQL rejected');
} catch {
  console.error(`FAIL: GreptimeDB pilot (${phase})`);
  process.exitCode = 1;
}
