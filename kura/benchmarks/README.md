# Kura cache benchmarks

## `cas_ab.sh` — Kura vs legacy CAS A/B

Compares the Kura cache (bare-metal, local-NVMe content-addressed store) against
the legacy Kamal cache (S3 write-through) over the real customer HTTP plane, using
the shared `/api/cache/cas/{id}` contract both implement.

It measures three things:

- **Hit latency** — small-object `GET` p50/p90/p99, warm (reused connection) and
  cold (fresh TLS per request).
- **Single-stream throughput** — `POST`/`GET` MB/s medians across a few blob sizes.
- **Aggregate throughput** — many parallel streams, to find the real ceiling that a
  single latency-bound stream hides.

Endpoints and auth are resolved from `tuist cache config` (the `kura` client feature
flag selects the Kura endpoint; its absence selects legacy), so nothing is hardcoded.

Run it via the `Kura Cache Benchmark` workflow (`.github/workflows/kura-cache-benchmark.yml`),
which dispatches on `ubuntu-latest`. It hits Kura's **public customer endpoint** — the same
path an external CLI takes — from a datacenter-grade uplink. (In-cluster `tuist-linux` runners
can't reach the box's public IP: cluster egress to it is blocked, and in-cluster cache clients
use the private path instead.) Results are written to the workflow job summary.

Note the CI runner's distance to a region skews absolute latency/throughput; the A/B between
the two backends from the same runner is the meaningful signal. For absolute numbers, run from
a host close to the target region.

It writes content-addressed junk blobs into the resolved account's **production** cache
on both backends (modest volume, reclaimed by normal retention), so it is a manual,
operator-run benchmark, not part of the automated suite.
