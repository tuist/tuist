import http from 'k6/http';
import { SetupData } from '../types.ts';
import { LARGE_SIZES, MODULE_PART_SIZE, RUN_ID } from '../config.ts';
import { authHeaders, cacheUrl } from '../lib/http.ts';
import { weightedRandom, randomItem, randomId } from '../lib/util.ts';
import { record } from '../metrics.ts';
import { getPayload } from '../payloads.ts';

export function moduleExists(data: SetupData): void {
  var bucket = weightedRandom(LARGE_SIZES);
  var seeded = data.module[bucket.name];
  if (!seeded || seeded.refs.length === 0) return;

  var ref = randomItem(seeded.refs);
  var start = Date.now();

  var res = http.head(
    cacheUrl('/api/cache/module/' + ref.hash, { hash: ref.hash, name: ref.name }),
    { headers: authHeaders(data.token) }
  );

  var duration = Date.now() - start;
  record('module_exists_' + bucket.name, duration, res.status === 204);
}

export function moduleRead(data: SetupData): void {
  var bucket = weightedRandom(LARGE_SIZES);
  var seeded = data.module[bucket.name];
  if (!seeded || seeded.refs.length === 0) return;

  var ref = randomItem(seeded.refs);
  var start = Date.now();

  var res = http.get(
    cacheUrl('/api/cache/module/' + ref.hash, { hash: ref.hash, name: ref.name }),
    {
      headers: authHeaders(data.token),
      timeout: '120s',
    }
  );

  var duration = Date.now() - start;
  record('module_read_' + bucket.name, duration, res.status === 200);
}

export function moduleWrite(data: SetupData): void {
  var bucket = weightedRandom(LARGE_SIZES);
  var hash = RUN_ID + '-modw-' + randomId();
  var name = 'Module-' + randomId() + '.xcframework.zip';
  var payload = getPayload(bucket.name);

  var partCount = Math.ceil(bucket.bytes / MODULE_PART_SIZE);
  var start = Date.now();
  var success = true;

  // Step 1: Start multipart upload
  var startRes = http.post(
    cacheUrl('/api/cache/module/start', { hash: hash, name: name }),
    null,
    { headers: Object.assign({}, authHeaders(data.token), { 'Content-Type': 'application/json' }) }
  );

  if (startRes.status !== 200) {
    record('module_write_' + bucket.name, Date.now() - start, false);
    return;
  }

  var uploadId = (startRes.json() as any).upload_id;
  if (!uploadId) {
    // Artifact already exists
    record('module_write_' + bucket.name, Date.now() - start, true);
    return;
  }

  // Step 2: Upload parts
  for (var p = 1; p <= partCount; p++) {
    var partStart = (p - 1) * MODULE_PART_SIZE;
    var partEnd = Math.min(p * MODULE_PART_SIZE, payload.byteLength);
    var partData = payload.slice(partStart, partEnd);

    var partRes = http.post(
      cacheUrl('/api/cache/module/part', { upload_id: uploadId, part_number: String(p) }),
      partData,
      {
        headers: Object.assign({}, authHeaders(data.token), { 'Content-Type': 'application/octet-stream' }),
        timeout: '120s',
      }
    );
    if (partRes.status !== 204) {
      success = false;
      break;
    }
  }

  // Step 3: Complete upload
  if (success) {
    var parts: number[] = [];
    for (var pi = 1; pi <= partCount; pi++) parts.push(pi);

    var completeRes = http.post(
      cacheUrl('/api/cache/module/complete', { upload_id: uploadId }),
      JSON.stringify({ parts: parts }),
      { headers: Object.assign({}, authHeaders(data.token), { 'Content-Type': 'application/json' }) }
    );
    if (completeRes.status !== 204) {
      success = false;
    }
  }

  var duration = Date.now() - start;
  record('module_write_' + bucket.name, duration, success);
}
