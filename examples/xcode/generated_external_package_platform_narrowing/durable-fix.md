# Reuse a combined XCFramework through SDK fingerprints

This document describes the implementation in this branch. The adjacent
reproduction records the original exact-hash behavior; the automated acceptance
test uses `generated_workspace_with_multiplatform_cache` and rewrites an actual
`Workspace.swift` between warming and generation.

## Problem and identity

A workspace containing iOS and macOS consumers narrows an external package to
both platforms. Loading a different workspace that contains only the iOS
consumer narrows the same package to iOS. Destinations participate in the
existing target hash, so the leaf hash changes and that difference propagates
through dependent targets. The combined XCFramework has usable iOS slices but
an exact lookup cannot find it. Positional focus applied after loading the same
incoming graph does not cause this difference.

Keep the original exact hashes and add per-SDK build fingerprints. Each
fingerprint normalizes the target's destinations and deployment targets to one
compilation variant, filters conditional dependencies, and recursively hashes
the applicable dependency variants. Macro dependencies use their macOS host
variant. Existing target hashing retains source/revision identity and settings;
the fingerprint also includes the resolved configuration, Swift compiler
version, cache version, fingerprint format version, SDK variant, and deployment
target.

Initial compatibility support is restricted to iOS device, iOS simulator,
Catalyst, and macOS. Explicit custom architecture settings and other platforms
retain exact-hash lookup. Resource bundles and macro executables are not newly
published as independently indexed XCFramework payloads.

## One payload, several small lookup records

Warming still builds one combined XCFramework. `BinaryCacheStorage` derives an
artifact digest from its content and the supported fingerprints, adds a
`BinaryCacheArtifact.json` manifest, and stores the payload once through the
existing storage implementation. Fingerprints travel from the preload graph
through archiving; they are not recomputed after binary substitution.

After payload publication succeeds, the index records the artifact under every
nonempty subset of its supported fingerprints. An iOS device/simulator/macOS
artifact needs seven small records, all pointing to the same payload. The four
modeled variants bound this to fifteen records. Readers request one key for
their complete required fingerprint set.

For example, an iOS-only request hashes its device and simulator fingerprints
into one lookup key. A combined provider registers that key as well as the
combined iOS/macOS key. An iOS-only provider cannot register the combined key.
Concurrent publishers for a given key satisfy the same complete request, so a
last-writer replacement does not require a read/merge/write protocol.

The local index uses separate atomic provider files in the bounded
`BinaryCacheIndex` support-cache category. Remote records use the existing
project-scoped key-value API with the `tuist-xcframework-v1-` prefix. No new
server endpoint or database migration is required.

## Lookup and validation

Lookup checks local metadata first, then remote metadata for unresolved items.
Selected payloads are deduplicated by their artifact identity before storage
fetches them. The returned cache result retains the caller's logical target hash
and the payload's local/remote hit source.

Before replacement, the index record must match the embedded artifact manifest.
The XCFramework property list must expose the requested SDK/platform variants
and required architectures, and the referenced library binaries must exist.
Unavailable, malformed, incomplete, and stale providers do not become hits.
Previously resolved payload digests remain protected from download-triggered
cache eviction. Requests still unresolved use the existing exact-hash lookup.

Independent iOS-only and macOS-only payloads are not assembled into another
XCFramework. A combined request needs a single compatible provider or a rebuild.
This preserves XCFramework packaging and avoids uploading the same combined
framework once for every consumer platform.

## Compatibility and rollout

New clients can still consume old artifacts through exact-hash lookup. New
indexed payloads require the updated client; old clients may rebuild until they
have a matching legacy entry. The legacy module-cache endpoint retains its
existing exact-hash publication and lookup path. Index records are disposable:
losing them can reduce reuse but does not make an incompatible artifact valid.
No migration or deletion of existing cache entries is required.

The CLI changes and private `TuistCacheEE` storage changes must be shipped
together. Reverting the integration restores exact-hash behavior; indexed
metadata and payloads can expire under the existing cache budgets and retention.

## Validation

The fingerprint tests compare combined, iOS-only, and macOS-only dependency
graphs, verify dependency-setting and deployment-target invalidation, and verify
that custom dependency architectures keep exact lookup. Storage tests cover one
payload serving narrower requests, stale/missing slices, incomplete providers,
and narrower publication preserving the combined lookup. Existing graph-hasher
and storage-factory suites also run.

The acceptance test warms real `Shared` and `Leaf` XCFrameworks with iOS and
macOS consumers, verifies device/simulator/macOS coverage, rewrites
`Workspace.swift` to include only the iOS project, and checks that the generated
workspace excludes the macOS project. It verifies both binary substitutions,
unchanged physical artifact paths, and successful device and simulator builds.
The package is local to keep acceptance validation independent of a hosted
package or remote cache. Revision-based external hashing is additionally covered
by the synthetic hash tests and the earlier loopback-Git reproduction.

Remote index and payload deduplication are exercised through unit-test service
and storage implementations; the acceptance test does not exercise a deployed
remote cache. The synthetic fixture demonstrates the workspace-shape failure
mode and does not establish compatibility for every package or build setup.
