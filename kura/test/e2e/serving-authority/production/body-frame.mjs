import assert from "node:assert/strict";
import { createHash } from "node:crypto";

// See encode_backfill_body_frame_header in src/http.rs. The metadata prelude
// is bounded by two u16 lengths; the artifact body is hashed without buffering.
export async function verifyBodyFrame(chunks, expected) {
  let header = Buffer.alloc(0),
    needed = 22,
    parsed = false,
    size = 0;
  const hash = createHash("sha256");
  for await (const bytes of chunks) {
    let chunk = Buffer.from(bytes);
    while (!parsed && chunk.length) {
      const take = Math.min(needed - header.length, chunk.length);
      header = Buffer.concat([header, chunk.subarray(0, take)]);
      chunk = chunk.subarray(take);
      if (header.length < needed) break;
      if (needed === 22) {
        assert.equal(header[1], 0, "body frame must be Present");
        assert.equal(Number(header.readBigUInt64BE(14)), expected.size);
        needed += header.readUInt16BE(2) + header.readUInt16BE(12);
      }
      if (header.length === needed) {
        const idEnd = 22 + header.readUInt16BE(2);
        assert.equal(header.subarray(22, idEnd).toString(), expected.record_id);
        const meta = JSON.parse(header.subarray(idEnd).toString());
        assert.equal(meta.key, expected.key);
        parsed = true;
      }
    }
    if (parsed) {
      hash.update(chunk);
      size += chunk.length;
    }
  }
  assert(parsed, "truncated body prelude");
  assert.equal(size, expected.size, "truncated or extra body bytes");
  assert.equal(hash.digest("hex"), expected.hash, "retained body digest");
  return size;
}
