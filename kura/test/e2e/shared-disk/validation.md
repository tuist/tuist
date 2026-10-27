# Local validation — 2026-10-27

No staging or production resources were used. The feature remains disabled in
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
