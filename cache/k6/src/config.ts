import { SizeBucket } from './types.ts';

export const CACHE_HOST = __ENV.CACHE_HOST || 'cache-eu-central-staging.tuist.dev';
export const SERVER_URL = __ENV.SERVER_URL || 'https://staging.tuist.dev';
export const REGION = __ENV.REGION || 'eu-central';
export const RUN_ID = __ENV.RUN_ID || `lt-local-${Date.now()}`;
export const COMMIT_SHA = __ENV.COMMIT_SHA || 'unknown';
export const CACHE_AUTH_TOKEN = __ENV.CACHE_AUTH_TOKEN || '';

export const ACCOUNT_HANDLE = 'tuist';
export const PROJECT_HANDLE = 'tuist';

export const CACHE_BASE_URL = `https://${CACHE_HOST}`;

export const XCODE_SEED_COUNT = 10;
export const MODULE_SEED_COUNT = 4;
export const GRADLE_SEED_COUNT = 4;
export const KV_DIRECT_SEED_COUNT = 10;

export const XCODE_SIZES: SizeBucket[] = [
  { name: '10kb', bytes: 10 * 1024 },
  { name: '256kb', bytes: 256 * 1024 },
  { name: '2mb', bytes: 2 * 1024 * 1024 },
];

export const LARGE_SIZES: SizeBucket[] = [
  { name: '5mb', bytes: 5 * 1024 * 1024 },
  { name: '10mb', bytes: 10 * 1024 * 1024 },
  { name: '25mb', bytes: 25 * 1024 * 1024 },
];

export const KV_DISTRIBUTIONS = [
  { entries: 4, valueSize: 64 },
  { entries: 8, valueSize: 128 },
  { entries: 16, valueSize: 256 },
];

export const MODULE_PART_SIZE = 10 * 1024 * 1024;
