# Borrowed-volume prototype qualification

This record concerns the disposable prototype in this directory. It is not
approval to enroll hosted nodes, ship the experimental segment layout, remove
per-device backing, or declare the production sharing backend implemented.

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
