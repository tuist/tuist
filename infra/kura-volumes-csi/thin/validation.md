# Thin stack qualification

Date: 2026-10-27. This is local mechanism evidence for [the proposed design](design.md),
not qualification of a thin CSI implementation or a staging deployment.

## Decision from the experiment

**Physical overcommit is not qualified. Use ceiling backing as the initial
implementation target.** XFS project quotas worked, but they did not bound
physical thin allocation. Fragmented files retained whole thin chunks even
after successful trim with discard enabled. This prevents treating quota
reductions or successful trim as transferable physical capacity.

The driver still creates thick LVs. The new API, sizing policy, persistent grant
ledger and pressure containment described in the design are not implemented by
this harness. It deliberately overcommits virtual sizes to explore the failure
case in a disposable VM. That is not the proposed conservative admission mode.

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


Before any implementation rollout, test the **final CSI code** on the actual
stack: concurrent CSI/grant/reclaim/delete operations, cancellation and crashes
at each durable boundary, restart reconciliation, stale snapshots, retained and
unknown volumes, pod-incarnation changes and replayed lease requests. This
harness does not exercise those interfaces.

Test data and metadata pressure independently with exhausted VG extension space,
allocator/CSI outages and process pauses. Verify write containment before either
reserve is consumed. The current negative case establishes why project quotas
and trim alone are inadequate; it does not establish a working pressure guard.
A new policy must not be declared safe merely because this harness's assertions
pass: one of its passing assertions demonstrates the unsafe assumption.

Benchmark representative Kura HTTP reads, writes, backfill and eviction churn
against thick storage, including CPU, memory and tails on representative hardware.
Recalculate #14825's shared-XFS regional admission and memory projections for the
qualified thin geometry and sizing policy. Rehearse the new thick-to-thin
migration on staging, preserving catch-up, endpoint handoff and deletion gates.
The older thick-LVM/OpenBao staging evidence does not satisfy these gates.
