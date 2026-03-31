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
  { name: '10kb', bytes: 10 * 1024, weight: 0.6 },
  { name: '256kb', bytes: 256 * 1024, weight: 0.3 },
  { name: '2mb', bytes: 2 * 1024 * 1024, weight: 0.1 },
];

export const LARGE_SIZES: SizeBucket[] = [
  { name: '10mb', bytes: 10 * 1024 * 1024, weight: 0.7 },
  { name: '25mb', bytes: 25 * 1024 * 1024, weight: 0.2 },
  { name: '50mb', bytes: 50 * 1024 * 1024, weight: 0.1 },
];

export const KV_DISTRIBUTIONS = [
  { entries: 4, valueSize: 64, weight: 0.5 },
  { entries: 8, valueSize: 128, weight: 0.35 },
  { entries: 16, valueSize: 256, weight: 0.15 },
];

export const MODULE_PART_SIZE = 10 * 1024 * 1024;
