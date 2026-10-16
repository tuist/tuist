# Verified REAPI throughput client

This is a standalone Go module for black-box ByteStream measurements against Kura, Buildbarn and BuildBuddy. Use `GOWORK=off` so the enclosing repository workspace does not change dependency resolution. See [README.md](README.md) for the frozen workload and qualification limits.

## Contracts

- Keep one standard REAPI/ByteStream timed transport for every implementation: identical deterministic unique bytes, SHA256 digests, 64 KiB upload chunks, connection count and concurrency.
- Generate each fresh corpus before the write clock, require missing-all first, retain every failed operation as failure, count transient retries and their delays, and verify complete read lengths and SHA256 hashes. Do not turn repeated unique writes into hits.
- Separate acknowledgment, full-replica availability, replica qualification, warm verification and timed reads. A peer read through a distributed frontend is not proof of a local replica.
- `buildbuddy_local.go` is a pinned local-backend qualification codec, not a faster timed transport. Preserve the pinned field numbers, negative preflight, missing-zero convergence, rejection of shared-storage references and full-byte integrity checks. Fail if an upstream protocol change is incompatible.
- Corpus rounds release prior payloads and use a fresh seed. Multi-round qualification keeps bounded digest-only records and finally verifies every accumulated digest on the primary and actual replicas; per-round verification alone is not full retained-corpus proof. Bound count × rounds before allocation. Keep the corpus ceiling, RPC/operation deadlines and client cgroup/GC guidance. No global environment mutation in tests.
- Do not claim OS-cold reads, crash-equivalent durability, physical host isolation, steady-state compaction or fleet leadership from finite shared-VM runs.
- Tests: `GOWORK=off go test ./...`. Keep malformed wire, local-only integrity and bounds tests alongside verifier changes.

Server implementations, competitor sources and binaries, credentials, runtime images, dated captures and raw results are outside this directory. Keep those artifacts in an ignored run directory. No competitor hot-path modification is permitted for a comparison.
