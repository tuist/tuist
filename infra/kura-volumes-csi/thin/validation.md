# Thin stack qualification

Date: 2026-10-27. The actual conservative CSI implementation has completed the
local and hosted staging qualification below. The hosted performance gate failed. The original
mechanism experiment remains evidence against physical overcommit.

## Decision from the experiment

**Physical overcommit is not qualified. Use ceiling backing as the initial
implementation target.** XFS project quotas worked, but they did not bound
physical thin allocation. Fragmented files retained whole thin chunks even
after successful trim with discard enabled. This prevents treating quota
reductions or successful trim as transferable physical capacity.

The original Ruby harness does not exercise the CSI API or ledger. It deliberately overcommits virtual sizes to explore the failure
case in a disposable VM. That is not the proposed conservative admission mode.

## Actual CSI qualification

The actual driver completed its disposable Linux qualification in **122.54 s**,
including benchmarks. `internal/driver/thin_integration_test.go` uses the real
command runner, mount table, LUKS, XFS and LVM code; only key retrieval supplies
random in-memory fixture keys. It also serves and reads the root-only Unix API.
The pool had 16 GiB data, 512 MiB metadata, 64 KiB chunks, 256 MiB data reserve,
32 MiB metadata reserve and four slots. The VM had four CPUs and 4 GiB RAM.

- Reclaiming A released **805,371,904 bytes** in both volume and pool counters;
  writing 768 MiB to B increased pool use by exactly that amount. Open-unlinked
  files remained charged. Injected trim failure returned an error.
- Lowered quotas rejected both fallocate and actual writes. The test rejects
  unrelated I/O failures as quota evidence and verifies subsequent writes work.
- Interrupted creation retained a full reservation until explicit deletion.
  Interrupted quota application recovered the durable intent on re-stage.
- Lost-response retries were idempotent. Stale generations and another pod UID
  were rejected. Reconstructed driver state and unstage/reopen preserved the
  SHA-256-verified payload and stable identity.
- Four concurrent creates admitted only two additional devices, reaching the
  four-slot limit. Increased data/metadata reserve requirements refused new
  admission. Retained volumes stayed charged; active deletion was refused;
  confirmed deletion released exactly one complete virtual reservation.
- The HTTP observation succeeded over a `0600` Unix socket. Cleanup removed the
  fixture VG and verified loop detachment before unlinking the backing file.

Earlier attempts found and fixed empty-pool device-mapper naming and unsupported
`lvcreate --zero` on thin children. Another attempt exhausted the laptop's backing
disk and caused VM I/O errors and an XFS shutdown. That run was rejected as
qualification. After backing space recovered and the VM restarted, the complete
suite passed. Physical device errors remain outside quota admission guarantees.

Cross-compile `go test -c ./internal/driver` for a disposable Linux VM with
LVM, cryptsetup, XFS tools and fio, then run:

```sh
sudo env KURA_THIN_DISPOSABLE_VM=1 KURA_THIN_BENCHMARK=1 \
  ./driver.test -test.run '^TestThinRealStack$' -test.v -test.timeout 12m
```

### Actual driver performance comparison

The control uses the thick CSI path's normal XFS defaults, without project
quotas or discard through LUKS. The thin path uses the implemented profile.
Runs are ordered thick/thin/thin/thick, with a 256 MiB fio file, direct I/O,
QD32 and five seconds per operation. The same loop-backed VM is used throughout.
These short samples do not establish hosted NVMe or Kura HTTP performance.

| Operation | Thick CSI | Thin CSI |
| --- | ---: | ---: |
| Sequential write | 4.33–5.65 GiB/s | 3.83–5.30 GiB/s |
| Sequential read | 6.55–7.42 GiB/s | 5.55–5.64 GiB/s |
| Random write, 4 KiB | 76.0–157.0k IOPS | 117.5–131.4k IOPS |
| Random read, 4 KiB | 211.0–389.8k IOPS | 214.1–284.7k IOPS |
| Eight 16 MiB write/fsync/delete cycles | 182–215 ms | 6,049–6,234 ms |

