import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import test from 'node:test';

// Exercise the executable's HTTP contract, not its internal helpers. No cloud calls.
for (const scenario of ['success', 'wrong metric', 'missing trace', 'rejected ingestion', 'partial ingestion']) {
  test(scenario, async () => {
    const seen = [];
    let trace;
    const server = createServer(async (req, res) => {
      try {
        assert.equal(req.headers.authorization, `Basic ${Buffer.from('openobserve@tuist.dev:test-password').toString('base64')}`);
        assert.equal(req.headers['stream-name'], 'ci_smoke');
        const url = new URL(req.url, 'http://localhost');
        seen.push(url.pathname);
        let raw = '';
        for await (const chunk of req) raw += chunk;
        const body = raw ? JSON.parse(raw) : undefined;
        res.setHeader('Content-Type', 'application/json');
        if (url.pathname.endsWith('/v1/metrics')) {
          const metric = body.resourceMetrics[0].scopeMetrics[0].metrics[0];
          assert.equal(metric.name, 'openobserve_ci_value');
          assert.equal(metric.gauge.dataPoints[0].asDouble, 17);
          assert.deepEqual(metric.gauge.dataPoints[0].attributes, [{ key: 'audit_run', value: { stringValue: 'test-run' } }]);
          if (scenario === 'rejected ingestion') {
            res.statusCode = 401;
            return res.end(JSON.stringify({ secret: 'MUST-NOT-LOG' }));
          }
          return res.end(JSON.stringify(scenario === 'partial ingestion' ? { partialSuccess: { rejectedDataPoints: '1' } } : {}));
        }
        if (url.pathname.endsWith('/ci_smoke/_json')) {
          assert.equal(body[0].audit_run, 'test-run');
          assert.equal(body[0].value, 17);
          return res.end(JSON.stringify({ code: 200, status: [{ name: 'ci_smoke', successful: 1, failed: 0 }] }));
        }
        if (url.pathname.endsWith('/v1/traces')) {
          const span = body.resourceSpans[0].scopeSpans[0].spans[0];
          assert.equal(span.name, 'test-run');
          assert.equal(BigInt(span.endTimeUnixNano) - BigInt(span.startTimeUnixNano), 17000000n);
          trace = span.traceId;
          return res.end('{}');
        }
        if (url.pathname.endsWith('/api/v1/query')) {
          assert.equal(url.searchParams.get('query'), 'openobserve_ci_value{audit_run="test-run"}');
          return res.end(JSON.stringify({ status: 'success', data: { resultType: 'vector', result: [{
            metric: { audit_run: 'test-run' }, value: [Date.now() / 1000, scenario === 'wrong metric' ? '19' : '17'],
          }] } }));
        }
        assert.equal(url.pathname, '/api/default/_search');
        assert.ok(body.query.start_time < body.query.end_time);
        if (url.searchParams.get('type') === 'logs') {
          assert.match(body.query.sql, /WHERE audit_run = 'test-run'/);
          return res.end(JSON.stringify({ hits: [{ audit_run: 'test-run', value: 17 }] }));
        }
        assert.equal(url.searchParams.get('type'), 'traces');
        assert.ok(body.query.sql.includes(trace));
        res.end(JSON.stringify({ hits: scenario === 'missing trace' ? [] : [{ trace_id: trace }] }));
      } catch (error) {
        res.statusCode = 500;
        res.end('{}');
        server.emit('test-error', error);
      }
    });
    const errors = [];
    server.on('test-error', error => errors.push(error));
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    try {
      const child = spawn(process.execPath, ['.github/scripts/openobserve-smoke.mjs'], { env: {
        ...process.env, OPENOBSERVE_URL: `http://127.0.0.1:${server.address().port}`,
        OPENOBSERVE_PASSWORD: 'test-password\n', SMOKE_RUN: 'test-run', SMOKE_TIMEOUT_SECONDS: '1',
      } });
      let output = '';
      child.stdout.on('data', chunk => { output += chunk; });
      child.stderr.on('data', chunk => { output += chunk; });
      const code = await new Promise(resolve => child.on('close', resolve));
      assert.deepEqual(errors, []);
      assert.equal(code, scenario === 'success' ? 0 : 1, output);
      assert.ok(!output.includes('test-password') && !output.includes('MUST-NOT-LOG'));
      if (scenario === 'success') assert.equal(seen.length, 6);
      if (scenario.includes('ingestion')) assert.equal(seen.length, 1);
    } finally {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
    }
  });
}
