import http from 'k6/http';
import { SetupData } from '../types.ts';
import { KV_DISTRIBUTIONS, RUN_ID } from '../config.ts';
import { authHeaders, cacheUrl } from '../lib/http.ts';
import { randomItem, randomString } from '../lib/util.ts';
import { record } from '../metrics.ts';

export function keyValueRead(data: SetupData): void {
  var casId = randomItem(data.kvDirect);
  var start = Date.now();
  var res = http.get(cacheUrl('/api/cache/keyvalue/' + casId), { headers: authHeaders(data.token) });
  var duration = Date.now() - start;
  record('key_value_read', duration, res.status === 200);
}

export function keyValueWrite(data: SetupData): void {
  var casId = RUN_ID + '-kv-' + Date.now() + '-' + Math.floor(Math.random() * 100000);
  var dist = KV_DISTRIBUTIONS[Math.floor(Math.random() * KV_DISTRIBUTIONS.length)];
  var entries: Array<{ value: string }> = [];
  for (var i = 0; i < dist.entries; i++) {
    entries.push({ value: randomString(dist.valueSize) });
  }

  var start = Date.now();
  var res = http.put(
    cacheUrl('/api/cache/keyvalue'),
    JSON.stringify({ cas_id: casId, entries: entries }),
    { headers: Object.assign({}, authHeaders(data.token), { 'Content-Type': 'application/json' }) }
  );
  var duration = Date.now() - start;
  record('key_value_write', duration, res.status === 204);
}