The churn comparison includes full CSI flush/trim/accounting verification after
**each** thin deletion; thick performs ordinary deletion. This exposes substantial
control-operation overhead, not just storage latency. The future allocator must
batch reclamation outside the foreground request path. Batching and final cache
workload latency are not qualified by this microbenchmark. Sample variability
precludes a single reliable percentage regression from these VM results.

Data/metadata pressure cases verify admission refusal before exhaustion. They
do not establish safe shared overcommit or recovery from actual pool metadata
exhaustion. The old shared-XFS capacity gains, regional memory measurements and
final runtime filesystem-overhead profile remain unvalidated for thin storage.

## Hosted staging qualification — 2026-10-27

The safety and performance runs below used the real CSI service, live PVC/PV
ownership, projected workload authentication and server-issued encrypted volume
keys on staging. CSI image: `sha-3711f4bf393d`; Kura runtime:
`sha-6e7fbe5cf700`. The controller's original candidate exposed a migration
reservation bug; its correction `13002218f364` was deployed and exercised below.
Production was not changed. **Neither uninterrupted migration nor the no-performance-regression gate passed.**

### Measured thick versus thin performance

Both controls ran on `tuist-tuist-kura-fleet-fm4h8-qmkn8`, using its Samsung
MZVLB1T0HALR NVMe devices and Linux `6.8.0-146-generic`. Both virtual LVs were
6.5 GiB (6,979,321,856 bytes), with per-volume LUKS2. Thick used the existing
CSI filesystem defaults; thin used 64 KiB pool chunks, discard through LUKS,
XFS project quotas, a 64 MiB log and reflinks disabled. The pool was 16 GiB
with 512 MiB metadata, 1 GiB data reserve, 64 MiB metadata reserve and four slots.
These are paired tests of the thick implementation versus this thin implementation,
not a new comparison with pre-PR shared-XFS production.

The runtime image, auth, 1-CPU limit, 256 MiB memory request, 768 MiB memory
limit and actual segment-ring budget were identical. A separate on-node client
avoided kubectl port-forward and WAN timing. The order was thick/thin/thin/thick.
Each run performed 2,528 requests at concurrency eight: small 16 KiB writes/reads,
large 4 MiB writes/reads, 24 batches of 256 MiB unique writes crossing the cache
ring repeatedly, then checksum reads of the final batch. Object generation is
outside timed phases; reads include warm cache. **10,112 requests passed with
zero HTTP failures or checksum mismatches.**

| HTTP operation | Thick, two samples | Thin, two samples |
| --- | ---: | ---: |
| 16 KiB PUT p95 | 31.72–36.63 ms | 29.38–40.19 ms |
| 16 KiB GET p95 | 1.93–2.85 ms | 2.25–3.00 ms |
| 4 MiB PUT p95 | 254.82–256.44 ms | 247.25–252.23 ms |
| 4 MiB GET p95 | 91.60–93.66 ms | 97.98–101.29 ms |
| Six-GiB eviction-write throughput | 157.19–161.02 MiB/s | 156.26–158.65 MiB/s |
| GET p95 after eviction churn | 105.17–110.09 ms | 111.82–112.06 ms |

Large-read p95 was about **7.6% higher** using the mean of the two samples.
Write and eviction throughput were similar. This is not statistical proof of
unchanged request performance: each runtime hit its CPU quota. Per-run CPU use
was 41.88–42.95 seconds thick and 42.72–43.40 seconds thin, with 33–42 seconds
of reported throttling. Cgroup memory peaks were about 372 MiB on the first
runs and 640 MiB thick / 649 MiB thin after the repeated runs; no OOM events
occurred. These bounded cgroup measurements do not establish regional memory
or admission gains.

Direct-I/O fio 3.36 used a separate 512 MiB file inside each fixture filesystem,
libaio, QD32, 10 measured seconds plus two seconds ramp-up, and the same
thick/thin/thin/thick order. Runtime containers retained their 1-CPU limit;
these results are for that resource profile, not unconstrained device ceilings.
All 16 samples completed without fio errors.

