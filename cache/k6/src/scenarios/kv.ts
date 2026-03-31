import http from 'k6/http';
import { SetupData } from '../types.ts';
import { KV_DISTRIBUTIONS, RUN_ID } from '../config.ts';
import { authHeaders, cacheUrl } from '../lib/http.ts';
import { randomItem, randomString } from '../lib/util.ts';
import { record } from '../metrics.ts';

export function keyValueRead(data: SetupData): void {
  const token = data.token;
  const casId = randomItem(data.kvDirect);
  const start = Date.now();
  const res = http.get(cacheUrl(`/api/cache/keyvalue/${casId}`), { headers: authHeaders(token) });

  record('key_value_read', Date.now() - start, res.status === 200);
}

export function keyValueWrite(data: SetupData): void {
  const token = data.token;
  const casId = `${RUN_ID}-kv-${Date.now()}-${Math.floor(Math.random() * 100000)}`;
  const dist = KV_DISTRIBUTIONS[Math.floor(Math.random() * KV_DISTRIBUTIONS.length)];
  const entries = Array.from({ length: dist.entries }, () => ({
    value: randomString(dist.valueSize),
  }));

  const start = Date.now();
  const res = http.put(
    cacheUrl('/api/cache/keyvalue'),
    JSON.stringify({ cas_id: casId, entries }),
    { headers: { ...authHeaders(token), 'Content-Type': 'application/json' } },
  );

  record('key_value_write', Date.now() - start, res.status === 204);
}
