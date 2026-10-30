# Staging validation — 2026-10-28

This run qualifies isolated shared-XFS storage fixtures on the Paris staging
node `tuist-tuist-kura-fleet-fm4h8-qmkn8`, in the existing `kura` namespace.
It does not enable a region, change production or establish per-tenant encryption.
OpenBao remains a future key-custody choice; this shared-XFS path does not call
OpenBao or retain the parked per-tenant LUKS boundary. The staging server's
OpenBao address was not configured when checked (configuration presence only;
no Secret values were read).

## Storage behavior and integration fixes

The run used real `scw-local-nvme` PVCs, the existing local-path provisioner,
XFS project quota accounting/enforcement and the Kubernetes-inventory allocator.
The allocator had a 24 GiB tenant cap and an additional 32 GiB filesystem reserve
on the node's 128 GiB data filesystem. These are bounded fixture settings, not a
recommended production reserve. Two runtime fixtures had 8 GiB floors, 16 GiB
ceilings, 2 GiB staging allowances, 1 CPU and 768 MiB memory limits.

- A grew to a 16 GiB quota while idle B's 8 GiB floor remained protected.
- Writing 1,500 8 MiB objects to A and 1,350 to B exercised contention and
  segment eviction. Recent objects were read and byte-verified.
- Open descriptors deliberately held approximately 14 GiB in A, including
  an unlinked allocation. A remained charged at 14.022 GiB, with B restricted
  to 9.978 GiB. Replacing the allocator pod did not release that charge.
- After closing the descriptors, both enforceable quotas settled at 12 GiB.
  Kernel quota observations, collected under the provisioner's lock with both
  lease files, proved reclamation before reassignment. Recent objects in both
  runtimes remained readable.
- Stopping the allocator beyond lease expiry refused a new write; the attempted
  key remained absent and an existing object was still readable. Renewal
  restored writes. Reducing the fixture capacity below the sum of floors also
  refused writes while preserving reads; restoring capacity recovered writes.
  This tested a capacity-policy failure, **not deliberate physical host exhaustion**.
- Replacing A's runtime pod preserved its PVC/data and issued a new pod-UID-bound
  lease; a recent pre-restart object still verified successfully.
- Deleting fixture PVCs used the real provisioner cleanup, releasing their
  blocks and inodes. XFS's remaining empty quota rows must not block new volumes.

The staging run exposed and fixed two integration defects:

1. Actual PV paths use `/opt/local-path-provisioner`, a bind mount of a directory
   on `/data`. Restricting every PV path to a textual `/data/` prefix rejected
   valid volumes. The agent now mounts the provisioner root read-only and accepts
   canonical, nonsymlink descendants only after checking they are on the same
   filesystem and retain a unique inherited project quota. Linux regression tests
   cover accepted paths, aliases, missing paths, symlinks and prefix siblings.
2. XFS keeps quota records after volume deletion. Treating every zero-hard-limit
   record as an active unbounded project stopped renewal indefinitely after
   cleanup. The agent now reads block and inode reports and ignores such a record
   only when both positively report zero use. Empty directories, open unlinked
   inodes, nonzero blocks and missing observations still fail closed.

An early observer combined leases from different allocator cycles and falsely
reported an over-issued sum. The kernel limits did not exceed the cap. The
observer was corrected to hold the shared quota lock while reading both leases
and the kernel report; the contention test then continued successfully. Failed
observer evidence was retained rather than counted as an application failure.

The final packaged allocator also rejected a zero-byte directory whose project
still owned one inode, stopping lease renewal. Removing that last inode restored
fresh authorization with the zero-use quota record still present.

All qualification pods/PVCs and their local-path PVs were removed through normal
provisioner cleanup; the isolated host control directory was removed afterward.
The seven original Kura pods retained their UIDs, and all four pre-existing
encrypted CSI PVs remained Bound. No existing driver/key service was removed.

Per-round benchmark and selected safety observations are preserved in
[staging-results.json](staging-results.json). Full temporary operational logs
were retained locally at `/tmp/kura-shared-evidence`; fixture credentials are
not committed.

## Benchmark method

Baseline: `ghcr.io/tuist/kura:sha-172ffef18648`; its Kura source tree matches
current main (`9ac6be6a35926b1b945fccb60acab79e9fe7f555`). Candidate:
`ghcr.io/tuist/kura:sha-d127fcf8c64a`. Later branch changes affect allocator,
packaging and tests, not that runtime's production source.

