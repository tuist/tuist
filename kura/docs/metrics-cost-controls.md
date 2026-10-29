# Public latency aggregation

Kura exports an additive public transport histogram alongside the existing route
histogram. Both use the same bucket constructor. HTTP and gRPC have cached
handles; future transports use the registered family. Each public request must
observe both distributions exactly once, including cached ByteStream/REAPI paths.

The route family carries `latency_aggregate="true"` to identify a runtime that
also exports the complete transport distribution. Self-hosted scrapers retain
the full route histogram. Hosted filtering is a separate, default-off rollout;
see the [monitoring guide](../../infra/helm/k8s-monitoring/README.md).

## Verification

Run the Bazel metrics suite, clippy, and Rust formatting. The monitoring chart's
regression tests exercise its production Alloy version against a local
Prometheus receiver with both migration flag values and test every migrated
query across old, new, mixed, same-region mixed, and rolled-back runtimes.

Before merging runtime changes, compare release builds against the merge base
with `main` using the same sustained workload on the same host, sequentially.
The existing `test/e2e/provider-topology/resources.mjs` fixture measures a
three-node mesh with real peer mTLS, periodic metrics sampling, and cooldown.

Record all four resource axes in the pull request description:

- CPU per completed request/byte, separating sustained load from seeding,
  convergence, and cooldown when whole-run totals vary.
- Peak and settled anonymous/allocator memory, transient reservations, pressure
  tiers, and shedding. Equal residency bought by refusing more work is a regression.
- Data-volume size, retained corpus, and segment refresh/write amplification.
- Client and peer payload egress plus interface transmit bytes.

Repeat noisy comparisons and use interleaved baseline/changed runs rather than
claiming improvements from one sample. Hold certificates, node names, workload,
and configuration constant when isolating a suspected CPU regression.

The source adds one histogram lock per public request; the collector migration
flag does not disable that observation. A bounded HTTP/mTLS fixture does not
qualify saturated gRPC contention, long-term retention, N-1 capacity, or a
physical private underlay. Watch CPU per request/byte, anonymous memory,
reservations, pressure, and shedding on a runtime canary before broad rollout.
