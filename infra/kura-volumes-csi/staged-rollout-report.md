# Encrypted LVM rollout rehearsal — 2026-10-26

The rack implementation now has an encrypted storage path, and staging exercised
incremental migration from both production-style plain local-path storage and
existing encrypted loop files. No production resources were changed. This does
not mean existing hosted volumes are already encrypted: production enrollment
and physical rack replacement remain separate operations.

## Implementation and deployment

Fresh rack storage installations, including resident-installer layouts, create
one `kura-volumes` VG, a 128 GiB XFS data LV with project quotas, and free extents
for per-claim LUKS2 LVs. Joined/populated hosts are never reformatted by a deploy.
The rack CSI DaemonSet lives in the independently deployed rack release, with
the same key-service identity and mount contract as the rented-node plugin.
Explicit, disjoint pool ownership keeps rack readiness out of the main release.

Regional LVM enrollment encrypts every account, including those whose encryption
flag is off, and renders at least two replicas. The controller recognizes old
backing even when the StorageClass does not change, holds the StatefulSet,
requires fresh sibling readiness and completed backfill, transfers client/peer
roles, observes the endpoint handoff, then replaces one claim. Operator pauses
and positive-fence recovery holds remain effective.

The tested deployment branch is `codex/kura-encryption-staged-rehearsal`. Runtime
`sha-6e7fbe5cf700` remained pinned throughout. Controller/CSI were
`sha-ae6b8b3d489f`; the final server was `sha-ef07ca13e38d`, including automatic
standby creation. The provider was updated to `ae6b8b3d` after its tests passed.