Both pods ran sequential traffic on the same staging node with identical
1 CPU/768 MiB limits, a 4 GiB configured CAS, 2 GiB staging allowance and 8 GiB
XFS hard quotas. Candidate had real renewed allocator leases with floor equal
to ceiling; baseline had sharing disabled. Both were standalone fixtures with
internal pod-IP traffic, no peer replication and no public ingress. This isolates
the sharing runtime overhead from dynamic capacity differences. The separate
contention test above exercises redistribution.

`benchmark.go` ran baseline/candidate/candidate/baseline, with eight workers,
2,528 requests per round and 6 GiB of unique churn writes. GET responses were
byte-verified. `/metrics`, cgroup CPU/memory/pressure, physical directory bytes
and network counters were sampled throughout; sampling continued for 20 seconds
after each run. CPU figures include the small measurement-exec overhead.
No host-wide caches were dropped. CPU throttling occurred at the identical
one-core limits, so these results characterize that limit, not raw NVMe speed.
Two rounds per build are not statistical proof of equivalence.


| HTTP phase | Baseline p95, ms (two rounds) | Shared p95, ms (two rounds) | Baseline MiB/s | Shared MiB/s |
| --- | ---: | ---: | ---: | ---: |
| small_put | 28.11–28.61 | 26.94–29.87 | 6.8–7.6 | 6.8–6.8 |
| small_get | 2.28–2.53 | 1.99–2.59 | 61.1–80.4 | 64.3–78.0 |
| large_put | 238.46–266.03 | 262.44–262.51 | 166.4–167.9 | 162.3–164.4 |
| large_get | 102.28–105.87 | 97.01–99.44 | 449.5–453.6 | 466.8–493.4 |
| post_churn_get | 101.66–111.10 | 111.60–123.65 | 441.2–468.2 | 398.0–424.4 |
| 6 GiB churn writes | — | — | 167.0–168.3 | 162.4–163.5 |

All **10,112 requests succeeded**. Mean churn throughput fell **2.8%** and mean runtime CPU rose **2.3%**. Small-object p95 remained similar. Immediate large reads were faster in these runs, but reads immediately after churn averaged **9.6% less throughput** (p95 averaged **10.6% higher**). These short read phases are noisy and do not establish a universal read regression or equivalence. Keep that observation visible; this is not a no-regression sign-off.

| Resource per equal 2,528-request workload | Baseline | Shared |
| --- | ---: | ---: |
| Runtime cgroup CPU seconds | 41.27–41.55 | 42.35–42.35 |
| Peak sampled process anonymous memory, MiB | 41.56–46.25 | 37.41–52.49 |
| Settled process anonymous memory, MiB | 17.30–20.19 | 21.36–24.90 |
| Peak sampled jemalloc allocated, MiB | 15.57–21.35 | 13.78–17.05 |
| Settled physical data-directory bytes, GiB | 3.54–4.00 | 3.52–3.76 |
| Transmitted pod network bytes, MiB | 521.34–521.69 | 521.58–522.01 |
| Maximum memory-pressure tier | 0.00–0.00 | 0.00–0.00 |
| OOM kills | 0.00–0.00 | 0.00–0.00 |

The allocator used 3.13–3.23 CPU seconds during each workload and 8.47–9.08 MiB anonymous memory at the sampled endpoints. It was active in both baseline and candidate rounds, managing the idle candidate during baseline, so that is a separate per-node cost rather than runtime overhead. This tiny inventory does not qualify fleet-scale agent cost. Pod transmitted bytes differed by about **0.05%** on average; peer replication was absent. Segment boundaries caused settled disk occupancy to vary; all requested recent objects verified, but lower occupied bytes are **not** claimed as a retention or density improvement. Twenty seconds of settling is not a long-running leak test.


## Larger working set and ByteStream

A separate 1 GiB HTTP working set (256 × 4 MiB, larger than the pod's 768 MiB
memory limit) completed 512 PUT/GET requests per build with no errors. Read
throughput was 483.6 → 438.1 MiB/s and p95 108.3 → 121.3 ms, a single-pair
9.4% throughput reduction. This reinforces the need to investigate the read
result rather than dismiss the short post-churn measurement.

