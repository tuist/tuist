// Runs inside the cluster. Never print credentials, response bodies or exception details.
import { createHash } from 'node:crypto';

try {
  const base = process.env.OPENOBSERVE_URL;
  const run = process.env.SMOKE_RUN;
  const password = process.env.OPENOBSERVE_PASSWORD?.trim();
  if (!base || !password || !/^[a-zA-Z0-9-]+$/.test(run ?? '')) throw new Error();
  const headers = {
    Authorization: `Basic ${Buffer.from(`openobserve@tuist.dev:${password}`).toString('base64')}`,
    'Content-Type': 'application/json',
    'stream-name': 'ci_smoke',
  };
  const now = Date.now();
  const timestamp = String(BigInt(now) * 1000000n);
  const trace = createHash('sha256').update(run).digest('hex').slice(0, 32);
  const request = async (path, body) => {
    const response = await fetch(`${base}/api/default/${path}`, {
      headers, method: body === undefined ? 'GET' : 'POST',
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(10000),
    });
    if (response.status !== 200) throw new Error();
    const result = await response.json();
    if (result.partialSuccess && Object.values(result.partialSuccess).some(value => value && value !== '0')) throw new Error();
    return result;
  };
  await request('v1/metrics', { resourceMetrics: [{ scopeMetrics: [{ metrics: [{
    name: 'openobserve_ci_value', gauge: { dataPoints: [{ timeUnixNano: timestamp,
      asDouble: 17, attributes: [{ key: 'audit_run', value: { stringValue: run } }],
    }] },
  }] }] }] });
  const logs = await request('ci_smoke/_json', [{ _timestamp: now * 1000, audit_run: run, value: 17 }]);
  if (logs.code !== 200 || !logs.status?.some(item => item.successful === 1 && item.failed === 0)) throw new Error();
  await request('v1/traces', { resourceSpans: [{
    resource: { attributes: [{ key: 'service.name', value: { stringValue: 'openobserve-ci' } }] },
    scopeSpans: [{ spans: [{ traceId: trace, spanId: trace.slice(0, 16), name: run, kind: 1,
      startTimeUnixNano: timestamp, endTimeUnixNano: String(BigInt(timestamp) + 17000000n),
      status: { code: 1 },
    }] }],
  }] });
  const search = (type, sql) => request(`_search?type=${type}`, { query: {
    sql, start_time: (now - 60000) * 1000, end_time: (Date.now() + 60000) * 1000, from: 0, size: 10,
  } });
  const deadline = performance.now() + Number(process.env.SMOKE_TIMEOUT_SECONDS ?? 180) * 1000;
  let qualified = false;
  while (performance.now() < deadline) {
    try {
      const metrics = await request(`prometheus/api/v1/query?${new URLSearchParams({
        query: `openobserve_ci_value{audit_run="${run}"}`, time: String(Date.now() / 1000),
      })}`);
      const logs = await search('logs', `SELECT audit_run, value FROM "ci_smoke" WHERE audit_run = '${run}'`);
      const traces = await search('traces', `SELECT trace_id FROM "ci_smoke" WHERE trace_id = '${trace}'`);
      const samples = metrics.data?.result;
      qualified = metrics.status === 'success' && metrics.data?.resultType === 'vector' && samples?.length === 1 &&
        samples[0].metric?.audit_run === run && Number(samples[0].value?.[1]) === 17 &&
        logs.hits?.length === 1 && logs.hits[0].audit_run === run && logs.hits[0].value === 17 &&
        traces.hits?.length === 1 && traces.hits[0].trace_id === trace;
      if (qualified) break;
    } catch { /* A newly created stream can take time to become queryable. */ }
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  if (!qualified) throw new Error();
  console.log('PASS: authenticated metric value/label, log value and trace identity round trips');
} catch {
  console.error('FAIL: OpenObserve authenticated three-signal round trip');
  process.exitCode = 1;
}