- [Provider build and tests](https://github.com/tuist/tuist/actions/runs/40412769027)
- [Initial staging deployment](https://github.com/tuist/tuist/actions/runs/40412773109)
- [Rack-release and standby-policy deployment](https://github.com/tuist/tuist/actions/runs/40414368008)
- [Deployment with an unready rack plugin](https://github.com/tuist/tuist/actions/runs/40416126245)
- [Final staging deployment restoring normal CSI ownership](https://github.com/tuist/tuist/actions/runs/40417421772)

## Migration cohorts

Each cohort began on the legacy Canada host and moved to the prepared Paris LVM
host. These were temporary private Kura server rows for existing staging smoke
accounts, created through the application. A bounded lifecycle hold prevented
the no-runner-demand sweep from retiring them during the test. Traffic used
scoped, expiring account tokens and the stable in-cluster client Service.

| Cohort | Starting storage | Replacement | Migration observation | Saved corpus |
| --- | --- | --- | --- | --- |
| Regional smoke, encryption flag off | Two plain local-path claims, 8 GiB each | Two encrypted LVs, 8 GiB each | 22:36:48–22:37:49 UTC | 512 objects verified on each replacement |
| Tuist smoke, encryption flag on | Two encrypted loop files, 8 GiB each | Two encrypted LVs, same StorageClass | 22:40:04–22:41:10 UTC | 512 objects verified on each replacement |
| Dedicated smoke, initially one copy | One plain local-path claim, 8 GiB | Two encrypted LVs, 25 GiB each | Standby Ready 22:51:27; old copy stopped 22:51:28; replacement Ready shortly after 22:52 | 256 objects verified on each replacement |

The third cohort used the actual deployed server manifest without overriding
its replica/storage policy. It exercised automatic standby creation and the
account's normal disk sizing, including an 8→25 GiB change. The new rack-release
plugin allocated both LVs and obtained their keys through the normal server
endpoint. All six resulting PVs had `backing: lvm`, and host inspection confirmed
six LUKS headers on the expected LVs.

The first cohort was paused with operator `OnDelete` before enrollment. Its
original pod UIDs remained unchanged while traffic continued. Resuming the
controller-owned hold completed one copy at a time. The workload-controller
leader was deleted during that migration; its replacement continued from the
persisted hold and handoff state. Two-second sampling for the first two cohorts
observed at least one ready, non-terminating pod and no empty client endpoint
sample throughout migration. Sampling is not proof against shorter gaps.

## Traffic and failure observations

The [probe source](rehearsal/probe.go) uses random 16 KiB bodies, checksum-declared
PUTs and byte-for-byte GET verification. Two workers continuously read the saved
corpus, write new objects and read those back, with a ten-second request timeout
and a 200 ms pause per cycle. There is no application retry loop; Go's HTTP
transport can retry an idempotent request on a stale connection. The saved corpus
checks cover pre-migration data, not an exhaustive inventory of every cache key.

One PUT returned EOF at 22:39:17.433 UTC in the encrypted-file cohort, before its
migration began at 22:40:04. Both original pod UIDs, readiness and the selected
endpoint were unchanged around that failure. It occurred almost exactly 300
seconds after the probe started; the pinned runtime has a 300-second HTTP
connection lifetime. Connection recycling is a hypothesis, not an established
root cause. An unchanged-instance 15-minute control completed 10,026 requests
with zero failures, so the control did not reproduce it. No checksum mismatch
was observed. Do not describe this entire rehearsal as error-free.

The migration probes stopped at 23:02:44 UTC. Their totals exclude initial
seeding and the separate saved-corpus verification passes:

| Probe | Duration | Requests | Failures |
| --- | ---: | ---: | ---: |
| Plain → encrypted LVM | 28m 28s | 41,307 | 0 |
| Encrypted file → encrypted LVM | 28m 27s | 37,892 | 1, before migration |
| One-copy → two-copy encrypted LVM | 11m 31s | 17,151 | 0 |
| Unchanged-instance control | 15m | 10,026 | 0 |

The three migration probes total 96,350 requests. Sanitized per-probe reports,
volume inspection and sampled transitions are retained in
[the evidence directory](rehearsal/2026-10-26/). No token or corpus payload is
included. Results establish the observed migration behavior under this workload;
they are not a production performance benchmark or a zero-error guarantee.

## Rack release isolation

Staging has no physical Linux rack-storage host. Paris was temporarily assigned
to `kuraVolumesCSI.rackPools`, which transferred its plugin into the real rack
release. Fresh encrypted allocations and restages exercised that release's
service-account/key identity and host mounts.

At 22:55 UTC a deliberately failing readiness probe made the rack DaemonSet
report 0/1 ready while its process remained running. The ordinary staging
workflow completed successfully and main Helm revision 874 was deployed; the
rack DaemonSet still reported 0/1 ready at 22:59:01. The independent release did
not block or roll back the server. This tests readiness isolation, not a physical
power failure. The injected probe was then removed.

An attempted synthetic offline Node was refused by staging RBAC, so no such
Node was created and no credentials or permissions were changed. The unready
DaemonSet test provided the relevant release-wait evidence within existing
permissions.

## Key-service failure and recovery

Only the staging rack plugin's key-service URL was temporarily pointed at a
nonexistent path on the same staging server. No account root key or global key
service setting was changed. After moving the regional smoke instance's client
endpoint to ordinal 1, ordinal 0 was deleted normally. At 23:01:18 UTC its
replacement reported `FailedMount`: key fetch returned 404 and CSI refused to
open the volume. Its sibling kept the same UID and Ready transition throughout,
and the continuous probe recorded no failures.

Restoring the original URL let kubelet retry and recover the pod. All 512 saved
objects passed byte-for-byte checks at 23:02:42. The PV remained
`pvc-c95d4403-3a2d-4c9d-9d26-020ac40fc97e`, with LUKS UUID
`5c44e999-f893-4fc5-b83f-09800788f732` before, during and after the failure.
The existing encrypted volume was reopened rather than replaced or reformatted.
This tests unavailable-key mount behavior and recovery; it does not simulate
every key-service outage mode or a node reboot.

## Validation and limits

Passed locally: full controller and CSI Go tests and vet; rack chart parity and
ownership render tests; provider rack-install and Linux-controller tests and
vet; 270 targeted server tests covering regions, capacity and manifest rendering.
The provider CI also passed its tests and generated-file checks. The full
`infra/mise/tasks/helm/rack-independence.sh` check passed across staging, canary
and production chart renders. Additional
handoff tests verify role demotion, missing endpoint holds and single-copy safety.

No physical rack installer boot was performed. Both curtin layouts are covered
by rendered-storage-graph tests, but disk ordering, firmware and actual rack
installation need validation on the first spare rack host. Final replicas were
colocated on one prepared Paris host; this does not establish physical host-loss
availability. An in-place reinstall of the only rack storage host is still an
outage. Prepare spare capacity before production enrollment.

Positive-fence instances retain explicit recovery holds and were not activated
in these fixtures. The probes do not test public ingress, end-to-end runner
demand or production load. An unrelated staging Linux runner node became
NotReady around 22:41, before the provider update; it was not changed for this
rehearsal. Existing Canada/Gravelines Kura workload identities were checked
separately for unintended changes.

## Cleanup and next rollout

All three temporary server rows reached `destroyed` through the normal
application reconciler by 23:05:34 UTC. Their KuraInstances, pods, PVCs and six
LVs were removed. Only the 128 GiB data LV remained, with 812,541,542,400 bytes
free in the VG. Probe/token files were removed with the temporary probe pod and
scoped server files were deleted. Existing Canada/Gravelines Kura pod UIDs and
readiness matched the pre-rehearsal inventory.

The injected readiness/key failures were removed. With no CSI claims remaining
on Paris, the kept rack DaemonSet was explicitly retired before returning Paris
to the main release, avoiding overlapping plugins. The staging-only rack pool
overrides were removed from the deployment branch. The final deployment passed,
and the main CSI DaemonSet returned to 3/3 Ready with no rack plugin remaining.
Only Paris remains enrolled in
LVM on the staging branch; the implementation branch leaves enrollment empty.
Production remains unenrolled by this work.
Follow [the rollout runbook](lvm-rollout.md): additive deployment first, prepared
spare capacity second, a deliberately bounded cohort third, then region-wide
enrollment only after verification. Keep both the CSI driver and LVM-aware
admission installed across rollback; reverting the region toggle is not a safe
storage rollback.
