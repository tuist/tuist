# ext4/fscrypt experiment evidence

This records disposable-VM qualification for #14152 on October 28, 2026.
It is not a staging deployment, production benchmark or fscrypt CSI validation.
The [integration gates](integration.md) remain separate from this experiment.

## Decision and application results

**The storage primitive and policy-reuse experiment pass; the performance gate
does not.** Do not replace the CSI implementation or clear #14152 for merge on
this evidence. The candidate can transfer a physically released grant without
changing #14825's fairness policy, but shows a repeatable write/CPU cost that
needs resolution or an explicit revised performance decision before a broad
implementation change.

Two complete runs passed with clean teardown:

- [40689323581](https://github.com/tuist/tuist/actions/runs/40689323581), revision
  `c322a1170e0`, Linux 6.17.0-1022-azure: 54 assertions and 24,320 HTTP requests.
- [40689687354](https://github.com/tuist/tuist/actions/runs/40689687354), revision
  `fb8059d3991`, Linux 7.0.0-1017-azure: 55 assertions and 24,320 HTTP requests,
  including the additional `file_setattr` quota-escape probe. Both unconfined
  mutation paths succeeded; both were denied under the test confinement.

There were **48,640 requests and zero failures**, including verified reads after
eviction churn and reads from a working set larger than the container memory
limit. Both use the same runtime digest:
`sha256:98a3e683675050fb2017015c0cd1372ed06e0463e2a2f976d2ce00830962425b`.
Each VM compares all layouts on that VM in forward/reverse order. The following
ranges cover four samples per layout across the two VMs, not one controlled
kernel comparison or statistical confidence interval.

| Actual cache workload | Shared XFS | Plain ext4 | ext4 + fscrypt | Thin LUKS/XFS |
| --- | ---: | ---: | ---: | ---: |
| Eviction churn, MiB/s | 241.98–243.05 | 189.08–191.91 | 163.82–167.49 | 166.92–168.18 |
| 16 KiB PUT p95, ms | 26.80–44.15 | 23.46–46.05 | 10.28–45.85 | 30.32–34.70 |
| 16 KiB GET p95, ms | 1.58–1.71 | 1.50–1.84 | 1.65–1.81 | 1.56–1.76 |
| 4 MiB PUT p95, ms | 197.77–202.80 | 192.97–206.74 | 220.16–284.79 | 295.87–342.90 |
| 4 MiB GET p95, ms | 108.78–136.38 | 93.76–106.48 | 92.42–110.65 | 107.92–123.93 |
| Post-churn GET p95, ms | 107.90–132.10 | 102.13–106.56 | 95.72–109.57 | 110.29–114.49 |
| 1 GiB working-set GET, MiB/s | 344.90–357.32 | 350.68–382.97 | 357.61–380.34 | 335.97–354.11 |
| Runtime CPU for ordinary phases, seconds | 19.06–20.90 | 35.45–36.05 | 40.54–41.23 | 19.51–21.06 |
| Runtime system CPU for ordinary phases, seconds | 11.04–12.02 | 27.23–27.83 | 32.67–32.88 | 11.37–12.23 |
| Cgroup memory peak before working-set phase, MiB | 383.35–424.14 | 387.56–425.55 | 383.80–427.28 | 381.20–423.27 |

In this fixture, fscrypt churn is approximately 32% below shared XFS and runtime
CPU is approximately doubled. Plain ext4 already loses about 21% of churn
throughput and consumes much more system CPU than XFS; encryption adds another
roughly 13% throughput loss relative to plain ext4. These controls identify a
filesystem-dependent component, but do not identify its kernel function or
prove that a particular mount option will fix it. Small-PUT p95 is noisy and
does not establish an improvement. Read results are encouraging; they do not
cancel the sustained write cost.

All layouts experienced CPU throttling. Recorded ordinary-phase memory events
showed no OOM/max-limit events. CPU and memory observations cover the runtime
cgroup before the extra working-set phase, not total host/CSI/OpenBao resources
or a fleet density projection. This uses a pinned candidate runtime on every
layout, not today's deployed runtime measured against a new release. The
shared-XFS control isolates storage layout within the VM; it is not production
or hosted staging evidence.

Both adapter runs kept A's 5,368,717,312 allocated bytes charged while its file
was held open. After closing it and recreating allocator process state, A's
quota fell from 6 to 4 GiB and B's rose from 4 to 6 GiB. B then held
5,368,721,408 allocated bytes, exceeding its old allowance. Removing A from the
active inventory did not release its retained quota commitment. The exact
policy implementation was unchanged. This clears the bounded policy-reuse
proof, not production admission or CSI integration.

## Bounded CPU diagnosis

The separate [profile run](https://github.com/tuist/tuist/actions/runs/40693941162)
at `805bc48c209` passed all four application layouts, 12,160 requests with zero
failures, the primitive/policy checks and complete cleanup. Linux was
7.0.0-1017-azure; the installed perf executable reported 6.8.12. It sampled the
actual Kura process at 99 Hz with software CPU-clock events and recorded symbol
reports only. Raw profiles and fixture credentials were removed. Its timings
are diagnostic and are excluded from the unprofiled comparison above.

Runtime system CPU was again about 12 seconds for XFS, 28 seconds for plain
ext4 and 34 seconds for fscrypt during the ordinary phases. The backing-device
cgroup I/O counters reported approximately 13.4 GB written for every layout;
do not sum the duplicated loop/device-mapper/backing-device rows. This does not
support an explanation based solely on twice as many written bytes.

Sampled ext4 stacks included page allocation/initialization, locking,
`dquot_add_space`, `ext4_da_map_blocks`, extent-status operations and writeback.
The encrypted path additionally sampled `aes_xts_encrypt_vaes_avx2`. This is
evidence of filesystem work as well as encryption work, not proof that one
function causes the whole regression or that a particular mount option fixes
it. The profiles contain only 369–1,026 samples per layout; percentages must
not be treated as a complete accounting of cgroup CPU, all worker threads or
host crypto/writeback work. No durability or runtime behavior was changed.

## Physical reclamation and confinement

The first [primitive run](https://github.com/tuist/tuist/actions/runs/40685359928)
passed 33 checks and verified complete fixture cleanup. It used Linux
6.17.0-1022-azure and fscryptctl v1.2.0, pinned to
`361a040c0f50c2440d51347b5eb48482ae1a41b7`. Raw output is the run's
`fscrypt-experiment` artifact, `kura-fscrypt-stack.json`.

| Observation | Result |
| --- | ---: |
| A's charge before and after unlinking an open 512 MiB file | 536,879,104 bytes |
| Filesystem available bytes before and after unlink | 2,137,763,840 bytes |
| A's charge after closing the file | 4,096 bytes |
| Filesystem available bytes after close | 2,674,638,848 bytes |
| B's allocation after receiving and consuming the increased quota | 1,207,967,744 bytes |

The filesystem independently confirmed 536,875,008 released bytes. No discard
command was required to reuse those blocks. A lowered hard quota refused new
writes while the open-deleted allocation remained charged. Concurrent writers,
inode quota pressure, mmap/pread equality, independent keys, wrong-key rejection
and cold unmount/remount with key reinstall also passed. The test did not reboot
or crash the VM, and it did not exercise CSI lifecycle concurrency.

The subsequent [confinement run](https://github.com/tuist/tuist/actions/runs/40686846793)
confirmed that an ordinary file owner could move its directory to project 0
without capabilities. The additional seccomp filter rejected project changes
and clearing project inheritance. This run passed its 35 primitive assertions,
but failed application startup and cleanup qualification; it is not a complete
passing run. Later test revisions additionally reject and directly probe Linux
6.17's `file_setattr` syscall. Never treat UID/capability dropping alone as
quota confinement.

## Methods and interpretation

The combined harness uses private loop-backed files in an ephemeral GitHub
Ubuntu VM. The shared ext4 filesystem is 16 GiB; A and B each have an 8 GiB
logical ceiling, exceeding filesystem usable capacity in aggregate. The
primitive test keeps only 1.5 GiB of granted capacity. The policy adapter has
its own 10 GiB admission cap and 2 GiB physical reserve. Neither is a fleet
capacity or optimal-reserve estimate.

The policy adapter compiles against unchanged #14825 revision
`34956ca681a3dc0dc257ee5b4d0d65814bd5f23d`. It keeps A's held allocation charged,
then recreates allocator state and attempts to transfer quotas from 6/4 GiB to
4/6 GiB after closure. Its two-project inventory is complete by construction;
production discovery, durable admission and CSI serialization are not tested.

The application comparison pins `ghcr.io/tuist/kura:sha-04e128167d80` on every
layout, one CPU, 768 MiB memory without swap, a 4 GiB cache budget and 2 GiB
workspace, under a 6 GiB project quota. Order is shared XFS, plain ext4, fscrypt,
thin LUKS/XFS, then reverse. It uses real authenticated HTTP requests, verifies
GET checksums, adds no retries and creates a new cache directory for every run.
Each run has 2,528 ordinary requests including 6 GiB eviction churn, followed
by a 512-request, 1 GiB working-set workload larger than the memory limit.

The separate fio diagnostic compares all four layouts plus thick LUKS/XFS.
It uses buffered psync QD1, 512 MiB files and eight-second phases, followed by
sixteen 64 MiB write/delete cycles. Thin includes TRIM; shared filesystems reuse
blocks without it. Buffered overwrite numbers include page-cache effects and
must not be represented as durable device throughput. Neither fio nor the
HTTP workload establishes equivalence on hosted NVMe or under production load.

## Failed attempts retained in the evidence

- The local Tart VM failed to boot; it executed no filesystem qualification.
  Its task-owned clone was removed.
- [40684933972](https://github.com/tuist/tuist/actions/runs/40684933972) could not
  mount the quota-enabled ext4 filesystem until the VM's quota format module
  was installed/loaded. The workflow now prepares that prerequisite explicitly.
- [40686196399](https://github.com/tuist/tuist/actions/runs/40686196399) and
  [40686846793](https://github.com/tuist/tuist/actions/runs/40686846793) stopped at
  application startup because the fixture omitted the runtime's required
  deployment-environment setting. No application measurements from those runs
  qualify. Cleanup verification also failed; backing files were retained inside
  the disposable VM. The harness now waits for loop autoclear before deciding
  cleanup is complete.
- [40688259559](https://github.com/tuist/tuist/actions/runs/40688259559) stopped
  before filesystem setup: its sparse sharing-policy checkout inherited a Go
  workspace referencing absent modules. The adapter build now sets `GOWORK=off`.
- [40692671442](https://github.com/tuist/tuist/actions/runs/40692671442) stopped
  before profiling because executable discovery skipped the packaged perf
  symlink. [40693145649](https://github.com/tuist/tuist/actions/runs/40693145649)
  completed the first layout's requests but attached to the idle container init
  and rejected perf's intentional interrupt status. It cleaned up successfully,
  but provides no useful profile. The final run locates the existing Kura
  process, accepts only successful/intentional-interrupt termination and rejects
  a report without samples. Neither failed diagnostic replaces the complete
  unprofiled benchmark runs.

No hosted staging or production storage was changed by these experiments.
Earlier shared-XFS capacity/memory gains and thin-layout staging results remain
separate evidence. A passing primitive test cannot clear final-layout storage
safety, permanent OpenBao custody/recovery or staged-migration release gates.
