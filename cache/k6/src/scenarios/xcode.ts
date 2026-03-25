import http from 'k6/http';
import { SetupData } from '../types.ts';
import { XCODE_SIZES, RUN_ID } from '../config.ts';
import { authHeaders, cacheUrl } from '../lib/http.ts';
import { weightedRandom, randomItem, randomId } from '../lib/util.ts';
import { record } from '../metrics.ts';
import { payloads } from '../payloads.ts';

export function xcodeReadHit(data: SetupData): void {
  var bucket = weightedRandom(XCODE_SIZES);
  var seeded = data.xcode[bucket.name];
  if (!seeded || seeded.kvCasIds.length === 0) return;

  var kvCasId = randomItem(seeded.kvCasIds);
  var start = Date.now();
  var success = true;

  // Step 1: GET KV to resolve CAS artifact ID
  var kvRes = http.get(
    cacheUrl('/api/cache/keyvalue/' + kvCasId),
    { headers: authHeaders(data.token) }
  );

  if (kvRes.status !== 200) {
    success = false;
  } else {
    // Step 2: GET CAS artifact
    var body = kvRes.json() as any;
    var casId = body && body.entries && body.entries[0] ? body.entries[0].value : null;

    if (casId) {
      var casRes = http.get(
        cacheUrl('/api/cache/cas/' + casId),
        { headers: authHeaders(data.token) }
      );
      if (casRes.status !== 200) {
        success = false;
      }
    } else {
      success = false;
    }
  }

  var duration = Date.now() - start;
  record('xcode_read_hit_' + bucket.name, duration, success);
}

export function xcodeWrite(data: SetupData): void {
  var bucket = weightedRandom(XCODE_SIZES);
  var casId = RUN_ID + '-xcw-' + randomId();
  var kvCasId = RUN_ID + '-kvxcw-' + randomId();
  var payload = payloads[bucket.name];
  if (!payload) return;

  var start = Date.now();
  var success = true;

  // Step 1: POST CAS artifact
  var casRes = http.post(
    cacheUrl('/api/cache/cas/' + casId),
    payload,
    {
      headers: Object.assign({}, authHeaders(data.token), { 'Content-Type': 'application/octet-stream' }),
      timeout: '60s',
    }
  );
  if (casRes.status !== 204 && casRes.status !== 200) {
    success = false;
  }

  // Step 2: PUT KV entry
  var kvRes = http.put(
    cacheUrl('/api/cache/keyvalue'),
    JSON.stringify({ cas_id: kvCasId, entries: [{ value: casId }] }),
    { headers: Object.assign({}, authHeaders(data.token), { 'Content-Type': 'application/json' }) }
  );
  if (kvRes.status !== 204) {
    success = false;
  }

  var duration = Date.now() - start;
  record('xcode_write_' + bucket.name, duration, success);
}
