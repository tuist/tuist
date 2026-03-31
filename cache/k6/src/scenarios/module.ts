import http from 'k6/http';
import { SetupData } from '../types.ts';
import { LARGE_SIZES, MODULE_PART_SIZE, RUN_ID } from '../config.ts';
import { authHeaders, cacheUrl } from '../lib/http.ts';
import { weightedRandom, randomItem, randomId } from '../lib/util.ts';
import { record } from '../metrics.ts';
import { getModulePartPayload } from '../payloads.ts';

export function moduleExists(data: SetupData): void {
  const token = data.token;
  const bucket = weightedRandom(LARGE_SIZES);
  const seeded = data.module[bucket.name];
  if (!seeded || seeded.refs.length === 0) return;

  const ref = randomItem(seeded.refs);
  const start = Date.now();
  const res = http.head(
    cacheUrl(`/api/cache/module/${ref.hash}`, { hash: ref.hash, name: ref.name }),
    { headers: authHeaders(token) },
  );

  record(`module_exists_${bucket.name}`, Date.now() - start, res.status === 204);
}

export function moduleRead(data: SetupData): void {
  const token = data.token;
  const bucket = weightedRandom(LARGE_SIZES);
  const seeded = data.module[bucket.name];
  if (!seeded || seeded.refs.length === 0) return;

  const ref = randomItem(seeded.refs);
  const start = Date.now();
  const res = http.get(
    cacheUrl(`/api/cache/module/${ref.hash}`, { hash: ref.hash, name: ref.name }),
    { headers: authHeaders(token), timeout: '120s' },
  );

  record(`module_read_${bucket.name}`, Date.now() - start, res.status === 200);
}

export function moduleWrite(data: SetupData): void {
  const token = data.token;
  const bucket = weightedRandom(LARGE_SIZES);
  const hash = `${RUN_ID}-modw-${randomId()}`;
  const name = `Module-${randomId()}.xcframework.zip`;
  const partCount = Math.ceil(bucket.bytes / MODULE_PART_SIZE);
  const start = Date.now();
  let success = true;

  const startRes = http.post(
    cacheUrl('/api/cache/module/start', { hash, name }),
    null,
    {
      headers: { ...authHeaders(token), 'Content-Type': 'application/json' },
      responseType: 'text',
    },
  );

  if (startRes.status !== 200) {
    record(`module_write_${bucket.name}`, Date.now() - start, false);
    return;
  }

  const uploadId = (startRes.json() as any).upload_id;
  if (!uploadId) {
    record(`module_write_${bucket.name}`, Date.now() - start, true);
    return;
  }

  for (let p = 1; p <= partCount; p++) {
    const partData = getModulePartPayload(bucket.bytes, p, MODULE_PART_SIZE);
    const partRes = http.post(
      cacheUrl('/api/cache/module/part', { upload_id: uploadId, part_number: String(p) }),
      partData,
      {
        headers: { ...authHeaders(token), 'Content-Type': 'application/octet-stream' },
        timeout: '120s',
      },
    );
    if (partRes.status !== 204) {
      success = false;
      break;
    }
  }

  if (success) {
    const parts = Array.from({ length: partCount }, (_, i) => i + 1);
    const completeRes = http.post(
      cacheUrl('/api/cache/module/complete', { upload_id: uploadId }),
      JSON.stringify({ parts }),
      { headers: { ...authHeaders(token), 'Content-Type': 'application/json' } },
    );
    if (completeRes.status !== 204) success = false;
  }

  record(`module_write_${bucket.name}`, Date.now() - start, success);
}
