import assert from "node:assert/strict";
import test from "node:test";
import { gzipSync } from "node:zlib";
import { bodyFor, bodySize } from "./corpus.mjs";

test("resource corpus is deterministic, distinct and incompressible", () => {
  const first = bodyFor("seed-0");
  assert.equal(first.length, bodySize);
  assert.deepEqual(first, bodyFor("seed-0"));
  assert.notDeepEqual(first, bodyFor("seed-1"));
  assert.ok(gzipSync(first).length > bodySize * 0.99);
});
