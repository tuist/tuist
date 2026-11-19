import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export function compareLayers(before, after, maxAddedBytes = 10 * 1024 * 1024) {
  const existing = new Set(before.layers.map((layer) => layer.digest));
  const added = after.layers.filter((layer) => !existing.has(layer.digest));
  const addedBytes = added.reduce((sum, layer) => sum + layer.size, 0);
  assert(addedBytes > 0, 'The script edit must change an image layer');
  assert(addedBytes <= maxAddedBytes,
    `Script-only edit adds ${addedBytes} bytes (limit ${maxAddedBytes}); large layers were rebuilt`);
  return { reusedLayers: after.layers.length - added.length, addedLayers: added.length, addedBytes };
}

// Both archives are OCI layouts. Traverse indexes (including the Buildx
// attestation wrapper), selecting only the Linux amd64 image manifest.
export function manifest(layout, descriptor) {
  const value = JSON.parse(readFileSync(descriptor
    ? resolve(layout, 'blobs', ...descriptor.digest.split(':'))
    : resolve(layout, 'index.json'), 'utf8'));
  if (value.layers) return value;
  const child = value.manifests.find((entry) => entry.platform?.os === 'linux'
    && entry.platform?.architecture === 'amd64')
    ?? value.manifests.find((entry) => !entry.platform);
  assert(child, 'No Linux amd64 image in OCI layout');
  return manifest(layout, child);
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [before, after] = process.argv.slice(2);
  assert(before && after, 'Usage: compare-layers.mjs <before-oci-directory> <after-oci-directory>');
  console.log(JSON.stringify(compareLayers(manifest(before), manifest(after)), null, 2));
}
