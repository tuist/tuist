import http from 'k6/http';
import { SetupData } from '../types.ts';
import { RUN_ID } from '../config.ts';
import { authHeaders, cacheUrl } from '../lib/http.ts';
import { randomItem, randomId } from '../lib/util.ts';
import { record } from '../metrics.ts';
import { getPayload } from '../payloads.ts';

function gradleReadBucket(data: SetupData, bucketName: string): void {
  const token = data.token;
  const seeded = data.gradle[bucketName];
  if (!seeded || seeded.keys.length === 0) return;

  const key = randomItem(seeded.keys);
  const start = Date.now();
  const res = http.get(
    cacheUrl(`/api/cache/gradle/${key}`),
    { headers: authHeaders(token), timeout: '120s' },
  );

  record(`gradle_read_${bucketName}`, Date.now() - start, res.status === 200);
}

function gradleWriteBucket(data: SetupData, bucketName: string): void {
  const token = data.token;
  const key = `${RUN_ID}-gradlew-${randomId()}`;
  const payload = getPayload(bucketName);

  const start = Date.now();
  const res = http.put(
    cacheUrl(`/api/cache/gradle/${key}`),
    payload,
    {
      headers: { ...authHeaders(token), 'Content-Type': 'application/octet-stream' },
      timeout: '120s',
    },
  );

  record(`gradle_write_${bucketName}`, Date.now() - start, res.status === 200 || res.status === 201);
}

export function gradleRead5mb(data: SetupData): void {
  gradleReadBucket(data, '5mb');
}

export function gradleRead10mb(data: SetupData): void {
  gradleReadBucket(data, '10mb');
}

export function gradleRead25mb(data: SetupData): void {
  gradleReadBucket(data, '25mb');
}

export function gradleWrite5mb(data: SetupData): void {
  gradleWriteBucket(data, '5mb');
}

export function gradleWrite10mb(data: SetupData): void {
  gradleWriteBucket(data, '10mb');
}

export function gradleWrite25mb(data: SetupData): void {
  gradleWriteBucket(data, '25mb');
}
