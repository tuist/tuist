import http from 'k6/http';
import { check } from 'k6';
import { SEED_COUNT, XCODE_SIZES, LARGE_SIZES, KV_DISTRIBUTIONS, MODULE_PART_SIZE, RUN_ID } from '../config.ts';
import { SetupData, XcodeSeeded, ModuleSeeded, GradleSeeded } from '../types.ts';
import { authHeaders, cacheUrl } from './http.ts';
import { randomId, randomString, weightedRandom } from './util.ts';
import { getPayload } from '../payloads.ts';

function seedXcode(token: string): Record<string, XcodeSeeded> {
  var result: Record<string, XcodeSeeded> = {};

  for (var si = 0; si < XCODE_SIZES.length; si++) {
    var bucket = XCODE_SIZES[si];
    var casIds: string[] = [];
    var kvCasIds: string[] = [];
    var payload = getPayload(bucket.name);

    for (var i = 0; i < SEED_COUNT; i++) {
      var casId = RUN_ID + '-xcode-' + bucket.name + '-' + i;
      var kvCasId = RUN_ID + '-kvxc-' + bucket.name + '-' + i;

      // Upload CAS artifact
      var casRes = http.post(
        cacheUrl('/api/cache/cas/' + casId),
        payload,
        {
          headers: Object.assign({}, authHeaders(token), { 'Content-Type': 'application/octet-stream' }),
          timeout: '120s',
        }
      );
      check(casRes, { 'seed xcode cas: ok': function (r) { return r.status === 204 || r.status === 200; } });

      // Create matching KV entry
      var kvBody = JSON.stringify({
        cas_id: kvCasId,
        entries: [{ value: casId }],
      });
      var kvRes = http.put(
        cacheUrl('/api/cache/keyvalue'),
        kvBody,
        { headers: Object.assign({}, authHeaders(token), { 'Content-Type': 'application/json' }) }
      );
      check(kvRes, { 'seed xcode kv: ok': function (r) { return r.status === 204; } });

      casIds.push(casId);
      kvCasIds.push(kvCasId);
    }

    result[bucket.name] = { casIds: casIds, kvCasIds: kvCasIds };
  }

  return result;
}

function seedModule(token: string): Record<string, ModuleSeeded> {
  var result: Record<string, ModuleSeeded> = {};

  for (var si = 0; si < LARGE_SIZES.length; si++) {
    var bucket = LARGE_SIZES[si];
    var refs: Array<{ hash: string; name: string }> = [];
    var payload = getPayload(bucket.name);
    var partCount = Math.ceil(bucket.bytes / MODULE_PART_SIZE);

    for (var i = 0; i < SEED_COUNT; i++) {
      var hash = RUN_ID + '-mod-' + bucket.name + '-' + i;
      var name = 'Module-' + bucket.name + '-' + i + '.xcframework.zip';

      // Start multipart upload
      var startRes = http.post(
        cacheUrl('/api/cache/module/start', { hash: hash, name: name }),
        null,
        { headers: authHeaders(token) }
      );
      check(startRes, { 'seed module start: ok': function (r) { return r.status === 200; } });

      if (startRes.status !== 200) {
        var bodySnippet = typeof startRes.body === 'string' ? startRes.body.substring(0, 200) : '';
        console.error('Module start failed: status=' + startRes.status + ' body=' + bodySnippet);
        refs.push({ hash: hash, name: name });
        continue;
      }

      var uploadId = (startRes.json() as any).upload_id;
      if (!uploadId) {
        refs.push({ hash: hash, name: name });
        continue;
      }

      // Upload parts
      for (var p = 1; p <= partCount; p++) {
        var partStart = (p - 1) * MODULE_PART_SIZE;
        var partEnd = Math.min(p * MODULE_PART_SIZE, payload.byteLength);
        var partData = payload.slice(partStart, partEnd);

        var partRes = http.post(
          cacheUrl('/api/cache/module/part', { upload_id: uploadId, part_number: String(p) }),
          partData,
          {
            headers: Object.assign({}, authHeaders(token), { 'Content-Type': 'application/octet-stream' }),
            timeout: '120s',
          }
        );
        check(partRes, { 'seed module part: ok': function (r) { return r.status === 204; } });
      }

      // Complete upload
      var parts: number[] = [];
      for (var pi = 1; pi <= partCount; pi++) parts.push(pi);

      var completeRes = http.post(
        cacheUrl('/api/cache/module/complete', { upload_id: uploadId }),
        JSON.stringify({ parts: parts }),
        { headers: Object.assign({}, authHeaders(token), { 'Content-Type': 'application/json' }) }
      );
      check(completeRes, { 'seed module complete: ok': function (r) { return r.status === 204; } });

      refs.push({ hash: hash, name: name });
    }

    result[bucket.name] = { refs: refs };
  }

  return result;
}

