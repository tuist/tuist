import { XCODE_SIZES, LARGE_SIZES } from './config.ts';

const SMALL_PAYLOAD_CACHE_LIMIT = 2 * 1024 * 1024;

const ALL_SIZES: Record<string, number> = {};
for (const bucket of [...XCODE_SIZES, ...LARGE_SIZES]) {
  ALL_SIZES[bucket.name] = bucket.bytes;
}

const cache: Record<string, ArrayBuffer> = {};

function buildPayload(size: number): ArrayBuffer {
  return new ArrayBuffer(size);
}

export function getPayloadForSize(size: number): ArrayBuffer {
  if (size <= SMALL_PAYLOAD_CACHE_LIMIT) {
    const key = String(size);
    cache[key] ??= buildPayload(size);
    return cache[key];
  }
  return buildPayload(size);
}

export function getPayload(name: string): ArrayBuffer {
  const size = ALL_SIZES[name];
  if (!size) throw new Error(`Unknown payload: ${name}`);
  return getPayloadForSize(size);
}

export function getModulePartPayload(totalBytes: number, partNumber: number, partSize: number): ArrayBuffer {
  const partOffset = (partNumber - 1) * partSize;
  if (partOffset < 0 || partOffset >= totalBytes) {
    throw new Error(`Invalid part number: ${partNumber}`);
  }
  return getPayloadForSize(Math.min(partSize, totalBytes - partOffset));
}
