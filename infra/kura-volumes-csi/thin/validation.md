# Thin stack qualification

## Review remediation — 2026-10-29

The review of `31233a1b5a4` correctly identified merge-time infrastructure
changes despite tenant enrollment being off. The remediation below is not
production approval; the draft and account-scoped migration gates remain.

| Review finding | Current disposition |
| --- | --- |
| 1: replacement-node disk loss | Bootstrap now requires `tuist.dev/kura-storage-layout: lvm-v1` on the infrastructure Machine/rack host. For rented pools CAPI propagates `MachineDeployment.spec.template.metadata.annotations`. Without it, cache taints retain the legacy full shared-XFS layout. `rack-seed --kura-lvm` is explicitly opt-in. Existing joined nodes are still never converted. |
| 2: controller rollback selects missing CSI image | Removed controller-tag inference. Routine deploys preserve the installed CSI image; explicit upgrades use a manifest-verified digest. API failures abort resolution rather than disable CSI. |
| 3: new required vault item | Production/canary root sync and CSI installation now default off. Staging retains the previously exercised legacy root dependency. No live secret was read and no new production vault provisioning is claimed. |
| 4: CSI rolls on every server deploy | Removed CSI from per-server build matrices and image selection. Publish separately and supply a qualified digest explicitly. Since 2026-10-31 the rented plugin is in the unwaited rack-nodes release, adopted in place with an identical pod template, so a broken Kura node no longer rolls a server deploy back. A readiness probe remains open. |
| 5: regional hold / dead destination | Partly fixed (2026-10-31): an instance waiting for source-node selection no longer skips the rest of its reconcile. Its template keeps the existing claim class, size and disk request while images, configuration, services and status follow the spec, and a partly migrated instance keeps its resize hold. Controller tests only; not rehearsed on staging. An armed destination whose pod keeps its UID but restarts its process is now rebound: the source stays armed, re-proves its retained records and feed on the new process, and reports ready only afterwards (Kura and controller tests only, not rehearsed on staging). A single-replica instance now migrates behind a temporary standby ordinal that takes the endpoint while ordinal 0 is rebuilt and hands it back before it is released (2026-11-01, controller tests on both encrypted and thin classes; not rehearsed on staging). Since 2026-11-01 the controller also rebinds a destination pod replaced under the same name, prepares a restarted source again under its new incarnation instead of failing, and aborts the bridge of an undemoted source whose node was unselected (controller tests; the abort endpoint is in the runtime change below). Bridge metrics (`kura_migration_*`, unit-tested) drive two proposed rules: armed but not ready for 15 minutes, and armed with no destination proof for 2 minutes; neither is provisioned in Grafana yet. |
| 6: public key-service transport | Fixed in `9eb1f45` (2026-10-31): per-request pod-bound tokens whose only audience names the request key, responses keyed by a pinned static server key with volume id and key version as AAD, and a fail-closed TokenRequest admission policy. See `../security/key-management.md`. Not yet provisioned or rehearsed on staging. |
| 7: foreign pending-PVC prebinding | Fixed in admission (2026-11-01): the node plugin can no longer select a node on a claim, and a new parameterised policy lets it create a PV only for a Kura claim the scheduler selected for its own node. The local kind 1.34 harness passes all 25 cases (`security/admission-results.json`); not yet installed on a hosted cluster. |
| 8: spoofable pre-authentication rate key | Uses the socket peer address, ignoring forwarding headers. Tests prove changing either forwarding header cannot create a fresh budget or trigger TokenReview after denial. |
| 9: registry permissions / mutable upgrades | PR tests/builds have no package-write permission and checkout credentials are not persisted. Only the manual publishing job can push. Explicit upgrades use digests; existing legacy tag pins are preserved until an intentional upgrade. PR builds target amd64 without QEMU. |
| 10: allocator peer identity | Added Linux `SO_PEERCRED` UID 0 checks, in addition to mode 0600. Non-Linux serving fails authorization. Linux non-root rejection and the real root socket request pass in the disposable run below. |
| 11: recursive quota setup | Stage/restage sets project ID and inheritance only on the filesystem root using `project -s -d 0`. Fresh driver-created filesystems are empty and descendants inherit. Inherited enforcement and recovery pass in the real-stack rerun below. |
| 12: long node-wide lock | Fixed 2026-10-31: node stage/unstage/publish/unpublish take only the per-volume lock; create, delete, grant, reclaim and observation keep pool-then-volume. Tests hold a stage inside a stalled key fetch and prove pool locking, observation and controller calls proceed while that volume stays serialized, and that a key outage on first format leaves no key version or header and the retry formats. Not yet exercised in the Linux CSI qualification. |
| 13: failed observation advertises zero | Now returns the removal sentinel, producing a null capacity patch. The scheduler still cannot place new requests; CSI remains the final allocation gate. `kubelet_restart_test.rb` on a disposable kind 1.34 node (2026-10-31): after withdrawal and a kubelet restart the resident pod kept running with zero restarts; after publishing zero, re-admission rejected it (`OutOftuist.dev/kura-disk`) and stopped its container. Not repeated on hosted kubelets. |
| 14: unbounded/expensive observation | Thin observations include lock acquisition in a 30-second deadline; advertisement has a 45-second deadline. LVM queries, dmsetup and quota commands have 15-second deadlines. Observations skip pool activation when it is already active, and the advertiser reads the node and patches only a changed value (canonical quantities compared as bytes; unreadable or unparseable values still patch). Per-volume command fan-out and LVM device filtering remain open. Deadlines cannot guarantee recovery of a process stuck in uninterruptible kernel I/O. |
| 15–16: armed-write serialization and cache-size-dependent preparation | Armed acknowledgments group-commit since 2026-10-31: sixteen concurrent completions made 17 destination round trips before and at most 4 after (unit test); not yet re-measured on staging. Since 2026-11-01 each preparation attempt keeps its own 20-minute deadline but the retained walk resumes across attempts for the same source and destination processes: the source saves the index position after each verified page and keeps its feed pin, a retry continues only if the failed attempt advanced, and feed loss, reset, rebind or another destination restart from the top (unit tests, including writes made during the interruption; not rehearsed on staging, and walk throughput at hundreds of GiB is unmeasured). An internal abort now clears a migration in any state for a source that was never demoted, releasing waiting writes as ordinary acknowledgments (unit tests only). The concurrent prepare/reset panic, which poisoned the bridge lock, is fixed. Normal-serving benchmarks do not qualify this path. |

