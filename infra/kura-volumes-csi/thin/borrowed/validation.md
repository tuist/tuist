# Borrowed-volume prototype qualification

This record concerns the disposable prototype in this directory. It is not
approval to enroll hosted nodes, ship the experimental segment layout, remove
per-device backing, or declare the production sharing backend implemented.

## Recovery follow-up and second matched comparison

[Run 40736770879](https://github.com/tuist/tuist/actions/runs/40736770879), source
`74f0000d4dd5eb982c8bf896b2ec93862cb0ad33`, passed in **761.85 seconds** with
**94 assertions**, **30,400 comparison requests**, zero reported failures and
verified cleanup. It includes all child API checks described below plus:

- A capacity-denied create can be cancelled after CSI reconstruction; its
  cryptographic identity remains retired and the parent can grant another unit.
- Seven children plus their parent fill the eight-device profile. A ninth device
  is refused without increasing commitments. All eight filesystems received
  2,048 scattered 4 KiB writes at 512 KiB spacing, deliberately amplifying thin
  allocation relative to quota usage.
- The full snapshot retained **9,294,577,664 mapped bytes** (8.66 GiB),
  **17,186,816 metadata bytes** (16.39 MiB) and **22,011,707,392 committed bytes**
  (20.5 GiB). Checksums survived CSI reconstruction. Normal parent deletion,
  without an allocator-side drain, removed all eight detached devices and
  returned commitments to zero.

The second VM repeated the same five-layout forward/reverse comparison with
13 GiB aggregate virtual size. Do not combine its absolute throughput with the
first VM's values; the shared baseline differs substantially between VMs.

| Measurement | Shared XFS | Thick LUKS/XFS | Thin LUKS/XFS | Two thick units | Two thin units |
| --- | ---: | ---: | ---: | ---: | ---: |
| 6 GiB upload churn, MiB/s | 241.54–242.20 | 241.41–242.31 | 165.65–166.71 | 241.54–241.99 | 165.28–166.86 |
| 4 MiB PUT p95, ms | 199.10–233.62 | 192.28–203.62 | 297.82–301.98 | 197.30–199.87 | 293.72–293.92 |
| 1 GiB checksum reads, MiB/s | 341.57–359.45 | 351.92–353.04 | 356.76–361.83 | 341.02–344.24 | 340.30–350.42 |
| Runtime CPU seconds, ordinary run | 18.71–19.06 | 19.26–19.33 | 19.37–19.58 | 19.27–19.33 | 19.68–19.83 |

Thick units overlap the shared baseline in this VM; thin units are approximately
31% below thick units during upload churn. This strengthens the case for measuring
thick units on the intended hardware before choosing thin provisioning. It is
still a loop-backed mechanism/application experiment, not a staging NVMe result.

A subsequent code review found an additional interruption point: a mount can
succeed before quota setup persists its staging path. Recovery now resolves the
CSI-owned deterministic child path instead of treating an empty record field as
proof of no mount. A targeted real-stack rerun injects this quota failure and
checks cancellation only credits backing after verified detach/delete. That
follow-up passed in [40741254572](https://github.com/tuist/tuist/actions/runs/40741254572),
source `d6ec6223007`, in **110.38 seconds**: **71 assertions**, zero failures,
verified container and backing cleanup. It deliberately skipped benchmarks;
performance numbers above still refer to the earlier matched run.

## Configured device-count and cold-pool recovery qualification

[Run 40739087937](https://github.com/tuist/tuist/actions/runs/40739087937), source
`c96dedee9e1fa059d79f850a5d44c2597dda4a43`, passed in **1,569.31 seconds** with
12 aggregate assertions and verified cleanup. It used a private 384 GiB thin
pool, 512 MiB metadata and 128 fully backed 256 MiB useful-cache devices. Each
received 64 scattered 4 KiB writes at 8 MiB spacing. A 129th device was refused
despite spare data commitment; an injected metadata-reserve crossing withdrew
healthy admission and refused further allocation.

All 128 closed mappings and the deactivated pool recovered their LV identities
and file checksums after cold pool activation. The cold activation/restaging
phase took **91.99 seconds**. The full snapshot charged **15,569,256,448 mapped
bytes**, **17,575,936 metadata bytes**, and **352,187,318,272 committed bytes**.
Normal deletion returned data usage and commitments to zero; the empty pool
retained its normal metadata baseline. This does not test a fully mapped 384 GiB
pool, worst-case fragmentation, physical power loss or a Kubernetes node reboot.

A full mounted observation took **22.55 seconds** at 128 devices in this VM.
That is a scalability limitation: the current implementation invokes host tools
per device while holding its pool lock. Do not infer low-latency allocation or
suitable pressure-control cadence from the passing metadata/recovery checks.
The staging fixture uses an eight-device profile; production scale needs an
explicit observation/operation latency budget and qualification against it.
Source `170e555be89` avoids reactivating already-active LVs during accounting
(the kernel status query does not need device-node repair). Inactive volumes
still activate normally; missing status fails closed. Local Go tests and vet
passed. Separate metadata and child-lifecycle runs are checking the change,
including a five-second full-observation gate; results remain pending.

## Child API and matched thick/thin comparison — October 28

[Run 40733165768](https://github.com/tuist/tuist/actions/runs/40733165768), source
`ce0cb6914e9e6cd0ac43629428e88b376b2035b7`, passed the patched runtime's Clippy/build
and the actual CSI/LUKS/XFS stack test in **1,052.90 seconds**. All **65 assertions**
passed. Ten comparison samples made **30,400 authenticated HTTP requests**, with
zero reported failures. The report contains no failure, all fixture containers
were removed, and the driver log confirms `BORROWED_CLEANUP_COMPLETE=true`.

Unlike the earlier fixture, this run uses the actual fenced `POST /v1/units`
implementation and durable parent/child identities. CSI owns control-file writes,
encryption, child publication and deletion. It passed hot publication into a
running runtime, response replay without duplicate allocation, stale-generation
rejection, closing/reopening parent and child mappings with stable LV identities,
replacement-pod fencing, checksum recovery, open-unlinked-reader release refusal,
CSI reconstruction during incomplete release, exact retry after close, prevention
of released-ID reuse, and transfer to another tenant's independently keyed child.
Both base identities survived and final commitment returned to zero. The restart
is reconstruction of the driver object plus real mapping close/reopen, not a
kubelet, containerd or node reboot. Keys remain fixture-derived: this run does not
qualify Kubernetes ownership or OpenBao integration.

All five layouts now have **13 GiB aggregate virtual size**, the same experimental
runtime binary, 4 GiB cache budget, one CPU, 768 MiB memory, and the same forward/
reverse workload. Multiple-volume layouts use two 6.5 GiB devices. Thin layouts
retain the existing project-quota/sizing profile; thick controls use the real
legacy thick CSI path without project quotas. This compares deployable storage
paths, not encryption in isolation or identical enforcement configurations.

| Measurement | Shared XFS | Thick LUKS/XFS | Thin LUKS/XFS | Two thick units | Two thin units |
| --- | ---: | ---: | ---: | ---: | ---: |
| 6 GiB upload churn, MiB/s | 109.70–125.23 | 113.98–114.50 | 86.26–90.91 | 107.97–108.28 | 83.66–89.60 |
| 16 KiB PUT p95, ms | 7.07–7.41 | 8.00–8.31 | 7.43–8.97 | 7.74–8.71 | 8.18–8.55 |
| 4 MiB PUT p95, ms | 359.31–385.60 | 306.14–315.19 | 512.40–524.44 | 451.70–468.98 | 613.05–643.27 |
| 1 GiB checksum reads, MiB/s | 432.29–434.70 | 433.30–433.92 | 427.37–428.02 | 435.89–437.11 | 424.52–429.43 |
| Runtime CPU seconds, ordinary run | 16.00–16.56 | 16.41–16.43 | 16.55–16.85 | 16.51–16.71 | 16.62–17.06 |

Churn means upload throughput while filling beyond the cache budget and evicting;
it is not download throughput or whole-build duration. At sample midpoints,
thin units are about **20% slower than thick units**, while thick units are about
**8% below shared XFS**. Shared-XFS throughput varied substantially between its
two samples. These loop-backed VM results justify retaining the thick-unit option;
they do not select a production winner or establish hosted performance, memory
cost, hit rate or regional density. Paris NVMe measurements are still required.

Follow-up source `74f0000d4dd5eb982c8bf896b2ec93862cb0ad33` adds cancellation of
unadvertised failed creates, detached-child cleanup on parent deletion, durable
unstage completion, recovery-record validation and an enforced seven-child limit.
Local driver tests, Linux compilation and `go vet` passed. Its separate VM run
also passed eight-device scattered-write/recovery qualification, recorded above.
The configured 128-device metadata profile passed the separate qualification below.
Do not infer these newer checks passed from run 40733165768.

The child key-authorization tests passed locally: **35 ExUnit tests** across the
issuance controller and key management, including separate child keys, sealed AAD,
explicit parent opt-in, live PVC UID replacement and malformed identities. They
use mocked Kubernetes/HTTP dependencies and do not replace the staging test.

Staging-only StorageClass and TokenReview reviewer identity prerequisites were
installed by [40737753180](https://github.com/tuist/tuist/actions/runs/40737753180).
The prior attempt [40737492748](https://github.com/tuist/tuist/actions/runs/40737492748)
selected the wrong GitHub deployment environment and failed before resource apply.
The corrected workflow uses the existing `server-k8s-staging` environment and
normal deployment lane. No hosted application image or enrollment changed.
Server/CSI images were built as downloadable artifacts in
[40734563091](https://github.com/tuist/tuist/actions/runs/40734563091); local fixture
runtime/CSI images were subsequently published under dedicated `kura-child-fixture-*`
tags after explicit user approval. The alternate host-containerd socket importer
was rejected and was not used. Native amd64 server release boot passed in
[40740703970](https://github.com/tuist/tuist/actions/runs/40740703970); this is not
full web-server readiness. An isolated three-voter OpenBao fixture and compiled
key endpoint are being qualified on staging; hardware measurements remain pending.

## Earlier fixture-only prototype (historical evidence)

## Method

The harness calls the actual CSI driver against its own private loop-backed VG,
with a 24 GiB thin data pool, 512 MiB metadata, 512 KiB chunks, 256 MiB data
reserve, 32 MiB metadata reserve and eight device slots. Each fixture volume has
a distinct derived key and runs LUKS2 + XFS with the current CSI sizing profile.
The key service is a test double; OpenBao and Kubernetes authorization are not
qualified by these runs.

Two instances each have a 4 GiB useful floor and a 16 GiB logical ceiling. A
borrowed unit adds 4 GiB useful capacity. The unchanged `Targets` function from
#14825 revision `34956ca681a3dc0dc257ee5b4d0d65814bd5f23d` chooses an 8/4 GiB
grant distribution, then a 4/8 GiB distribution when demand moves. The fixture
can back three units with its existing per-device overhead. This exercises the
target calculation, not the production `Agent`, discovery, leases or an
asynchronous allocator backend.

Logical ceilings sum to 32 GiB, but **existing virtual devices are never
physically overcommitted**. Each useful 4 GiB unit currently reserves a 6.5 GiB
virtual device. Two base volumes plus one borrowed volume reserve 19.5 GiB;
a fourth cannot fit under the 23.75 GiB usable pool budget. This deliberately
reuses the existing sizing profile, including 2 GiB workspace per device.
It is expensive at this test scale and must not be used to claim regional
capacity gains. Borrowed segment-only devices need a separately qualified sizing
profile; runtime staging workspace need not necessarily be duplicated.

Kura uses an experiment-only patch built in a disposable checkout. The patch
adds a specific borrowed-storage root to its existing I/O boundary, deterministic
segment-to-unit paths, multi-root startup recovery and targeted retirement through
normal writer barriers and eviction cleanup. Production runtime builds never
apply the patch. Containers have no capabilities and use a private shared parent
with host-to-container mount propagation. This is a necessary mounting primitive,
not a Kubernetes CSI parent/child publication implementation.

The transfer sequence retains an open descriptor after Kura unlinks its segment,
injects failed TRIM, restarts the CSI object and runtime, verifies retained data,
and requires normal unpublish/unstage/delete before credit. It also checks data
and metadata reserve refusal and two concurrent creates competing for one unit.
Reserve injection tests refusal, not filesystem recovery after actual exhaustion.

The comparison runs shared XFS / monolithic thin LUKS / multiple thin LUKS in
forward and reverse order. All use the same experimental binary (the opt-in is
disabled for the controls), one CPU, 768 MiB memory without swap, a 4 GiB cache,
the same JWT-authorized HTTP client, and a separate 1 GiB checksum-read corpus.
The ordinary workload includes 6 GiB of 4 MiB upload churn at concurrency eight,
plus small/large writes, reads and post-churn reads. Data is generated outside
timed phases. Provisioned sizes differ: the plain filesystem is 13 GiB,
monolithic thin is 10.6875 GiB (the 8 GiB useful-ceiling sizing profile), and the multi-volume
case has two devices sized for 4 GiB useful each. Therefore this is a bounded
application comparison, not equal-overhead/density or saturated-device proof.

Runtime cgroup CPU/memory/I/O counters are retained. Whole-VM CPU ticks include
the HTTP load client and host crypto workers; they are not runtime CPU alone.
There is no peer-replication workload or egress qualification. Warm reads, loop
backing and short samples do not establish cold-NVMe or production performance.

## Attempts and evidence

| Run | Source | Outcome |
| --- | --- | --- |
| [40717800708](https://github.com/tuist/tuist/actions/runs/40717800708) | `b4fdd727113` | Cancelled while the shared build runner was queued; no qualification. |
| [40718897505](https://github.com/tuist/tuist/actions/runs/40718897505) | `e7e5be1691c` | Build and Clippy passed. The base-volume workload passed; the borrowed-volume batch returned 64 HTTP 503s because its path was outside the configured storage roots. No comparison benchmarks completed. Teardown retained the backing after incomplete unmount cleanup. A missing `pipefail` incorrectly made the workflow green: this run is a failure, not evidence of a passed prototype. |
| [40721692541](https://github.com/tuist/tuist/actions/runs/40721692541) | `b7feebd2c42` | Stopped before compilation/stack tests because the selected Rust toolchain lacked rustfmt. No storage qualification. |
| [40723287535](https://github.com/tuist/tuist/actions/runs/40723287535) | `bbf3133d52b` | Passed: real-stack test, 53 assertions, six comparison samples, no reported cache failures and verified teardown. See results below. |

The corrected workflow explicitly installs rustfmt, registers only the borrowed
subtree, propagates the Go test's failure status, and independently checks the
JSON report, completed benchmarks and verified teardown marker. Cleanup retries
normal unmounts and retains backing when detachment cannot be established.

## Completed bounded qualification

Run **40723287535**, source **`bbf3133d52bf7f50edd501b1863ae92e4e1989e4`**,
passed the patched runtime's Clippy and optimized build, then the real CSI/Kura
stack test in 970.75 seconds on kernel `7.0.0-1017-azure`. All 53 assertions passed.
The six comparison samples completed **18,240 authenticated HTTP requests with
zero reported failures**, including checksum reads. Transfer-specific workloads
also passed; they are separate from that request count. The JSON report has no
`failure`, reports `containers_cleaned: true`, and the Go log ends with
`BORROWED_CLEANUP_COMPLETE=true` and `PASS`. No hosted storage was modified.

### Allocation transfer and failure containment

- The pinned #14825 `Targets` calculation moved useful grants from A/B **8/4 GiB
  to 4/8 GiB**. Both base LV identities survived, and the retained base corpus
  passed checksum reads after runtime restart. A borrowed corpus was also read
  after restart before its intentional eviction.
- Idle targeted drain completed in **0.504 s**, without an upload to force
  rotation. The held-open descriptor remained readable across unlink and runtime
  restart. Normal unmount correctly refused the busy filesystem.
- After unlink, the donor still had **1,162,870,784 mapped bytes** and the pool
  retained **19.5 GiB** of commitments. Failed TRIM, the busy unmount and a CSI
  reconstruction did not release that reservation. This is an externally held
  file descriptor, not a long-running HTTP reader or a node reboot test.
- After final close, ordinary deletion took **1.627 s**. The donor disappeared
  from authoritative inventory; total mapped data fell from **2,483,027,968** to
  **1,320,157,184 bytes**, exactly the donor's mapped allocation in this quiet
  interval. Commitments fell from **19.5 to 13 GiB**. The 6.5 GiB reservation
  released is distinct from the roughly 1.08 GiB of blocks actually mapped.
- Two concurrent creates competed for the released unit: exactly one succeeded.
  Reconstructing CSI retained that unpublished allocation's charge. Its later
  idempotent create/stage/publish took **1.927 s** (excludes the initial winning
  create). B then used **2,839,543,808 mapped bytes** on that new unit. Every
  transfer commitment was released at final cleanup.
- Injected data and metadata reserve crossings each made observations unhealthy
  and refused an actual CSI create. This qualifies refusal under the configured
  reserve checks, not actual metadata exhaustion or a worst-case device count.

### Application comparison

Two samples per layout, forward/reverse order, in the same VM:

| Measurement | Shared XFS | One thin LUKS/XFS volume | Base + borrowed thin LUKS/XFS |
| --- | ---: | ---: | ---: |
| 6 GiB upload churn, MiB/s | 96.89–98.87 | 79.99–80.24 | 73.91–74.88 |
| 16 KiB PUT p95, ms | 9.41–11.44 | 9.47–10.27 | 10.21–15.91 |
| 4 MiB PUT p95, ms | 489.69–504.38 | 598.75–730.46 | 605.15–720.29 |
| 1 GiB checksum-read corpus, MiB/s | 178.23–179.90 | 169.82–181.33 | 177.25–181.96 |
| Runtime CPU, seconds/ordinary run | 18.54–19.11 | 19.80–20.75 | 19.50–20.05 |
| Runtime cgroup peak memory, MiB | 371.79–376.97 | 372.03–388.28 | 368.78–382.02 |
| Runtime anonymous memory at ordinary-run end, MiB | 34.82–36.02 | 40.81–42.53 | 39.04–42.13 |

Churn is **client-upload throughput while cycling beyond the cache budget**:
6,144 MiB divided by the sum of 24 churn-PUT phase durations, at concurrency
eight. It is not download bandwidth or whole-build throughput. CPU and memory
cover the ordinary workload, before the separate checksum corpus. Memory peak
includes charged page cache; neither it nor final anonymous memory establishes
per-instance production overhead. Raw whole-VM CPU counters also include the
load generator and kernel workers, with no attributable idle baseline.

On sample midpoints, multiple volumes are **7.1% slower than monolithic thin
LUKS** and **24.0% slower than shared XFS** during churn. Runtime CPU is similar
to the encrypted control; reads overlap. This does **not** meet a claim of no
additional write regression. Two samples, different virtual sizes and a private
loop-backed cloud VM do not isolate the cause or predict production impact.
These absolute values must not be combined with earlier Paris staging or fscrypt
VM runs. A matched device-size comparison on the intended hardware is still
required. Smaller-capacity units may also increase eviction frequency and cache
misses during transfer; this fixture did not measure application build times or
steady-state hit-rate impact.

The run's `borrowed-stack` artifact contains raw results and the driver log;
`borrowed-runtime` contains the compiled binary and exact experimental patch.
For evidence identification, SHA-256 values are:

```
kura-borrowed-results.json  4e59ea2ae96db21436a2a7ec3095829a129b0c16a69da8f0a8ca4c67558e1548
kura-borrowed-driver.log    9502951706df680e9be298f1369faf1fe55274e5b3b95c7d4172e43f2761b729
```

Local CSI `go test ./...`, `go vet ./...`, Linux test-binary compilation, Ruby
syntax, exact patch application/rustfmt parsing, the pinned target fixture and
workflow actionlint checks also passed. A later harness-only cleanup guard checks
all private `.img` files for attached loops before removing the fixture root;
that defensive change is compiled locally, not included in the VM measurements
above. The runtime and benchmark workloads remain the measured revision.

## Interpretation and remaining decisions

Returning a complete backed unit uses deletion as the allocation boundary. This
principle also applies to **thick** LUKS/XFS units: thin provisioning is not
intrinsically required for this granularity of sharing. A matched thick-unit
control is a useful next comparison before choosing the final backend, especially
because earlier direct-I/O results found a thin random-read penalty. Do not infer
thick-unit performance from this thin prototype's application measurements.

This successful bounded prototype leaves production work: stable parent/child identity
and authorization, durable and fenced asynchronous grant operations, complete
retained-volume inventory, Kubernetes mount lifecycle, quota/overhead conversion,
unit-granularity fairness, larger device-count metadata/memory qualification, and
migration of existing monolithic volumes. OpenBao custody/recovery and staged
catch-up, destination-bound write acknowledgments and endpoint handoff remain
independent release requirements. The original single-filesystem requirement is
changed by this candidate, and that tradeoff must remain explicit.
