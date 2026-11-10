import assert from 'node:assert/strict';
import { test } from 'node:test';
import { compareLayers } from './compare-layers.mjs';

const before = { layers: [{ digest: 'sdk', size: 1_400_000_000 }, { digest: 'script-v1', size: 10_000 }] };
test('script-only releases reuse toolchain bytes', () => {
  assert.deepEqual(compareLayers(before, {
    layers: [before.layers[0], { digest: 'script-v2', size: 11_000 }],
  }), { reusedLayers: 1, addedLayers: 1, addedBytes: 11_000 });
});
test('fresh SDK blob fails even when its size is unchanged', () => {
  assert.throws(() => compareLayers(before, {
    layers: [{ digest: 'sdk-rebuilt', size: 1_400_000_000 }, { digest: 'script-v2', size: 11_000 }],
  }), /large layers were rebuilt/);
});
test('unchanged build does not prove the script edit was exercised', () => {
  assert.throws(() => compareLayers(before, before), /must change/);
});