The existing `grpc-upload-throughput/client` was built with a fixture-token
credential and `shared/` resource prefix. Eight workers shared one HTTP/2
connection; 256 writes followed by 256 verified reads ran for both 16 KiB and
4 MiB objects. All 2,048 requests returned OK:

| gRPC phase | Baseline requests/s | Shared requests/s | Baseline p95, ms | Shared p95, ms |
| --- | ---: | ---: | ---: | ---: |
| 16 KiB write | 386.30 | 403.33 | 32 | 30 |
| 16 KiB read | 8,002.27 | 6,158.67 | 1 | 1 |
| 4 MiB write | 33.56 | 32.68 | 299 | 325 |
| 4 MiB read | 80.54 | 72.13 | 146 | 137 |

To reduce short-burst timing effects, 4 MiB reads were repeated in ABBA order
with 2,560 requests per round against the same 256-object working set (10 GiB
served per round). All **10,240 reads verified**. Baseline sustained 69.03–69.93
requests/s (276.1–279.7 MiB/s); shared sustained 65.46–66.51 requests/s
(261.8–266.0 MiB/s): **5.0% less throughput on average**. Baseline p95 was
163–164 ms and shared 151–160 ms. Lower p95 does not cancel the lower completed
throughput. Received gRPC payload/framing bytes were equal within 23 bytes per
10 GiB round. These fixtures do not identify the cause of the throughput gap.

Across the HTTP churn, working-set and gRPC benchmarks, **23,424 measured
requests completed without errors** (plus uncounted readiness/warmup requests).
The safety-test writes deliberately refused during expiry/capacity failure are
expected assertions and are reported separately from these benchmark totals.

## Builds, packaging and remaining rollout gates

