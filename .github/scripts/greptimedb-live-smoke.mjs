// CI pod only: count real recent telemetry, never print response bodies or tokens.
import { readFileSync } from 'node:fs';
try {
  const token = readFileSync(process.env.GREPTIMEDB_DASHBOARD_AUTH_FILE, 'utf8').match(/^dashboard:ro=(.+)$/m)?.[1];
  if (!token) throw new Error();
  const base = process.env.GREPTIMEDB_URL;
  const headers = {Authorization: `Basic ${Buffer.from(`dashboard:${token}`).toString('base64')}`, 'X-Greptime-DB-Name': 'public'};
  const deadline = Date.now() + 300000;
  const since = new Date(Date.now() - 600000).toISOString();
  const get = async path => {
    const response = await fetch(`${base}${path}`, {headers, signal: AbortSignal.timeout(10000)});
    if (response.status !== 200) throw new Error();
    return response.json();
  };
  let qualified = false;
  while (Date.now() < deadline) {
    try {
      const metrics = await get(`/v1/prometheus/api/v1/query?${new URLSearchParams({query: 'kube_pod_info'})}`);
      const counts = [];
      for (const sql of [
        `SELECT COUNT(*) FROM opentelemetry_logs WHERE timestamp >= '${since}' AND COALESCE(json_get_string(resource_attributes, '["service.name"]'), '') != 'greptimedb-ci'`,
        `SELECT COUNT(*) FROM opentelemetry_traces WHERE timestamp >= '${since}' AND service_name != 'greptimedb-ci'`,
      ]) {
        const result = await get(`/v1/sql?${new URLSearchParams({sql})}`);
        counts.push(Number(result.output?.[0]?.records?.rows?.[0]?.[0] ?? 0));
      }
      qualified = metrics.status === 'success' && metrics.data?.result?.some(item => Number(item.value?.[1]) > 0) && counts.every(count => count > 0);
      if (qualified) break;
    } catch { /* A new table or idle workload must not silently pass. */ }
    await new Promise(resolve => setTimeout(resolve, 5000));
  }
  if (!qualified) throw new Error();
  console.log('PASS: real Kubernetes metrics, non-CI logs and non-CI traces present in recent window after collector rollout');
} catch {
  console.error('FAIL: recent real telemetry absent or unreadable; generate real workload traffic and investigate before promotion');
  process.exitCode = 1;
}
