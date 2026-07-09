# Proposal: range-digest anti-entropy for bootstrap

## Problem

When a node (re)joins the mesh it **bootstraps** each peer: it walks the peer's
entire manifest set page by page (`/_internal/bootstrap/manifests`, 256/page,
cursor-ordered by `artifact_id`), pre-checks every manifest against its local
store, and fetches the ones it is missing. A peer is marked bootstrapped — and
the node allowed to serve — only after one fully clean pass.

This is O(peer's whole dataset) **regardless of how in-sync the two nodes
already are**. In production the tuist `eu-central` ↔ `scw-fr-par` pair is ~99%
in sync (the joining node already holds ~1.4M of the peer's ~1.4M artifacts),
yet each bootstrap still:

- fetches **~5,652 manifest pages** serially over the peer link (~15 min just to
  walk, measured), and
- runs **~1.4M local pre-checks**,

before it can apply the tiny delta. Combined with the fixed
`KURA_BOOTSTRAP_TIMEOUT_MS` (default 30 min, wraps the *whole* per-peer
bootstrap) and the walk restarting from `after = None` every retry, a
mostly-in-sync-but-large pair **never finishes a pass** and the node stays
`NotReady` indefinitely. Both nodes are same-metro (Paris) with 512 MB/s
replication bandwidth configured, so this is pure per-artifact/per-page
**overhead**, not bytes or WAN — the same "many tiny artifacts" shape as the
value-graph tail.

## Goal

Make bootstrap cost O(**delta**), not O(peer dataset), so a mostly-in-sync pair
reconciles in seconds and only genuinely-large deltas do real work.

## Approach: range-based set reconciliation

The manifests column family is a sorted keyspace over `artifact_id` (a
content/storage hash, uniform and identical across nodes for identical content).
That makes it a natural fit for **range digests** (the technique behind
Cassandra/Scylla merkle anti-entropy, Dynamo, `rsync` rolling checks):

1. **Digest.** Both nodes summarize their manifest keyspace as per-range
   digests. Partition by `artifact_id` prefix into a fixed number of buckets
   (e.g. 4096 = first 3 hex nibbles → ~340 artifacts/bucket at 1.4M). For each
   bucket compute `(count, rolling_hash)` where the hash folds the sorted
   `(artifact_id, version_ms)` pairs in the bucket. One ordered CF scan builds
   all buckets — local, no network, seconds.

2. **Compare.** The joining node fetches the peer's digest, computes its own,
   and diffs per bucket. Buckets whose `(count, hash)` **match** are skipped
   entirely. Only **mismatching** buckets are enqueued.

3. **Enumerate only the divergent ranges.** For each mismatching bucket, run the
   existing paginated manifest walk **scoped to that bucket's key range**, then
   fetch + apply exactly as today. `version_ms` in the hash means a version
   change flips the bucket, so LWW conflicts are caught; the existing apply path
   (`ignored_stale`, group-commit fsync) is unchanged.

For a 99%-in-sync pair this collapses 5,652 serial page round-trips into **one
digest exchange + a handful of small range walks**.

### Optional recursion

For a large delta concentrated in one bucket, recurse one level (sub-bucket the
mismatching bucket with more nibbles) before enumerating. A 2-level scheme is
plenty for tens of millions of artifacts; start with a single flat level and add
recursion only if profiling shows a hot bucket.

## Protocol

New peer endpoint, additive and negotiated:

```
GET /_internal/bootstrap/digest?buckets=4096
→ 200 { "buckets": 4096, "digests": [ {"prefix":"000","count":331,"hash":"…"}, … ] }
```

- Server: one ordered scan of `ROCKSDB_CF_MANIFESTS`, folding `(count, hash)`
  per prefix bucket. (Later optimization: maintain the digest incrementally on
  each manifest write so the endpoint is O(buckets), not O(n).)
- Client: `bootstrap_manifests_from_peer` fetches the peer digest, computes the
  local digest the same way, diffs, and walks only the mismatching ranges. It
  needs a range-scoped variant of the manifests walk — add an optional
  `&prefix=` / `&before=` to `/_internal/bootstrap/manifests` (the walk already
  takes `after`).
- **Fallback:** a peer that 404s `/_internal/bootstrap/digest` → fall back to the
  full walk (today's behavior), negotiated exactly like the `inline "*"`
  extension. Mixed-version safe both directions.

## Correctness

- `artifact_id` is a content/storage hash and unique, so bucket membership is
  well-defined and identical for identical content across nodes.
- Folding `(artifact_id, version_ms)` (not just `artifact_id`) into the hash
  detects adds, removes, **and** version bumps → no missed updates.
- `count` is a cheap first discriminator; the hash is the authority. Use a
  non-XOR fold (e.g. a running blake3/xxh3 over the ordered pairs) so a pair of
  swapped ids can't cancel out.
- The digest only decides *which ranges to enumerate*; apply semantics (LWW,
  tombstones, staging budget) are untouched, so a digest bug can at worst cause
  an unnecessary walk, never data loss or a wrong apply.

## Rollout safety

Additive endpoint; no wire-format, storage-format, or replication-body change;
negotiated with graceful fallback; safe under one version skew in both
directions. Matches kura's rollout invariants.

## Relationship to the other levers

- **Resumable walk** (persist the manifest cursor across retries) is a smaller,
  complementary win; largely subsumed once the walk is delta-sized.
- **Bootstrap vs. live-replication lock fairness** is *orthogonal* and may still
  be needed: production telemetry shows the bootstrap stalling (`applied` flat)
  while live `replicate/artifact` runs at ~28/s, i.e. live writes appear to
  starve the bootstrap on the segment-append lock. Range digests shrink the work
  but do not by themselves fix starvation on the remaining delta. Recommend
  confirming with a quick profile / lock-wait metric and, if real, adding
  fairness (e.g. bounded live-write concurrency while a bootstrap is inflight).

## Rough plan

1. `manifests_digest(buckets)` in `store.rs` (ordered scan → per-bucket
   `(count, hash)`), plus a range-scoped `manifests_page`.
2. `GET /_internal/bootstrap/digest` handler + client fetch/negotiation.
3. `bootstrap_manifests_from_peer`: digest-diff → walk only divergent ranges;
   404 → full-walk fallback.
4. Tests: identical stores → zero ranges walked; single divergent artifact →
   exactly one bucket walked; version bump flips a bucket; old-peer fallback.
5. Metric: ranges-skipped vs walked, to confirm the win in prod.