The runtime source was built by [the runtime image workflow](https://github.com/tuist/tuist/actions/runs/40658529726).
On code revision `9aec259bb32046789ff7482742ff66a06fad49f9`, full controller Go
tests/vet, Linux allocator regression tests, Helm lint/render, Rust formatting,
Bazel Compile, full Bazel Test and Bazel Clippy passed. The Linux allocator tests
also ran directly in the staging helper. At evidence capture, 39 PR checks had
succeeded and the long rollout-backfill/discovery-faults-handoff shards were
still running; this record does not claim a completed all-green CI suite. A preexisting shared-disk Rust test's
initial statfs observations were made deterministic so unrelated runner disk
activity could not arm its no-progress guard before its intended test phase;
production runtime logic was unchanged by that correction.

The [controller/disk-agent image workflow](https://github.com/tuist/tuist/actions/runs/40662689395)
published SHA-only images for this branch; `latest` is now main-only. The final
packaged `ghcr.io/tuist/kura-disk-agent:sha-9aec259bb320` ran on staging with a
read-only root filesystem, renewed the existing candidate grant, and served the
long gRPC validation. Its observed platform digest was
`sha256:9f620b5a469d8bcb1a3c3ab11a3f143c4b893876dd18051f9b51aa61824be7c1`.
The fixture used the existing controller service account, an isolated lease
directory and an explicitly scheduled pod; this does not qualify the chart's
new service-account/RBAC or node enrollment as a full Helm DaemonSet rollout.

**Conclusion:** the scoped storage correctness checks passed, and writes showed
small overhead. Reads still measured slower in both short and sustained tests.
This is not a no-regression or broad-production-rollout sign-off. Keep sharing
disabled pending read-performance investigation, full controller/server
admission and existing-volume conversion rehearsal, production reserve and
inode-pressure qualification, and representative multi-replica HTTP/gRPC
traffic through the actual endpoint/catch-up/handoff path. Node loss/reboot,
maximum-size module uploads and fleet-density gains were not established here.
No LVM migration, encryption validation or OpenBao validation occurred in this
shared-XFS run. Regional capacity/memory projections remain planning scenarios.


# Local validation — 2026-10-27

The 2026-10-27 local run used no staging or production resources. The feature remains disabled in
all regions and managed Helm values.

## Behavior

The final `run.mjs` run passed all assertions on Ubuntu with real XFS project
accounting/enforcement, two Kura runtimes and the node allocator. The filesystem
had a 12 GiB tenant cap, two 4 GiB floors and two 8 GiB ceilings. The compact
fixture used 128 MiB staging; managed instances require at least 8 GiB floors
and retain 2 GiB staging.

- A grew to an 8 GiB quota while B's unused 4 GiB floor stayed reserved.
- With open unlinked files held, A used 7.000 GiB against a 6.896 GiB target.
  Its enforceable quota remained 7.404 GiB and B stayed at 4.596 GiB: the
  requested shrink was not spent twice.
- A new allocator generation was observed while those files remained held;
  restart did not release their charge.
- Closing the descriptors allowed physical reclaim and B's pending growth.
  Both quotas reached 6 GiB, their sum stayed within 12 GiB, and the most recent
  objects in both runtimes remained readable.
- After 17 seconds without the allocator, a new write was refused and the
  attempted object remained absent. Existing reads worked. Renewing leases
  restored writes and subsequent reads.

The workload completed 900 8 MiB writes to A and 650 to B with up to four
concurrent writers. The run's evidence directory was
`/var/tmp/kura-shared-disk-cqhdUM` in the disposable VM; its result and stdout
were copied to the local validation artifacts before stopping the VM.

Earlier real-XFS runs exposed two implementation issues that were fixed before
this passing run: nominal segment count alone did not account for all retained
physical blocks, and a larger quota could leave a runtime stuck with a pressure
cap learned at its smaller allocation. Regression coverage now checks physical
reclaim, no-progress suspension/resumption and recovery after a larger grant.
The fixture also measures held blocks explicitly and waits for a new allocator
generation, avoiding timing-dependent assertions about transient targets.

## Tests and builds

- Full controller Go suite: `go test ./...`.
- Linux: `go test ./cmd/disk-agent ./internal/diskallocator`,
  `go test ./controllers -run TestSharedDisk`, and `go vet ./...`.
  The inventory test covers 36 replicas with three API requests, bounded caching,
  and rejected PV/claim ownership mismatches.
- Rust: `cargo test --release disk_budget`, `cargo test --release shared_disk`,
  and `cargo test --release disk_pressure`: 12 tests passed.
  `cargo clippy --release --all-targets -- -D warnings` passed.
- Server admission, capacity and Kubernetes-controller manifest suites:
  **219 tests passed**, using `TUIST_HOSTED=1` and dedicated local PostgreSQL
  and ClickHouse databases. Repository dependency versions and lockfiles were
  preserved. Elixir parsing and Styler formatting passed.
- Runtime and disk-agent Dockerfiles built; the enabled Helm DaemonSet rendered.

Rust validation used the repository Dockerfile/Cargo toolchain because local
Bazel rejected the installed Xcode SDK's absolute `SDKSettings.json` include.
The server's existing local test database had conflicting migration history;
the focused tests ultimately used isolated databases. Kubernetes placement/rendering were
unit tested; this was not a live Kubernetes DaemonSet rollout.

## Resource comparison

`../quota-pressure/resources.mjs` ran sequentially on the same local Docker host,
with the test VM stopped. The baseline used `kura:disk-baseline`; the changed
image used `kura:disk-after` with `KURA_RESOURCE_SHARED_DISK=1`. Both had two
replicas, the same effective 3 GiB ring, 1.5 GiB container memory limits and the
same workload: 320 writes and 512 verified reads of 8 MiB objects, four reads
per second per replica and four writes per second, followed by 30 seconds idle.
Both runs had zero failures and returned 4 GiB of verified read data.

| Aggregate across both runtimes | Before | Shared leases enabled |
| --- | ---: | ---: |
| Peak process RSS | 214.1 MiB | 219.7 MiB |
| Peak anonymous cgroup memory | 173.6 MiB | 178.2 MiB |
| Process CPU time | 44.36 s | 45.22 s |
| Final apparent data-directory bytes | 5,369,724,006 | 5,369,724,251 |
| Transmitted network bytes | 7,009,686,659 | 7,010,321,608 |
| Paced load duration | 63.860 s | 63.884 s |

This single paired run showed approximately 2.6% higher peak RSS, 1.9% more
process CPU time, essentially unchanged stored bytes and 0.009% more transmitted
bytes. It is a controlled runtime-overhead measurement, not a fleet performance
estimate. Synthetic leases keep capacity equal and do not enforce XFS quotas or
measure the host agent/API cost; the separate real-XFS run verifies physical
allocation behavior. Maximum-size module uploads, production reserve selection,
existing-volume conversion and automatic movement are not qualified by these
measurements.
