# Autoresearch: lock-free chunk recipe pressure path

## Objective

Minimize the time needed to apply 128 replicated chunk recipes concurrently and evict their shared chunk while preserving every reverse-reference and cascade invariant.

## Metrics

- Primary: `concurrent_recipe_cascade_ns` (nanoseconds, lower is better)
- Secondary: correctness checks for chunk reconstruction, backfill ordering, bounded presence scans, and cascade cleanup

## How to Run

`./autoresearch.sh`

## Files in Scope

- `src/reapi/chunking.rs`: bounded recipe lookup and chunk access
- `src/reapi/service.rs`: lock-free splice admission and reconstruction
- `src/store.rs`: atomic reverse references and eviction cascades
- `src/backfill/pass.rs`: dependency-preserving replication order

## Off Limits

- Wire compatibility with Bazel's Remote Execution Application Programming Interface
- Existing storage durability and last-write-wins semantics
- Global process resource budgets

## Constraints

- Introduce no mutex or read-write lock for content-defined chunking.
- Bound recipe size, chunk count, request probes, background probes, verification concurrency, and streaming buffers.
- Reject or safely miss incomplete composites; never return partial bytes.
- Preserve action-result, recipe, and chunk referential integrity through eviction and replication.
- Add no dependency solely for benchmarking.

## What's Been Tried

- Baseline uses an atomic four-slot verification guard and commits reverse references in the same RocksDB batch as recipes: median 18,492,708 nanoseconds for 128 concurrent recipe applies plus high-fanout eviction.
- Reusing decoded chunk identifiers during cascade deletion regressed the median to 20,467,084 nanoseconds and was discarded.
- The restored implementation measured 17,583,667 nanoseconds and passed every focused correctness gate. The variance is too high to claim a speedup, so the result only confirms that the bounded path remains fast under the benchmark workload.
- The final lock audit replaced the shared batch-read materialization mutex on the chunking path with an atomic request budget and independent response-lifetime permits. This removes lock contention without weakening either the per-request or process-wide memory bound.