The nullable replica default is corrected. The unrelated WebSocket adapter
upgrade is removed and version 0.6.0 is pinned so dependency resolution does not
silently restore it. Migration reset/panic recovery and separation of experimental fixture code remain open. Reserved-disk
accounting also changes for legacy regions because it includes init containers,
sidecars and pod overhead; it is not an encrypted-capacity gain.

Local validation: full CAPI `go test ./...` and `go build ./...`; CSI
`go test ./...` and `go vet ./...`; 85 server endpoint/region tests with the
restored adapter; `mix deps.get --check-locked`; independent-image resolver
failure tests and ShellCheck; Helm lint and all three managed renders. Production
and canary render neither the CSI driver nor the root-key remote reference;
staging renders both. Actionlint passes the CSI/reusable-deployment workflows
with the repository's custom runner labels excluded. The production wrapper
still has pre-existing action-output/ShellCheck diagnostics outside this change.
No new staging or production deployment is represented by these local checks.

The first [disposable Linux run](https://github.com/tuist/tuist/actions/runs/40890461619)
at `9cab9acf1de` passed Linux unit tests and the complete 512 KiB stack. The
64 KiB driver test stopped at its immediate post-TRIM assertion: actual mapped
release was 703,201,280 bytes, below its 700 MiB threshold. CSI reported that
smaller physical release and zero released commitment; it did not credit the
logical trim size. The follow-up test retains the same threshold and original
physical baseline while retrying observation/TRIM for at most 15 seconds. Both
per-volume and pool decreases must satisfy it before B consumes reclaimed space.
The first run also started an unrelated fscrypt experiment; it was cancelled
after both thin jobs completed, and `qualification_only` now excludes it.

The [clean rerun](https://github.com/tuist/tuist/actions/runs/40891950047) at
`88c8d2c1bbf` passed Linux unit tests and both real CSI geometries. A physically
released 805,371,904 bytes at 64 KiB chunks and 805,830,656 bytes at 512 KiB; B
then increased pool usage by exactly those amounts. Both mechanism runs passed
all 12 assertions, including open-deleted files, failed/delayed discard, reopen,
quota enforcement and the quota-versus-mapped-allocation counterexample, and
confirmed loop detachment. Root-only quota setup, durable quota recovery and the
root allocator request passed through the actual driver. Image publication and
unrelated experiments were skipped. This is disposable VM qualification, not
a fresh hosted staging rehearsal or a production performance measurement.

### Infrastructure rollout prerequisites

1. Keep production/canary CSI installation, legacy root sync and tenant/regional
   enrollment off on merge. Staging's existing support remains enabled.
2. Qualify key custody/private transport and publish a separately tested CSI
   image. Enable installation in the selected environment and provide
   `kura_volumes_csi_image_digest` to the deployment workflow. Missing manifests
   fail before Helm; normal server/controller rollbacks preserve that image.
3. Prepare selected replacement hosts with the explicit layout annotation;
   evacuate existing hosts before reinstalling them. The annotation is not an
   online conversion command. Prepare thin pools only from unused extents.
4. Do not enable the current region-wide enrollment as a substitute for the
   required Tuist-first account/region canary. Implement and rehearse that path,
   armed-handoff recovery, standby, endpoint continuity and safe deletion first.
5. Pausing enrollment must retain CSI, its installed image, storage records,
   mappings, key access and admission safeguards while any encrypted PV exists.

## Active encryption objective and unqualified thin candidate

Encryption at rest with per-tenant keys and OpenBao remains the objective of
#14152, including rack nodes. Disk sharing in #14825 is a separate workstream
whose future reclamation/accounting needs constrain the encryption layout.
The earlier decision below to defer encryption was a scope error and is
superseded. Shared XFS without tenant encryption does not satisfy this work.

The tested thin implementation is still not a rollout candidate. Preserve its
performance and physical-allocation failures while selecting a layout that
supports safe future redistribution without routine volume replacement or
permanent full-ceiling backing. Reopening the encryption draft does not waive
those gates or establish permanent OpenBao custody. The shared-XFS benchmarks
and no-node-reboot rollout in #14825 do not qualify an encrypted implementation.

## Fresh qualification and sharing compatibility — 2026-10-28

**Safety regression tests passed; compatibility and performance release gates
remain open.** The [cross-PR review](sharing-compatibility.md) checks encryption
head `33ad1b6c2cf` against sharing head `34956ca681a3`. The policy and runtime
budget mechanism can be retained, but the latter's shared-XFS accounting cannot
be applied to an encrypted thin pool. Full-ceiling backing remains necessary
for the implemented safety model. It is not established that #14825 can follow
this layout with only small changes.

### New execution and physical evidence

[Qualification run 40673030463](https://github.com/tuist/tuist/actions/runs/40673030463)
reran the actual CSI driver and mechanism harness on separate disposable Linux
VMs for both 64 and 512 KiB pools. Both driver tests and all 12 mechanism
assertions per geometry passed. The workflow's Go tests and vet passed; local
`go test -race ./...` and `go vet ./...` also passed. The unchanged #14825
`internal/diskallocator` policy tests passed locally; its Linux-only agent was
not exercised on macOS. This is not a combined allocator/CSI integration pass.

The real CSI run verified open-deleted charging, failed discard, quota
enforcement, durable intent recovery, process restart, stale pod rejection,
concurrent creates, reserve refusal, retained claims and deletion safeguards.
Reserve-refusal injection does not qualify recovery after actual metadata
exhaustion. Physical A-to-B recycling measured:

| Pool chunk | Observed A release | B pool growth | Admission commitment released by reclaim |
| --- | ---: | ---: | ---: |
| 64 KiB | 805,371,904 bytes | 805,371,904 bytes | 0 |
| 512 KiB | 805,830,656 bytes | 805,830,656 bytes | 0 |

Both runs reproduced the negative allocation test: a **256 MiB project quota**
permitted **1,073,741,824 additional mapped bytes** during fragmented writes
with ignored discard. After restoring working trim, the tested volume still
mapped **1,158,676,480 bytes (64 KiB)** or **1,162,346,496 bytes (512 KiB)**.
Live blocks prevented whole-chunk reclamation. This is concrete evidence against
replacing complete backing with quota-based admission; a successful safety test
does not mean physical overcommit passed.

### New VM benchmark results

Each VM ran thick/thin/thin/thick with the same encryption settings as the
existing harness: 512 MiB fio files, direct/libaio, QD32, eight-second phases,
1 MiB sequential and 4 KiB random I/O. The following is the **512 KiB** candidate
on kernel `6.17.0-1022-azure`, LVM 2.03.16, cryptsetup 2.7.0 and XFS tools 6.6.0.
Backing was a private 24 GiB sparse file on the VM disk, not hosted NVMe.

| Measurement | Encrypted thick | Encrypted thin, 512 KiB |
| --- | ---: | ---: |
| Sequential read | 407.38–407.53 MiB/s | 407.19–407.38 MiB/s |
| Sequential write | 407.27–408.35 MiB/s | 343.63–344.92 MiB/s |
| Random read | 19.63–19.66k IOPS | 19.58–19.67k IOPS |
| Random write | 19.58–19.64k IOPS | 19.57–19.61k IOPS |
| 16 × 64 MiB write/delete/TRIM | 2.33–2.36 s | 4.95–4.96 s |

All fio jobs completed without I/O errors. Sequential writes were about 15.6%
lower and the small churn sequence took about 2.12 times as long on thin in
this VM. Other phases overlap. Similar read IOPS here do not overturn the
hosted NVMe random-read regression: VM storage can hide that difference.
The 64 KiB VM produced overlapping read/write IOPS and sequential rates near
406–409 MiB/s; churn took 2.33–2.38 s thick and 2.38–2.39 s thin. It ran a
different kernel (`7.0.0-1017-azure`) on a separate VM, so comparing those two
jobs cannot attribute differences to chunk size. No geometry change is justified
by this run. Raw JSON and driver logs are the workflow's `thin-stack-64` and
`thin-stack-512` artifacts.

### Relationship to existing staging benchmarks

This run did **not** recreate the hosted staging benchmark or deploy OpenBao.
A read-only staging inventory found the original workloads and CSI pods running.
No staging or production resources were changed. The prior encrypted staging
evidence below remains relevant: the current Kura source matches tested runtime
`04e128167d80`; CSI driver/Dockerfile source matches packaged `e13640b0fc04`;
controller executable source matches `6e17641d4fac`. Subsequent changes in
those directories are documentation and the rollout-probe verification tool.

Keep the baseline distinctions explicit. Main/shared-XFS versus encrypted thin
measured 16 KiB PUT p95 **28.99–29.84 → 34.87–35.82 ms** and eviction churn
**159.36–164.16 → 156.55–157.45 MiB/s**. The separate encrypted-thick versus
encrypted-thin NVMe test measured **25.6% lower QD32 random-read IOPS**.
Neither result is a fresh measurement of today's production deployment. The
plaintext sharing benchmarks in #14825 cannot replace either comparison.

The release decision remains **hold**: establish a physically bounded,
transferable grant model before committing to this layout, then benchmark and
rehearse that final encrypted implementation with OpenBao on staging. Do not
move this unresolved storage problem into #14825 or relax pool containment to
make its admission policy appear compatible.

## Superseded scope decision — 2026-10-28

The thin-LVM migration in #14152 is parked. Continue disk sharing in #14825
on shared XFS; it no longer depends on this CSI implementation. Preserve this
branch and the evidence below as an experiment, not as a rollout candidate.

The final measurements did not meet the performance gate: tuned thin random
reads at QD32 remained 25.6% below encrypted thick LVM. In the separate
production-style staging comparison, small PUT p95 was 28.99–29.84 ms on
main/shared XFS versus 34.87–35.82 ms on candidate/encrypted thin. These compare
different baselines and must not be combined into one attributed overhead.
The qualified mode also requires complete virtual-ceiling backing, so it does
not deliver the proposed disk-sharing admission gains.

This decision defers per-tenant encryption at rest. Shared XFS alone does not
provide it; host-wide encryption would not provide equivalent tenant key
isolation. Application-level encryption remains an unqualified alternative.
Any future proposal must qualify key custody/recovery, authenticated reads,
range access and serving performance, rotation, disk overhead and eviction
churn before becoming a migration prerequisite.

The prior rehearsal fixtures and thin pool were removed. A read-only check on
2026-10-28 found four existing encrypted CSI PVs still Bound on staging. Retain
their driver, key service and state until a separately verified migration;
parking this PR does not authorize deleting their storage dependencies.
Production is unchanged. Shared-XFS sharing still needs its own staging and
rollout qualification; the following thin tests cannot qualify it.

All release-status statements below describe the experiment at the time of
measurement. The active encryption objective above governs subsequent work;
the measurements and safety failures remain valid evidence.

## Destination-bound handoff qualification — 2026-10-27

**The live-write handoff defect is corrected and its repeated staged migration
passed. Performance remains a release blocker; keep this PR draft and production
thin enrollment disabled.** The following evidence supersedes the current-state
conclusion of the earlier failed rehearsal below. Production was not changed.
Physical overcommit remains disabled: only `ceiling-backed-v1` is implemented.

### Handoff fix and actual staged migration

The previous two fresh-write misses came from acknowledging a donor write before
asynchronous replication made it available at the selected destination. The
controller now persists the source process and destination pod/process identities
before any endpoint move. An authenticated preparation verifies retained content
on that exact peer and covers concurrent writes through the source feed. Once
armed, successful HTTP/gRPC mutation completion requires destination content
verification. A cursor alone is never a receipt. Existing endpoint observation,
connection retirement, catch-up, deletion and queued-template safeguards remain.
See [the protocol and pause/retry procedure](../../kura-controller/thin-migration.md).

Runtime `60996da4c4c7` and controller `6e17641d4fac` completed a new actual
Canada-file-backed → Paris-thin migration. Both source replicas held a verified
1 GiB large-object corpus and 128 small objects. Desired thin layout did not
replace either source while the node remained unselected. After selecting one
cordoned source, both claims migrated in **520 seconds**. An annotation queued
during catch-up restarted the first thin replica without replacing its PVC.
The hold released only after the replacement replicas completed catch-up.

The continuous probe completed **21,276 requests, zero failures and 7,092
successful writes**. It has no application retry loop; Go's transport may retry
an idempotent request after a stale connection. Every successful write was
journaled by key, length and SHA-256, then independently read through the Service
and both final replicas: **21,276 successful journal verification reads**.
The original corpus passed another **1,152 verification reads**, for **22,428
final reads** in total. The earlier failed run remains below; eventual checks
are not being substituted for the zero-error live traffic result.

The 16 GiB pool retained its 1 GiB data and 64 MiB metadata reserves. Final
commitments were **13,958,643,712 bytes** for two 6.5 GiB virtual volumes. At the
post-migration snapshot, physical data usage was **4,357,357,568 bytes**, metadata
usage **17,039,360 bytes**, and unattributed allocation zero. Both volume UUIDs
remained stable across the queued restart and CSI image rollout. All eight
pre-existing Kura runtime pods retained their UIDs and readiness.

The first large-corpus seed exhausted the probe client's 512 MiB limit. It was
rerun with a 1 GiB client limit; runtime limits remained one CPU/768 MiB. This
was fixture correction, not evidence of lower runtime memory requirements.
The migration fixture reduced its claim to 4 GiB but retained the rendered
5,728,412,631-byte CAS budget. Its approximately 2 GiB retained workload stayed
inside the grant; this is not a full-capacity budget-alignment test. The final
paired performance fixtures explicitly set both cache budgets to 4 GiB.
The live key provider was `tuist_root`; this rehearsal does not requalify OpenBao
custody. Prior OpenBao evidence remains a separate deployment/operational gate.

### Packaged metadata checking

The staging activation revealed that the CSI image omitted
`thin-provisioning-tools`: LVM warned that `thin_check` was unavailable and could
skip its activation check. The Docker image now includes the package and checks
the executable at build time. Pool preparation verifies the prerequisite before
any VG mutation. The corrected image `e13640b0fc04` reports `thin_check` 0.9.0
and re-staged the live fixture without probe failures. The same package was
installed in the preceding test container before the new image finished building;
the later restart verifies the packaged dependency. Offline metadata checks are
never run against a live metadata device.

[CSI image qualification](https://github.com/tuist/tuist/actions/runs/40581939556)
passed Go tests/vet and both the actual-driver and mechanism tests at 64 and
512 KiB before publishing. These include physical A-to-B reclaim, deleted-open
files, failed/ignored discard, restart, stale-identity rejection, concurrent
operations and reserve refusal. They do not qualify recovery after actual
metadata exhaustion. [Controller build](https://github.com/tuist/tuist/actions/runs/40577662478)
and full Go tests/vet passed. The
[handoff runtime qualification](https://github.com/tuist/tuist/actions/runs/40579216449)
passed formatting, Clippy and 1,259 Rust tests, with 49 ignored and the binary
test passing separately.

### Pause, retry and HTTP/2 qualification

Runtime `04e128167d80` separates the bounded preparation deadline from an
established bridge. After readiness, a weak-reference background loop refreshes
the feed consumer and verifies the destination until the donor drains. An exact-
identity reset endpoint clears only a completed failed, unarmed preparation;
it cannot clear a running preparation or a ready bridge. Reset serializes with
acknowledgments and releases only that attempt's feed pin.

[Linux qualification](https://github.com/tuist/tuist/actions/runs/40585572593)
passed formatting, Clippy and **1,261 Rust tests, 49 ignored**, plus the binary
test. The same image then passed live staging checks:

- A deliberately wrong destination incarnation failed preparation. Wrong source
  or destination reset identities returned 409; the exact failed attempt reset
  successfully without restarting the source. Reset of a ready bridge returned
  409. The correct preparation became ready in 17 seconds.
- The armed bridge remained healthy for over 21 minutes with both process
  identities unchanged, exceeding the old 20-minute deadline. The probe completed
  **22,587 requests, zero failures and 7,529 successful writes** in 1,313 seconds.
  All writes were independently verified through the Service and both replicas
  using HTTP/2. This deliberately held one fixture's progress; the shared
  controller was never paused.
- A separate h2c-only run completed **16,347 requests, zero failures and 5,449
  writes**. Every response was required to use HTTP/2 and every write was verified
  through all three endpoints. The original four-connection cohort reached zero
  after **275 seconds**, within the existing five-minute maximum connection age.
  The harness's initial 240-second observation deadline was too short; an extended
  observer watched the same uninterrupted run complete. This was not a runtime
  restart or a replay of failed traffic. Since 2026-11-01, retirement also sends
  HTTP/2 connections in the retired cohort a GOAWAY on every public listener,
  including the gateway gRPC port, so the cohort empties once in-flight streams
  finish instead of at the connection age. A unit test with a real h2c client
  shows an in-flight request completing and the cohort reaching zero; this is
  not rehearsed on staging and the 275-second figure has not been re-measured.

Together with the migration, these three runs produced **60,210 live requests,
zero failures and 20,070 successful writes**, followed by **60,210 independent
journal reads**, all successful. The extra 1,152 original-corpus reads also passed.
The initial sequential HTTP/1 journal reader on a retiring source incurred about
78 ms per request because every response closed its connection. After complete
HTTP/2 verification, that redundant reader was stopped by its exact process
identity. It is not counted as a failed or completed verification run.

A separate eight-concurrent-request, 1 GiB large-object bridge test verified
all 256 writes through the source and destination. While the Service was
intentionally held on the bridged, retiring source, 4 MiB PUT batches delivered
only **16.25–21.12 MiB/s**, with **2.10–3.12 seconds p95**. GET throughput was
273.98 MiB/s with 158.54 ms p95. Replication, destination verification and retiring
HTTP/1 connections were all active. This is a substantial temporary migration
cost, not normal thin serving performance; the paired unbridged tests below
must be read separately. A long operator pause can prolong this cost.

### Final unbridged application comparison

Runtime `04e128167d80` ran on equal 6.5 GiB thick/thin devices, one CPU/768 MiB
limits, 100 mCPU/256 MiB requests, an explicitly matched 4 GiB useful cache
budget and 2 GiB workspace. Replication/discovery and migration bridges were
inactive on these standalone fixtures. The authenticated on-node client had a
1 GiB limit. Order was thick/thin/thin/thick, with 20 seconds settling after each
run. Each run performed 2,528 checksum-checked requests, including 6 GiB of
writes through segment eviction. **All 10,112 requests passed.**

| Application measurement | Thick | Thin |
| --- | ---: | ---: |
| 6 GiB eviction churn | 156.21–159.48 MiB/s | 157.76–160.64 MiB/s |
| 16 KiB PUT p95 | 27.38–36.95 ms | 36.31–38.89 ms |
| 16 KiB GET p95 | 2.95–2.96 ms | 3.61–4.99 ms |
| 4 MiB PUT p95 | 224.05–230.21 ms | 242.36–251.72 ms |
| 4 MiB GET p95 | 92.92–95.71 ms | 94.42–99.18 ms |
| Post-churn 4 MiB GET p95 | 93.85–98.59 ms | 97.02–115.27 ms |
| Runtime CPU per run | 42.70–43.39 s | 42.60–42.82 s |
| Sampled peak anonymous memory | 45.85–47.82 MiB | 44.64–45.49 MiB |

All runs reported zero memory-pressure state and no OOM. CPU throttling was
present on both one-CPU fixtures; these are workload comparisons under the same
limits, not storage-only latency measurements. Each served 543,424,512 measured
artifact bytes. Retained cache directories were 3.24–3.78 GB as segment eviction
rotated; request bytes and cache budget matched, not the incidental ring phase.
CPU/memory figures describe the runtime cgroup, not total host, CSI or OpenBao
cost. They do not establish a tenant-density or regional-memory projection.
Short ranges and page-cache hits do not prove statistical equivalence. These
results replace the earlier runtime `532db7a28be5` application results as the
current candidate comparison.

A separate 1 GiB shuffled-read working set exceeded the 768 MiB container limit.
All **2,048 requests** passed. Thick GET throughput was **424.48–455.37 MiB/s**
and thin **484.91–493.04 MiB/s**; p95 was **106.74–114.39 ms** versus
**104.70–106.85 ms**. No global cache dropping was used, and not every read is
claimed cold. This bulk-workload result does not overturn the small direct-read
regression or establish a regional capacity gain.

The prepared-node guard correctly rejected creating a new thick claim after
thin opt-in. For the diagnostic control only, a fresh, bounded 6.5 GiB LV was
preallocated from verified free VG space under its exact CSI volume lock, with
its exclusive unformatted marker. Normal CSI retry then recognized the existing
volume, obtained its real key and formatted/staged it. This preserves the new-
volume guard and exercises the supported existing-thick path; it does not
qualify new thick admission on thin-enrolled nodes.

### Runtime-only control on the same thin PVC

The main/candidate/candidate/main control recreated the Pod on the same thin
PVC before each run. The baseline image `172ffef18648` has exactly the same Kura
source tree as main `3552a2c78f4`; the candidate was `04e128167d80`. No bridge was
armed. Equal resources, useful cache budget and workload were retained. All
**10,112 requests passed**.

| Measurement | Main runtime | Candidate runtime |
| --- | ---: | ---: |
| Runtime CPU per run | 44.06–44.51 s | 43.37–44.06 s |
| Sampled peak anonymous memory | 44.17–49.16 MiB | 45.76–47.36 MiB |
| Eviction churn | 152.99–154.64 MiB/s | 154.29–156.33 MiB/s |
| 16 KiB PUT p95 | 35.97–36.38 ms | 41.09–41.46 ms |
| 16 KiB GET p95 | 2.80–3.06 ms | 2.53–2.63 ms |
| 4 MiB PUT p95 | 262.69–282.00 ms | 220.85–264.86 ms |
| 4 MiB GET p95 | 93.74–94.05 ms | 96.51–100.36 ms |

No OOM or memory-pressure state was observed; measured artifact egress remained
543,424,512 bytes per run. The resource measurements do not show increased CPU
or anonymous-memory consumption when the new bridge is inactive. Small PUT and
large GET tails were higher in these samples, while other phases improved;
this short, CPU-throttled control does not establish latency equivalence or
attribute every timing difference to the handoff code. The earlier claim based
on runtime `532db7a28be5` is superseded by these final-image measurements.

### Current-main/shared-XFS application baseline

A separate new directory on Paris's existing shared XFS `data` LV hosted the
main-runtime control (`172ffef18648`, same Kura source tree as main `3552a2c78f4`).
The candidate (`04e128167d80`) used the existing encrypted thin fixture. Both
had the same 4 GiB cache budget, CPU/memory limits, client and workload. Order
was shared/thin/thin/shared. All **10,112 requests passed**, bringing the four
final benchmark groups to **32,384 requests with zero failures**.

| Measurement | Main / shared XFS | Candidate / thin LUKS XFS |
| --- | ---: | ---: |
| Eviction churn | 159.36–164.16 MiB/s | 156.55–157.45 MiB/s |
| 16 KiB PUT p95 | 28.99–29.84 ms | 34.87–35.82 ms |
| 16 KiB GET p95 | 2.66–3.20 ms | 2.99–3.51 ms |
| 4 MiB PUT p95 | 256.42–274.84 ms | 261.17–261.71 ms |
| 4 MiB GET p95 | 93.41–114.91 ms | 93.11–94.87 ms |
| Runtime CPU per run | 42.40–43.29 s | 43.21–43.39 s |
| Sampled peak anonymous memory | 43.41–44.50 MiB | 51.52–56.99 MiB |
| Settled anonymous memory | 17.35–21.17 MiB | 20.94–24.29 MiB |

The small-write tail increased by about 6 ms; eviction churn was modestly lower.
Sampled anonymous-memory peaks were higher in this comparison, despite the
runtime-only control's overlapping ranges. Neither result is a regional density
projection. Both controls were CPU-throttled, reported no OOM or memory-pressure
state, and served the same measured artifact bytes. This is a **production-style
baseline recreated on staging**, not a benchmark of live production, a mixed
fleet workload or a cold-cache saturation test. It changes both layout and
runtime; the preceding controlled comparisons isolate those separately.

The shared directory was created only after a free-space/filesystem check,
without reusing any existing directory. The original data LV was not reformatted.
The thick control and this shared-XFS control are diagnostic fixtures, not new
storage classes or alternative admission paths in the implementation.

### Retained-volume accounting

After scaling the qualified fixture from two replicas to one, the unmounted
second volume remained charged: total backing commitments stayed at
**13,958,643,712 bytes**, and its **3,457,155,072 mapped bytes** remained visible.
Only deleting its retained PVC through normal CSI cleanup released those mapped
bytes and reduced commitments to **6,979,321,856 bytes**. Pod disappearance alone
released neither physical allocation nor backing commitment.

After the final benchmarks, the pool remained healthy with two thin members:
**8,977,383,424 data bytes**, **17,199,104 metadata bytes**, and
**13,958,643,712 committed bytes**. Data and metadata reserves remained intact.
The 4 GiB-budget benchmark volume itself mapped **5,507,645,440 bytes** after
churn, reinforcing why cache usage or a quota cannot stand in for physical
allocation. These measured counters, rather than a successful trim command,
own the accounting conclusions.

### Final cleanup and release decision

Normal CSI deletion removed the benchmark and migrated claims and released all
thin commitments. The shared-XFS control directory was removed only after its
Pod terminated and its recorded inode and ownership marker matched. The empty
pool and its owned metadata spare were removed after checking every LV UUID
against the creation record. The original **128 GiB `data` LV** retained UUID
`qf316g-aMzF-KlpS-5jsX-yqKl-25BI-OhgZ5U`. VG free space and Kubernetes capacity/
allocatable both returned to **812,541,542,400 bytes**. Thin configuration and
node opt-in were removed; Canada was unselected and schedulable.

The fixture account/key rows, clients and local token file were removed. No
qualification PVs remain, including the previous source claims. The first health
check caught test clients still completing normal termination; a subsequent live
check confirmed all qualification Pods absent, CSI **3/3 Ready**, and all eight
original Kura runtime Pods at their original UIDs and Ready. Candidate CSI and
controller images remain on staging. The temporarily loaded kernel module was
not forcibly unloaded and no persistent host boot configuration was written.
Production was not changed.

**Keep this PR draft and production thin enrollment disabled.** The live-write
handoff correctness blocker and missing metadata-checker package are corrected.
Conservative backing contains the demonstrated fragmentation risk; physical
overcommit remains blocked. The requested no-performance-regression gate still
fails, with both direct random-read loss and application-level small-write/read
tail increases. Further sector, chunk and queue/concurrency experiments did not
remove the raw loss. A staged rollout limits exposure but cannot waive that gate.

Permanent OpenBao custody/audit/off-cluster recovery, real populated-thick-volume
multi-host migration, a host reboot, physical rack installation and public-ingress/
gRPC continuity still need their own qualification before the corresponding
production phase. This report does not infer those results from colocated final
replicas or direct HTTP traffic. The node-by-node rollout and rollback procedure
remains in [the storage interface](interface.md) and
[handoff runbook](../../kura-controller/thin-migration.md).

### Integration checks

Main `3552a2c78f4` is integrated. Three guidance-file conflicts retained both
main's maintenance/KVM instructions and the storage contract. The merge changed
no Kura runtime, controller or CSI implementation. Full controller and CSI Go
tests/vet passed again, as did the OpenBao/CSI Helm checks, managed rack-release
isolation and `git diff --check`.

After the required server dependency installation, **110 focused tests passed**
for key management, the OpenBao provider, HKDF, internal endpoint authorization
and environment configuration. Hex also selected `websock_adapter` 0.7.0 over
the upstream 0.6.0 lock; repeating with that dependency's local checkout removed
still requested the same change. Only that lock entry was refreshed. A subsequent
`MIX_ENV=test mix deps.get --check-locked` passed and all 110 tests passed again.
These checks validate integration, not a new permanent OpenBao deployment.

### Additional random-read investigation

Neither changing encryption sectors to 4 KiB nor creating a separate 4 MiB-chunk
pool removed the random-read cost. The clean larger-chunk ABBA run measured
**67.05–67.77k IOPS thick versus 50.98–51.63k thin** at 4 KiB/QD32. Both layouts
kept AES-XTS with a 512-bit key. The sector experiment was exploratory and some
later samples overlapped an interrupted result copy; it is not release evidence.
Neither change was adopted: encryption sectors remain 512 bytes and new pools
use 512 KiB chunks.

An own-process kernel profile showed extra thin B-tree lookup, bio cloning and
block-accounting work, with the fio caller CPU saturated. A second bounded ABBA
experiment used fresh disposable thick/thin 2 GiB devices, identical 512 MiB
files, 4 KiB direct/libaio reads, QD32 **per job**, 12 seconds plus 2 seconds
ramp. Each row is a distinct total queue depth; these are not interchangeable
with the single-job QD32 comparison.

| Jobs / aggregate queue depth | Thick IOPS | Thin IOPS |
| --- | ---: | ---: |
| 1 / 32 | 67,688–68,243 | 48,001–48,400 |
| 4 / 128 | 237,263–242,169 | 154,848–156,533 |
| 8 / 256 | 429,224–429,546 | 248,762–249,513 |
| 16 / 512 | 500,862–508,145 | 258,481–260,175 |

All samples completed without I/O errors. Increasing concurrency did not hide
the regression. The fixture runtime was rolling during the later concurrency
samples; this experiment is an additional diagnostic, not an uncontended fleet
capacity estimate. The earlier paired idle-fixture result of approximately
25.6% lower single-job IOPS remains the controlled release evidence. No global
scheduler, security-mitigation or cache-drop changes were used. All private
benchmark devices were removed after the run.


## Historical follow-up: tuning and live migration fixes — 2026-10-27

**Historical status, superseded by the qualification above:** Sequential-read and random-write regressions were
recovered, and the premature donor restart was corrected. The no-regression and
uninterrupted live-write migration gates still failed at that point. This section supersedes
the current-state conclusions in the original rehearsal below, whose failed
results remain part of the evidence. Production was not changed.

### Changes and reproducible validation

- `172ffef18648` retains the resize rollout hold until every LVM replacement has
  a fresh, valid runtime observation with initial backfill complete and no
  exhausted real-peer catch-up budget. Kubernetes Ready alone is insufficient.
- `532db7a28be5` adds process-incarnation-bound retirement of existing public
  connections. The controller waits for endpoint/peer handoff and an empty
  original connection cohort before deleting a thin migration donor. HTTP/1
  finishes responses with `Connection: close`; HTTP/2 retains its bounded
  connection aging. New probes do not prolong the original cohort. A queued
  template change rolls through this same path while the StatefulSet remains
  OnDelete, preserving the new PVCs.
- `695bbe1f8d2d` carries the retirement request through the existing authenticated
  kubelet port-forward with end-to-end peer mTLS. Direct Pod IP connectivity was
  not available on every controller-to-node path. No NetworkPolicy or RBAC
  widening was needed. Tests cover mTLS, malformed/incarnation-mismatched
  receipts, remaining connections and cancellation of stalled TLS.
- `76d90eeb549c` uses **512 KiB chunks for new pools** and
  `--perf-submit_from_crypt_cpus` for newly opened thin encryption mappings,
  retaining encryption workqueues and discard. Existing pool geometry is not
  changed in place, and already-open mappings do not silently adopt new flags.
  Larger chunks retain more physical allocation around small live extents.
- The benchmark now supports a bounded 1 GiB shuffled-read working set and a
  persisted hash/size manifest for independent post-migration verification.

Controller and CSI Go tests/vet passed. The
[runtime qualification](https://github.com/tuist/tuist/actions/runs/40565922912)
passed formatting, Clippy and 1,252 Rust tests (49 ignored), plus the cached
binary test. The
[controller build](https://github.com/tuist/tuist/actions/runs/40567053272)
passed before deployment. The
[CSI image workflow](https://github.com/tuist/tuist/actions/runs/40566471144)
ran both the actual-driver suite and mechanism harness at **64 and 512 KiB**
before publishing. The 512 KiB actual-driver suite completed in 28.25 seconds:
A released **805,830,656 bytes**, and B consumed exactly that amount according
to the pool counters. Open-deleted files, failed/ignored discard, quota refusal,
restart, stale pod/generation rejection, concurrent operations and data/metadata
reserve refusal passed. These disposable Ubuntu VMs ran kernel 7.0.0-1017-azure;
they do not substitute for the staging host's 6.8 kernel or NVMe measurements.

The 512 KiB fragmentation counterexample still retained **more than 1 GiB mapped under a
256 MiB project quota**, after working discard. Physical overcommit remains
blocked. Only `ceiling-backed-v1` is implemented, and grant reductions/trim
release no backing commitment. Actual exhausted-metadata recovery is not
qualified by tests that refuse admission before reserves are consumed.

### Updated Paris performance

Same Samsung NVMe host, kernel 6.8.0-146-generic, equal approximately 6.5 GiB
virtual thick/thin volumes, LUKS2, one runtime CPU and 768 MiB memory. Thick
retained its existing mapping and filesystem defaults. Thin had project quotas,
discard, 512 KiB chunks and the write-submission flag. No global cache dropping
or production traffic was used. Short paired ranges below are observations,
not statistical confidence intervals or fleet capacity estimates.

| Direct I/O measurement | Thick | Tuned thin | Interpretation |
| --- | ---: | ---: | --- |
| 1 MiB sequential read, QD32 | 3,707–3,914 MiB/s | 3,734–3,938 MiB/s | Original roughly 32% regression recovered |
| 1 MiB sequential write, QD32 | 2,182–2,203 MiB/s | 2,199–2,201 MiB/s | Comparable in this run |
| 4 KiB random write, QD32 | 62.06–62.08k IOPS | 61.35–62.61k IOPS | Original roughly 26% regression recovered |
| 4 KiB random read, final QD32 repeat | 66.38–66.94k IOPS | 49.46–49.69k IOPS | **25.6% lower mean IOPS remains** |
| 4 KiB random read, final QD1 repeat | 7.75–7.79k IOPS | 7.48–7.50k IOPS | Mean latency 127.2–127.8 vs 132.2–132.5 µs |

Final random-read p99 completion latency at QD32 was 0.839–0.913 ms thick versus
1.138–1.220 ms thin. fio 3.36 used direct libaio on a 512 MiB file; tuning trials
ran 10 seconds plus two seconds ramp, and the final QD1/QD32 comparison ran
12 seconds plus two seconds ramp in thick/thin/thin/thick order. No errors
occurred. Crypto-workqueue bypass and same-CPU variants did not recover random
reads; write-workqueue bypass reduced sequential writes to about 557 MiB/s,
and same-CPU variants reduced sequential reads to about 2.3 GiB/s. Those
alternatives were rejected. The cipher and 512-byte encryption sector size
were not weakened or changed to obtain the selected result.

With the final runtime (`532db7a28be5`) on both layouts, four authenticated HTTP
runs completed **10,112 requests with zero errors**, each including six GiB of
eviction writes. Bulk churn was 153.81–156.30 MiB/s thick versus
152.94–156.44 MiB/s thin. Four MiB GET p95 was 94.23–95.36 ms versus
93.73–99.09 ms. **Small requests were slower in this pair:** 16 KiB GET p95
was 2.45–2.65 ms versus 3.56–4.95 ms; PUT p95 was 25.71–28.78 ms versus
32.88–35.32 ms. First-run 4 MiB PUT outliers were 634 ms thick and 414 ms thin,
with subsequent runs at 251 and 262 ms. The one-CPU fixtures throttled in both
layouts. Bulk similarity does not erase the small-request or direct-read cost.

A second four-run workload seeded 256 four-MiB objects in bounded batches, then
shuffled and checksummed the complete **1 GiB** corpus, larger than the runtime's
768 MiB memory limit. Its 2,048 PUT/GET requests had zero errors. Read throughput
was 399.50–441.26 MiB/s thick versus 456.14–459.04 MiB/s thin; p95 was
112.77–116.18 ms versus 113.86–116.40 ms. This exceeds the memory working set,
but does not establish that every read was cold. The direct-I/O results remain
the evidence for disk-bound random reads.

### Isolating the runtime change from storage

The original `6e7fbe5cf700` runtime also predates unrelated main changes. A
separate main/candidate/candidate/main comparison therefore used the **same
tuned thin volume**, identical pod resources and isolated peers, recreating the
runtime pod between trials. The
[baseline image](https://github.com/tuist/tuist/actions/runs/40569920292)
was built at `172ffef18648`, whose entire `kura/` tree exactly matches main merge
base `9e577621d4713ff3103c055e2d341e32dfd07d90`. Candidate was `532db7a28be5`.
This isolates the retirement instrumentation from the storage layout; it is not
a recreation of the current production shared-XFS deployment.

All **10,112 requests passed**. Mean cgroup CPU was 43.5768 seconds baseline
versus 43.5944 seconds candidate (about +0.04%). Peak anonymous memory was
44.77–58.73 MiB versus 46.88–51.88 MiB, settled anonymous memory
18.79–20.99 MiB versus 18.97–20.13 MiB. Both remained at pressure tier zero,
with a 64 MiB transient-memory peak and no OOM. Client response bytes were
543,424,512 in every run. Retained bytes varied from approximately 2.2 to
2.48 GB in both as segment rotation progressed. Churn throughput was
154.00–157.26 MiB/s versus 155.31–156.52 MiB/s. Four MiB GET p95 ranges were
91.27–94.61 ms versus 93.45–98.09 ms; two samples do not establish exact latency
equivalence. Peer-traffic resource cost was not stress-qualified by this
isolated benchmark. These are bounded measurements, not regional memory gains.

### Repeated actual migration

Staging deployed CSI `76d90eeb549c`, controller `695bbe1f8d2d` and fixture
runtime `532db7a28be5`. A new 16 GiB/512 MiB metadata pool used 512 KiB chunks,
1 GiB data and 64 MiB metadata reserves, and four slots. Only the disposable
account/instance was enrolled. Its automated server provisioning was held for
the fixture alone after a preflight detected that test traffic could reactivate
its archived server record and overwrite the test spec. That earlier reset
occurred before node selection and is not counted as a migration attempt.

The Canada source had two 4 GiB encrypted file-backed replicas. Both were
verified caught up, with the 1 GiB manifest independently checksummed through
each source, before selection. Thin was already desired, but repeated preflight
observations confirmed that both source pod UIDs remained unchanged while the
source was unselected. The Paris pool backed both replacement ceilings before
the Canada node was cordoned and selected. The different host taints were
handled only in the fixture's tolerations; optional memory-ceiling bin packing
was disabled for this fixture because Paris does not advertise that resource.

After the first thin replacement appeared, a harmless pod-template annotation
was deliberately queued during catch-up. Both volumes migrated, the annotation
rolled through a further restart of replica zero, and the hold released only
after complete runtime catch-up: **441 seconds from node selection**. Replica
zero retained the same thin PVC and PV across that queued restart. Both final
replicas were Ready on the desired revision. Final commitments were
13,958,643,712 bytes. This demonstrates storage migration, queued-update
serialization and stable volume identity across a pod replacement.

**The continuity gate still failed: 2 failures in 10,788 no-retry requests over
579 seconds.** Both were 404 GETs at 19:51:14 UTC immediately after successful
PUTs, at the Canada donor's serving handoff. Neither key belonged to the seeded
corpus. There were no EOFs, failed PUTs or checksum mismatches. All 128 seeded
small objects and all 256 four-MiB objects then verified through the Service
and independently through each final replica: **1,152 successful final reads**.
The final checks do not prove the two just-written objects survived and do not
erase their transient misses.

This narrows the remaining defect: connection retirement prevents abrupt
transport termination, and initial catch-up prevents promotion of an empty
replacement, but neither proves the destination received the final writes on
old connections. Closing a PUT response can send its following GET to the new
replica ahead of asynchronous replication. A correct live-write handoff needs
an explicit destination-bound completion barrier coordinated with write
admission/serving ownership, not a longer sleep or client retry. Existing
positive-fence handover is a separate protocol and was not activated by this
legacy migration fixture. Do not claim that the connection-cohort receipt is a
data-transfer receipt or that this rehearsal qualifies zero-error migration.

The live key path used **`tuist_root`**, with projected-token/node/account
ownership checks and sealed transport. It does not requalify OpenBao custody.
Actual thick-to-thin physical migration, single-copy standby, host reboot,
public ingress/HTTP2/gRPC continuity and real pool metadata exhaustion remain
outside this rehearsal. Thick-to-thin controller unit tests are separate from
physical migration evidence.

### Cleanup and release decision

The source annotation and cordon were removed. Fixture workloads, claims,
account/lifecycle hold and wrapped keys were removed after confirmed physical
volume deletion. The pool and its metadata spare were removed only after UUID
checks and an empty CSI ledger. VG free space returned to **812,541,542,400
bytes** and the original 128 GiB data LV retained UUID
`qf316g-aMzF-KlpS-5jsX-yqKl-25BI-OhgZ5U`. Thin configuration and the opt-in node
label were removed. The temporary module remains loaded; no boot configuration
was changed. All eight pre-existing Kura runtime pods retained their UIDs and
were Ready, and the CSI DaemonSet completed its cleanup restart. The candidate
CSI/controller images remain on staging.

**Keep production enrollment disabled and the PR draft.** Further work must
resolve and repeat the live-write handoff test and either eliminate the remaining
performance cost or explicitly change the acceptance criterion. Successful
safety tests, eventual data verification and warm/bulk throughput do not satisfy
the requested no-regression/no-interruption gate. #14825 must use the final
layout to remeasure regional capacity and memory; earlier shared-XFS gains are
not transferable results.

## Original 64 KiB rehearsal — retained historical evidence

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