| Direct I/O | Thick | Thin | Change in sample means |
| --- | ---: | ---: | ---: |
| 1 MiB sequential write | 2,203–2,211 MiB/s | 2,159–2,196 MiB/s | −1.3% |
| 1 MiB sequential read | 3,723–3,851 MiB/s | 2,550–2,588 MiB/s | **−32.2%** |
| 4 KiB random write | 61.8–62.0k IOPS | 45.7–46.2k IOPS | **−25.7%** |
| 4 KiB random read | 64.9–66.3k IOPS | 48.1–48.4k IOPS | **−26.5%** |

Random-read p99 increased from 0.840–0.864 ms to 1.139 ms; random-write p99
increased from 0.922–0.930 ms to 1.286 ms. Random reads spent approximately
99% of the fio process's CPU in user/system time. The extra storage-layer cost
is material under this CPU budget even though the HTTP write workload largely
hid it. **Do not promote this result as regression-free.** Tuning or a reviewed
performance tradeoff and another paired run must precede broad enrollment.

The reusable authenticated workload is `cmd/cache-bench`; fio can be reproduced
with `--size=512M --ioengine=libaio --direct=1 --iodepth=32 --time_based=1
--runtime=10 --ramp_time=2 --group_reporting=1 --output-format=json`, using
`write/read` with `--bs=1M` and `randwrite/randread` with `--bs=4k`. Use only
isolated fixture files; never drop host caches on a shared node.

### Live safety evidence

- XFS project quota stopped real writes at **2,281,701,376 bytes**, below the
  **3,623,878,656-byte** virtual LV. The 16 GiB pool was healthy and far from
  full. This kernel returned ENOSPC for the project limit; the quota counter
  exactly matched its hard limit, and subsequent writes after cleanup worked.
- Deleting a 768 MiB payload while holding its descriptor open, then trimming,
  released **zero** mapped bytes. After closing the descriptor, the first
  reclaim response conservatively credited **201,457,664 bytes** while discard
  was still completing. Later volume and pool counters both confirmed exactly
  **805,306,368 bytes** released. Another volume then consumed that capacity.
  Full backing commitments remained unchanged throughout.
- CSI restart preserved commitments. Removing the workload closed both LUKS
  mappings; unmounted retained volumes stayed fully charged. Cold re-stage
  through the live key service preserved SHA-256 data, LV/pool identities and
  the reduced quota. The new pod UID invalidated the old pod's reclaim request;
  stale grant generations were also rejected.
- Concurrent PVC provisioning admitted two further volumes, reaching four
  fully backed devices. A fifth was unschedulable for insufficient
  `tuist.dev/kura-disk`. Concurrent deletion released exactly the two confirmed
  removed commitments. No actual shared-pool exhaustion was induced.
- After HTTP eviction churn, mapped use was **3,378,511,872 bytes** while quota
  use was **2,172,420,096 bytes**, demonstrating why filesystem usage cannot
  replace physical accounting.

This run used the live server's **`tuist_root`** wrapping provider (fixture key
version 1). It validates the real key-service/CSI path but does **not** requalify
OpenBao custody. Earlier OpenBao-specific evidence remains separate. No keys,
projected tokens or ciphertext were printed or exported for inspection.

### Migration outcome: storage completed, continuity gate failed

The isolated two-replica instance moved from 4 GiB encrypted file-backed PVCs
on Canada staging to two thin PVCs on the Paris node. Only the Canada source
was cordoned and selected with `tuist.dev/kura-lvm-migrate=true`; ordinary node
evacuation was not used. Before source selection, the migration gate preserved
both source pod UIDs and the legacy template. The landing pool backed both
6.5 GiB virtual devices; no whole-fleet duplication was needed.

