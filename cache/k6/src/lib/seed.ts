import http from 'k6/http';
import { check } from 'k6';
import {
  XCODE_SEED_COUNT, MODULE_SEED_COUNT, GRADLE_SEED_COUNT, KV_DIRECT_SEED_COUNT,
  XCODE_SIZES, LARGE_SIZES, KV_DISTRIBUTIONS, MODULE_PART_SIZE, RUN_ID,
} from '../config.ts';
import { SeedData, SetupData, XcodeSeeded, ModuleSeeded, GradleSeeded } from '../types.ts';
import { authHeaders, cacheUrl } from './http.ts';
import { randomString } from './util.ts';
import { getPayload, getModulePartPayload } from '../payloads.ts';

function seedXcode(token: string): Record<string, XcodeSeeded> {
  const result: Record<string, XcodeSeeded> = {};

  for (const bucket of XCODE_SIZES) {
    const casIds: string[] = [];
    const kvCasIds: string[] = [];
    const payload = getPayload(bucket.name);

    for (let i = 0; i < XCODE_SEED_COUNT; i++) {
      const casId = `${RUN_ID}-xcode-${bucket.name}-${i}`;
      const kvCasId = `${RUN_ID}-kvxc-${bucket.name}-${i}`;

      const casRes = http.post(
        cacheUrl(`/api/cache/cas/${casId}`),
        payload,
        {
          headers: { ...authHeaders(token), 'Content-Type': 'application/octet-stream' },
          timeout: '120s',
        },
      );
      check(casRes, { 'seed xcode cas: ok': (r) => r.status === 204 || r.status === 200 });

      const kvRes = http.put(
        cacheUrl('/api/cache/keyvalue'),
        JSON.stringify({ cas_id: kvCasId, entries: [{ value: casId }] }),
        { headers: { ...authHeaders(token), 'Content-Type': 'application/json' } },
      );
      check(kvRes, { 'seed xcode kv: ok': (r) => r.status === 204 });

      casIds.push(casId);
      kvCasIds.push(kvCasId);
    }

    result[bucket.name] = { casIds, kvCasIds };
  }

  return result;
}

function seedModule(token: string): Record<string, ModuleSeeded> {
  const result: Record<string, ModuleSeeded> = {};

  for (const bucket of LARGE_SIZES) {
    const refs: Array<{ hash: string; name: string }> = [];
    const partCount = Math.ceil(bucket.bytes / MODULE_PART_SIZE);

    for (let i = 0; i < MODULE_SEED_COUNT; i++) {
      const hash = `${RUN_ID}-mod-${bucket.name}-${i}`;
      const name = `Module-${bucket.name}-${i}.xcframework.zip`;

      const startRes = http.post(
        cacheUrl('/api/cache/module/start', { hash, name }),
        null,
        { headers: authHeaders(token), responseType: 'text' },
      );
      check(startRes, { 'seed module start: ok': (r) => r.status === 200 });

      if (startRes.status !== 200) {
        const body = typeof startRes.body === 'string' ? startRes.body.substring(0, 200) : '';
        console.error(`Module start failed: status=${startRes.status} body=${body}`);
        refs.push({ hash, name });
        continue;
      }

      const uploadId = (startRes.json() as any).upload_id;
      if (!uploadId) {
        refs.push({ hash, name });
        continue;
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
        check(partRes, { 'seed module part: ok': (r) => r.status === 204 });
      }

      const parts = Array.from({ length: partCount }, (_, i) => i + 1);
      const completeRes = http.post(
        cacheUrl('/api/cache/module/complete', { upload_id: uploadId }),
        JSON.stringify({ parts }),
        { headers: { ...authHeaders(token), 'Content-Type': 'application/json' } },
      );
      check(completeRes, { 'seed module complete: ok': (r) => r.status === 204 });

      refs.push({ hash, name });
    }

    result[bucket.name] = { refs };
  }

  return result;
}

function seedGradle(token: string): Record<string, GradleSeeded> {
  const result: Record<string, GradleSeeded> = {};

  for (const bucket of LARGE_SIZES) {
    const keys: string[] = [];
    const payload = getPayload(bucket.name);

    for (let i = 0; i < GRADLE_SEED_COUNT; i++) {
      const key = `${RUN_ID}-gradle-${bucket.name}-${i}`;

      const res = http.put(
        cacheUrl(`/api/cache/gradle/${key}`),
        payload,
        {
          headers: { ...authHeaders(token), 'Content-Type': 'application/octet-stream' },
          timeout: '120s',
        },
      );
      check(res, { 'seed gradle: ok': (r) => r.status === 200 || r.status === 201 });

      keys.push(key);
    }

    result[bucket.name] = { keys };
  }

  return result;
}

function seedKvDirect(token: string): string[] {
  const casIds: string[] = [];

  for (let i = 0; i < KV_DIRECT_SEED_COUNT; i++) {
    const casId = `${RUN_ID}-kvdirect-${i}`;
    const dist = KV_DISTRIBUTIONS[i % KV_DISTRIBUTIONS.length];
    const entries = Array.from({ length: dist.entries }, () => ({
      value: randomString(dist.valueSize),
    }));

    const res = http.put(
      cacheUrl('/api/cache/keyvalue'),
      JSON.stringify({ cas_id: casId, entries }),
      { headers: { ...authHeaders(token), 'Content-Type': 'application/json' } },
    );
    check(res, { 'seed kv direct: ok': (r) => r.status === 204 });

    casIds.push(casId);
  }

  return casIds;
}

function warmReads(token: string, data: SetupData): void {
  for (const seeded of Object.values(data.xcode)) {
    for (const kvCasId of seeded.kvCasIds) {
      http.get(cacheUrl(`/api/cache/keyvalue/${kvCasId}`), { headers: authHeaders(token) });
    }
    for (const casId of seeded.casIds) {
      http.get(cacheUrl(`/api/cache/cas/${casId}`), { headers: authHeaders(token) });
    }
  }

  for (const seeded of Object.values(data.module)) {
    for (const ref of seeded.refs) {
      http.get(
        cacheUrl(`/api/cache/module/${ref.hash}`, { hash: ref.hash, name: ref.name }),
        { headers: authHeaders(token) },
      );
    }
  }

  for (const seeded of Object.values(data.gradle)) {
    for (const key of seeded.keys) {
      http.get(cacheUrl(`/api/cache/gradle/${key}`), { headers: authHeaders(token) });
    }
  }

  for (const casId of data.kvDirect) {
    http.get(cacheUrl(`/api/cache/keyvalue/${casId}`), { headers: authHeaders(token) });
  }
}

export function seedDataOf(data: SetupData): SeedData {
  return {
    xcode: data.xcode,
    module: data.module,
    gradle: data.gradle,
    kvDirect: data.kvDirect,
  };
}

export function setupFromSeedData(token: string, seedData: SeedData): SetupData {
  const data: SetupData = { token, ...seedData };

  console.log('Warming reads...');
  warmReads(token, data);

  return data;
}

export function seedAll(token: string): SetupData {
  console.log('Seeding xcode cache artifacts...');
  const xcode = seedXcode(token);

  console.log('Seeding module cache artifacts...');
  const module = seedModule(token);

  console.log('Seeding gradle cache artifacts...');
  const gradle = seedGradle(token);

  console.log('Seeding KV direct entries...');
  const kvDirect = seedKvDirect(token);

  const data = setupFromSeedData(token, { xcode, module, gradle, kvDirect });

  console.log('Seed complete.');
  return data;
}