function seedGradle(token: string): Record<string, GradleSeeded> {
  var result: Record<string, GradleSeeded> = {};

  for (var si = 0; si < LARGE_SIZES.length; si++) {
    var bucket = LARGE_SIZES[si];
    var keys: string[] = [];
    var payload = getPayload(bucket.name);

    for (var i = 0; i < SEED_COUNT; i++) {
      var key = RUN_ID + '-gradle-' + bucket.name + '-' + i;

      var res = http.put(
        cacheUrl('/api/cache/gradle/' + key),
        payload,
        {
          headers: Object.assign({}, authHeaders(token), { 'Content-Type': 'application/octet-stream' }),
          timeout: '120s',
        }
      );
      check(res, { 'seed gradle: ok': function (r) { return r.status === 200 || r.status === 201; } });

      keys.push(key);
    }

    result[bucket.name] = { keys: keys };
  }

  return result;
}

function seedKvDirect(token: string): string[] {
  var casIds: string[] = [];
  for (var i = 0; i < SEED_COUNT; i++) {
    var casId = RUN_ID + '-kvdirect-' + i;
    var dist = KV_DISTRIBUTIONS[i % KV_DISTRIBUTIONS.length];
    var entries: Array<{ value: string }> = [];
    for (var e = 0; e < dist.entries; e++) {
      entries.push({ value: randomString(dist.valueSize) });
    }

    var res = http.put(
      cacheUrl('/api/cache/keyvalue'),
      JSON.stringify({ cas_id: casId, entries: entries }),
      { headers: Object.assign({}, authHeaders(token), { 'Content-Type': 'application/json' }) }
    );
    check(res, { 'seed kv direct: ok': function (r) { return r.status === 204; } });

    casIds.push(casId);
  }
  return casIds;
}

function warmReads(token: string, data: SetupData): void {
  // Warm xcode reads
  var xcodeKeys = Object.keys(data.xcode);
  for (var xi = 0; xi < xcodeKeys.length; xi++) {
    var seeded = data.xcode[xcodeKeys[xi]];
    if (seeded.kvCasIds.length > 0) {
      http.get(cacheUrl('/api/cache/keyvalue/' + seeded.kvCasIds[0]), { headers: authHeaders(token) });
    }
    if (seeded.casIds.length > 0) {
      http.get(cacheUrl('/api/cache/cas/' + seeded.casIds[0]), { headers: authHeaders(token) });
    }
  }

  // Warm module reads
  var modKeys = Object.keys(data.module);
  for (var mi = 0; mi < modKeys.length; mi++) {
    var modSeeded = data.module[modKeys[mi]];
    if (modSeeded.refs.length > 0) {
      var ref = modSeeded.refs[0];
      http.get(
        cacheUrl('/api/cache/module/' + ref.hash, { hash: ref.hash, name: ref.name }),
        { headers: authHeaders(token) }
      );
    }
  }

  // Warm gradle reads
  var gradleKeys = Object.keys(data.gradle);
  for (var gi = 0; gi < gradleKeys.length; gi++) {
    var gradleSeeded = data.gradle[gradleKeys[gi]];
    if (gradleSeeded.keys.length > 0) {
      http.get(cacheUrl('/api/cache/gradle/' + gradleSeeded.keys[0]), { headers: authHeaders(token) });
    }
  }

  // Warm KV direct reads
  for (var ki = 0; ki < Math.min(3, data.kvDirect.length); ki++) {
    http.get(cacheUrl('/api/cache/keyvalue/' + data.kvDirect[ki]), { headers: authHeaders(token) });
  }
}

export function seedAll(token: string): SetupData {
  console.log('Seeding xcode cache artifacts...');
  var xcode = seedXcode(token);

  console.log('Seeding module cache artifacts...');
  var mod = seedModule(token);

  console.log('Seeding gradle cache artifacts...');
  var gradle = seedGradle(token);

  console.log('Seeding KV direct entries...');
  var kvDirect = seedKvDirect(token);

  var data: SetupData = {
    token: token,
    xcode: xcode,
    module: mod,
    gradle: gradle,
    kvDirect: kvDirect,
  };

  console.log('Warming reads...');
  warmReads(token, data);

  console.log('Seed complete.');
  return data;
}