The first candidate stalled safely before deleting either source replica:
`reconcileDataStorageResize` compared the 6.5 GiB scheduler reservation against
the 4 GiB useful cache claim and repeatedly reapplied the held template. Commit
`13002218f364` compares against `diskReservation(instance)` instead. Both file-to-thin
and thick-to-thin regression cases fail with the old comparison and pass with
the correction. Controller tests/vet and the [image build](https://github.com/tuist/tuist/actions/runs/40551337577)
passed. This correction was exercised by the actual migration, not just mocks.

Paris has a different runner-cache taint from the Canada source. The first
replacement remained Pending until the isolated fixture's instance, held template
and pending pod gained that toleration. No host taint was removed. The fixture
also disables the optional memory-ceiling resource, which Paris does not advertise.
A rollout preflight must include compatible taints and all extended resources,
not just the destination's free disk space.

Both replicas reached Paris and finished catch-up in approximately 212 seconds
from source selection, including that scheduling correction. The live API charged
**13,958,643,712 bytes** for the two complete virtual devices. Post-migration reads
verified all 128 seeded objects through the Service and independently through each
pod (**384 reads, zero errors or checksum mismatches**).

However, the continuous no-retry probe recorded **27 failures in 4,217 requests**:
one PUT EOF at 17:41:13 UTC and 26 GET 404 responses from 17:41:39.904 through
17:41:42.696 UTC. The first coincided with the Service handoff away from the
source. The misses occurred when the Service selected the second replacement
before its first backfill pass completed at 17:41:42.869 UTC. The first thin pod
also underwent a normal template rollout after the fixture toleration changed.
The sampled timeline and runtime logs establish this overlap, but do not prove
which change is necessary or sufficient to eliminate it. Treat catch-up gating,
release of the resize hold, and draining existing HTTP connections as unresolved.
**This is not a passed uninterrupted end-to-end migration.** Later successful
checksum checks do not erase those failures. The earlier ten-minute pre-migration
hold soak had 6,657 requests and no failures; it was not migration traffic.

The fixture validates file-to-thin movement with real replication and key service.
It does not establish a live populated thick-to-thin conversion, single-copy
standby migration, host reboot recovery, or public ingress continuity. The PR
remains draft; both continuity and performance gates block production enrollment.

### Setup failures retained as evidence

The first preparation found the unloaded `dm_thin_pool` host module. With
explicit approval it was loaded temporarily through a short-lived pod with a
read-only module mount; no host boot configuration changed. The pool was created
from free VG extents, preserving the original `data` LV. The preparation script
now checks kernel target availability before mutation. Host reboot/bootstrap
qualification remains separate.

The initial 1 GiB legacy fixture rejected the first PUT because Kura needs at
least 1 GiB free for segment rotation. A later 4 GiB thick benchmark control
also returned two HTTP 503 responses during churn: this runtime enforces a
minimum 2.5 GiB segment ring despite a smaller requested CAS budget. Those failed
attempts were retained and excluded from the paired success results. The source
fixture was recreated at 4 GiB for its bounded migration corpus; benchmark
controls were recreated with equal 6.5 GiB virtual devices. The runtime minimum
must be reflected in future allocator grant floors and workspace qualification.

### Cleanup and remaining staging state

All owned runtime/benchmark fixtures, PVCs/PVs, encrypted source files and LUKS
mappings were removed. The server reconciler recreated the archived fixture once
after its KuraInstance was deleted; removing the fixture's database records before
the second deletion stopped reconciliation, and absence was verified afterward.
The synthetic account and wrapped keys were removed after the encrypted volumes
were gone; the scoped client token and port-forward were destroyed.

The empty pool and its owned metadata spare were removed only after checking
UUIDs and zero outstanding commitments. VG free space returned to exactly
**812,541,542,400 bytes**, and the original 128 GiB `data` LV retained UUID
`qf316g-aMzF-KlpS-5jsX-yqKl-25BI-OhgZ5U`. Pool configuration, thin-ready and thin
layout labels were removed; only Paris CSI was restarted to restore legacy
capacity advertisement. The source is uncordoned with no migration annotation.
The kernel module remains temporarily loaded; no persistent boot config was
written and a shared module was not forcibly unloaded.

All eight pre-existing ordinary Kura runtime pods retained their UIDs and were
Ready at the final check. The server and runner workload images were unchanged;
only the intended controller image differed from the start of this approved run.
An unrelated `shard-replica-test-1027` StatefulSet disappeared during the interval;
this task did not modify it. Staging retains the candidate CSI and corrected
controller images, with no test thin enrollment remaining. Production was untouched.

## Original mechanism experiment

## Reproduction and isolation

Use a disposable Ubuntu Linux VM with root and `ruby`, `lvm2`,
`thin-provisioning-tools`, `cryptsetup-bin`, `xfsprogs`, `util-linux` and `fio`.
The harness accepts no real block-device argument and refuses to run without
its explicit disposable-VM environment flag:

```sh
sudo env KURA_THIN_DISPOSABLE_VM=1 ruby stack_test.rb > /tmp/kura-thin-result.json
```

The completed run used Ubuntu 24.04, kernel `7.0.0-38-generic` on arm64,
LVM `2.03.16`, cryptsetup `2.7.0` and xfsprogs `6.6.0`. The VM had four CPUs and
4 GiB RAM. The fixture created a private 24 GiB sparse file, attached only that
file with direct loop I/O, and built a unique VG. Its thin pool had 8 GiB data,
128 MiB metadata and 64 KiB chunks. Three thin volumes and one thick comparison
volume each had a 6 GiB virtual device, LUKS2 AES-XTS, a bounded 64 MiB XFS log,
`reflink=0`, project quota ID 1 and explicit discard support. No hosted cluster,
production device or live key was used. Keys were random in-memory test bytes
passed on stdin and discarded during cleanup.

The scripts remove their mounts, encryption mappings, VG and loop device. They
verify asynchronous loop detachment before unlinking the backing file. A failed
cleanup preserves it for inspection instead of deleting an attached file.

## Mechanisms exercised

- Lowering a hard project quota below current use rejected new allocation.
- Unlinking a file while retaining its open descriptor did not release its
  allocation, even after successful trim. Closing the descriptor and trimming
  released physical mappings, observed both per volume and in the pool.
- A second encrypted filesystem allocated bytes after that reclamation. This
  demonstrates the shared pool path; it is not a saturation/admission test that
  proves B could not have grown before A shrank.
- Deletion without trim retained mapped allocation. Disabling dm-crypt discard
  made trim fail and preserved the charge; restoring it enabled reclamation.
- Unmount, crypt close, LV deactivation/reactivation and cold reopen preserved
  the LV UUID, random payload and hard quota. This is a mapping restart, not a
  reboot or a restarted CSI service.
- Fragmentation and ignored discard produced mapped allocation above the hard
  quota. Restoring working discard and trimming did not release thin chunks
  that still contained live filesystem blocks.

The fixture reads exact `dmsetup status` mapped sectors and pool data/metadata
block counters. It does not use filesystem free space, rounded LVM percentages
or fstrim's claimed byte count as proof of reclamation.

## Recorded results

The final run completed all **12 assertions** and verified loop detachment during
cleanup. All underlying XFS mounts, dm-crypt mappings and fixture LVs were gone
on the subsequent independent inventory check.

| Reclamation step | A mapped bytes | B mapped bytes | Pool used data bytes |
| --- | ---: | ---: | ---: |
| Empty formatted filesystems | 84,475,904 | 84,475,904 | 253,427,712 |
| A writes 768 MiB | 889,782,272 | 84,475,904 | 1,058,734,080 |
| A unlinks, descriptor stays open, trim succeeds | 889,782,272 | 84,475,904 | 1,058,734,080 |
| Descriptor closes, sync and trim complete | 84,475,904 | 84,475,904 | 253,427,712 |
| B writes 768 MiB | 84,475,904 | 889,782,272 | 1,058,734,080 |

The donor and pool both released exactly **805,306,368 bytes (768 MiB)**. The
recipient then added the same mapped amount. The empty formatted filesystem's
roughly 80.56 MiB allocation is measured fixture overhead, not a universal
production sizing allowance.

The fragmentation counterexample had a **268,435,456-byte hard quota (256 MiB)**
and **134,426,624 quota-accounted bytes (about 128.20 MiB)**. Its thin mapping
consumed **1,158,217,728 bytes (about 1.079 GiB)**. After restoring pool discard,
cold reopening and successful trim, it still mapped **1,158,676,480 bytes**.
The small increase is included, not subtracted as assumed reclamation. Pool
metadata usage was **13,897,728 / 134,217,728 bytes**. This was not a metadata
exhaustion test: neither metadata pressure containment nor a production-safe
reserve has been demonstrated.

The fixture writes 128 MiB chunks, then punches out 60 KiB of each 64 KiB range,
leaving live data in the thin chunks, eight times. This is deliberately adverse
fragmentation, not an assertion that Kura normally produces this layout. It
shows why a filesystem quota and successful trim cannot be the physical safety
proof, even with a relatively small quota and substantial free pool capacity.

## Performance interpretation


The paired workload uses the same encrypted XFS settings for thick and thin,
including project quotas and discard, to isolate the layout difference. That
controlled thick baseline differs from the current driver's mount/open options;
it is not a literal benchmark of the unchanged production driver. The sequence
is thick, thin, thin, thick, with two samples per layout. Each fio case uses a
512 MiB file, direct I/O, libaio QD32 and an eight-second timed run: 1 MiB
sequential reads/writes and 4 KiB random reads/writes. Each eviction sample writes,
fdatasyncs, deletes and trims sixteen 64 MiB files.

This is a VM on a local workstation with a loop-backed PV. Direct loop I/O avoids
the guest backing-file page cache, but does not remove hypervisor/host effects.
These short samples are diagnostic, not production NVMe throughput, cache HTTP
latency or stable percentage overhead. They do not establish regional capacity
or memory savings. The first exploratory benchmark used buffered loop I/O;
its numbers are excluded from the reported comparison below.

The two samples per layout in the final direct-loop-I/O run were:

| Workload | Thick | Thin |
| --- | ---: | ---: |
| Sequential write, 1 MiB QD32 | 4.98–6.06 GiB/s | 4.53–5.34 GiB/s |
| Sequential read, 1 MiB QD32 | 7.68–8.11 GiB/s | 5.97–6.74 GiB/s |
| Random write, 4 KiB QD32 | 142.9–169.7k IOPS | 123.1–123.2k IOPS |
| Random read, 4 KiB QD32 | 194.6–203.3k IOPS | 133.3–140.6k IOPS |
| Random-write p99 completion latency | 0.338–0.522 ms | 0.569–0.594 ms |
| Random-read p99 completion latency | 0.338–0.371 ms | 0.618–0.684 ms |
| Sixteen 64 MiB write/delete/trim cycles | 1.14–2.06 s | 2.49–2.76 s |

Thin random I/O, sequential reads and eviction/trim were slower in these samples;
sequential-write ranges overlapped. The large sequential rates reflect this
virtualized local setup, not hosted disk capability. Do not combine these figures
with the previous staging plain-XFS/thick-LUKS numbers to calculate cumulative
production overhead. Cache hit-rate benefits were not measured.

## Remaining blocking gates

Physical overcommit remains blocked. Quotas do not bound mapped allocation;
shared-mode pressure containment must be demonstrated independently under data
and metadata pressure, exhausted VG extension space, allocator/CSI outages and
process pauses. Passing the negative fragmentation test establishes an unsafe
assumption, not a working pressure guard.

The hosted thin-versus-thick comparison above found material I/O regressions.
Tune and remeasure, or explicitly review the performance tradeoff, before broad
enrollment. Recalculate #14825's shared-XFS regional admission and memory
projections for the qualified thin geometry and final runtime sizing policy.

Host bootstrap/reboot, genuine pool metadata exhaustion, and an actual populated
thick-to-thin migration across prepared hosts remain separate qualification gates.
The staging fixture uses legacy file-backed encrypted storage as its source.
Neither this run nor the older thick/OpenBao evidence qualifies every topology.
