import http from 'k6/http';
import { SetupData } from '../types.ts';
import { XCODE_SIZES, RUN_ID } from '../config.ts';
import { authHeaders, cacheUrl } from '../lib/http.ts';
import { weightedRandom, randomItem, randomId } from '../lib/util.ts';
import { record } from '../metrics.ts';
import { getPayload } from '../payloads.ts';

export function xcodeRead(data: SetupData): void {
  const token = data.token;
  const bucket = weightedRandom(XCODE_SIZES);
  const seeded = data.xcode[bucket.name];
  if (!seeded || seeded.kvCasIds.length === 0) return;

  const kvCasId = randomItem(seeded.kvCasIds);
  const start = Date.now();
  let success = true;

  const kvRes = http.get(
    cacheUrl(`/api/cache/keyvalue/${kvCasId}`),
    { headers: authHeaders(token), responseType: 'text' },
  );

  if (kvRes.status !== 200) {
    success = false;
  } else {
    const body = kvRes.json() as any;
    const casId = body?.entries?.[0]?.value;

    if (casId) {
      const casRes = http.get(cacheUrl(`/api/cache/cas/${casId}`), { headers: authHeaders(token) });
      if (casRes.status !== 200) success = false;
    } else {
      success = false;
    }
  }

  record(`xcode_read_${bucket.name}`, Date.now() - start, success);
}

export function xcodeWrite(data: SetupData): void {
  const token = data.token;
  const bucket = weightedRandom(XCODE_SIZES);
  const casId = `${RUN_ID}-xcw-${randomId()}`;
  const kvCasId = `${RUN_ID}-kvxcw-${randomId()}`;
  const payload = getPayload(bucket.name);

  const start = Date.now();
  let success = true;

  const casRes = http.post(
    cacheUrl(`/api/cache/cas/${casId}`),
    payload,
    {
      headers: { ...authHeaders(token), 'Content-Type': 'application/octet-stream' },
      timeout: '60s',
    },
  );
  if (casRes.status !== 204 && casRes.status !== 200) success = false;

  const kvRes = http.put(
    cacheUrl('/api/cache/keyvalue'),
    JSON.stringify({ cas_id: kvCasId, entries: [{ value: casId }] }),
    { headers: { ...authHeaders(token), 'Content-Type': 'application/json' } },
  );
  if (kvRes.status !== 204) success = false;

  record(`xcode_write_${bucket.name}`, Date.now() - start, success);
}
