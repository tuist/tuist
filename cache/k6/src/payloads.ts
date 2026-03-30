var cache: Record<string, ArrayBuffer> = {};

var SIZES: Record<string, number> = {
  '10kb': 10 * 1024,
  '256kb': 256 * 1024,
  '2mb': 2 * 1024 * 1024,
  '10mb': 10 * 1024 * 1024,
  '25mb': 25 * 1024 * 1024,
  '50mb': 50 * 1024 * 1024,
};

export function getPayload(name: string): ArrayBuffer {
  if (cache[name]) return cache[name];

  var size = SIZES[name];
  if (!size) throw new Error('Unknown payload: ' + name);

  var buf = new ArrayBuffer(size);
  var view = new Uint8Array(buf);
  for (var i = 0; i < size; i++) {
    view[i] = i & 0xff;
  }
  cache[name] = buf;
  return buf;
}
