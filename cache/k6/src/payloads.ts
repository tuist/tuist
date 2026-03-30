var cache: Record<string, ArrayBuffer> = {};

var SMALL_PAYLOAD_CACHE_LIMIT = 2 * 1024 * 1024;

var SIZES: Record<string, number> = {
  '10kb': 10 * 1024,
  '256kb': 256 * 1024,
  '2mb': 2 * 1024 * 1024,
  '10mb': 10 * 1024 * 1024,
  '25mb': 25 * 1024 * 1024,
  '50mb': 50 * 1024 * 1024,
};

export function getPayload(name: string): ArrayBuffer {
  var size = SIZES[name];
  if (!size) throw new Error('Unknown payload: ' + name);

  return getPayloadForSize(size);
}

function buildPayload(size: number): ArrayBuffer {
  var buf = new ArrayBuffer(size);
  var view = new Uint8Array(buf);
  for (var i = 0; i < size; i++) {
    view[i] = i & 0xff;
  }
  return buf;
}

export function getPayloadForSize(size: number): ArrayBuffer {
  if (size <= SMALL_PAYLOAD_CACHE_LIMIT) {
    var key = String(size);
    if (!cache[key]) {
      cache[key] = buildPayload(size);
    }
    return cache[key];
  }

  return buildPayload(size);
}

export function getModulePartPayload(totalBytes: number, partNumber: number, partSize: number): ArrayBuffer {
  var partOffset = (partNumber - 1) * partSize;
  if (partOffset < 0 || partOffset >= totalBytes) {
    throw new Error('Invalid part number: ' + partNumber);
  }

  return getPayloadForSize(Math.min(partSize, totalBytes - partOffset));
}
