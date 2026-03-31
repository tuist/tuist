import http from 'k6/http';
import { SetupData } from '../types.ts';
import { LARGE_SIZES, RUN_ID } from '../config.ts';
import { authHeaders, cacheUrl } from '../lib/http.ts';
import { weightedRandom, randomItem, randomId } from '../lib/util.ts';
import { record } from '../metrics.ts';
import { getPayload } from '../payloads.ts';

export function gradleRead(data: SetupData): void {
  const token = data.token;
  const bucket = weightedRandom(LARGE_SIZES);
  const seeded = data.gradle[bucket.name];
  if (!seeded || seeded.keys.length === 0) return;

  const key = randomItem(seeded.keys);
  const start = Date.now();
  const res = http.get(
    cacheUrl(`/api/cache/gradle/${key}`),
    { headers: authHeaders(token), timeout: '120s' },
  );

  record(`gradle_read_${bucket.name}`, Date.now() - start, res.status === 200);
}

export function gradleWrite(data: SetupData): void {
  const token = data.token;
  const bucket = weightedRandom(LARGE_SIZES);
  const key = `${RUN_ID}-gradlew-${randomId()}`;
  const payload = getPayload(bucket.name);

  const start = Date.now();
  const res = http.put(
    cacheUrl(`/api/cache/gradle/${key}`),
    payload,
    {
      headers: { ...authHeaders(token), 'Content-Type': 'application/octet-stream' },
      timeout: '120s',
    },
  );

  record(`gradle_write_${bucket.name}`, Date.now() - start, res.status === 200 || res.status === 201);
}
