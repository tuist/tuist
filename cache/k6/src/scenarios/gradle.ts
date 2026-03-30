import http from 'k6/http';
import { SetupData } from '../types.ts';
import { LARGE_SIZES, RUN_ID } from '../config.ts';
import { authHeaders, cacheUrl } from '../lib/http.ts';
import { weightedRandom, randomItem, randomId } from '../lib/util.ts';
import { record } from '../metrics.ts';
import { getPayload } from '../payloads.ts';

export function gradleRead(data: SetupData): void {
  var token = data.token;
  var bucket = weightedRandom(LARGE_SIZES);
  var seeded = data.gradle[bucket.name];
  if (!seeded || seeded.keys.length === 0) return;

  var key = randomItem(seeded.keys);
  var start = Date.now();

  var res = http.get(
    cacheUrl('/api/cache/gradle/' + key),
    {
      headers: authHeaders(token),
      timeout: '120s',
    }
  );

  var duration = Date.now() - start;
  record('gradle_read_' + bucket.name, duration, res.status === 200);
}

export function gradleWrite(data: SetupData): void {
  var token = data.token;
  var bucket = weightedRandom(LARGE_SIZES);
  var key = RUN_ID + '-gradlew-' + randomId();
  var payload = getPayload(bucket.name);

  var start = Date.now();

  var res = http.put(
    cacheUrl('/api/cache/gradle/' + key),
    payload,
    {
      headers: Object.assign({}, authHeaders(token), { 'Content-Type': 'application/octet-stream' }),
      timeout: '120s',
    }
  );

  var duration = Date.now() - start;
  record('gradle_write_' + bucket.name, duration, res.status === 200 || res.status === 201);
}
