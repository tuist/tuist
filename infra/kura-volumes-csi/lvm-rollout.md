# Moving hosted Kura volumes to encrypted LVM

The node owns one `kura-volumes` volume group. Its 128 GiB `data` logical volume
holds kubelet, containerd, CSI metadata and legacy local-path directories on XFS
with project quotas. Each new CSI data claim gets its own logical volume.
Every account in an enrolled LVM region uses LUKS2, independently of the
account encryption flag. The plain CSI class remains available for diagnostics.
Fresh rack storage installs create the same layout through curtin, including
resident-installer layouts. Existing populated hosts are never converted live.

The design removes the extra filesystem journal flush imposed by loop-backed
LUKS. The staging measurements recorded in PR #14152 on 2026-10-26 were 3.3 ms
for a synced 16 KiB plain write, 3.4 ms for LUKS on LVM, and 6.9 ms for LUKS on
a backing file; corresponding median Kura uploads were 17, 18 and 32 ms. These
are prior measurements, not validation of this rollout.

## Initial rented-host bootstrap rehearsal (historical)

This was the first, explicitly approved single-host staging reinstall. The
continuous migration procedure below supersedes its account-flag rollout.

1. Inspect the live staging server/controller revisions and preserve their
   changes in a new deployment branch. Do not force-push a shared deploy branch.
2. Build the updated CAPI provider and deploy the additive CRD, CSI driver,
   Kura controller and server. Keep `kuraVolumesCSI.lvmRegions` empty until the
   selected region is ready to switch. The Paris node pool is `kura-scw-fr-par`;
   its server region ID is `scw-fr-par-runners`. Verify that the CSI driver and its
   service account/RBAC remain installed across rollback.
3. For the initial staging `scw-fr-par` conversion, confirm the single host's
   Machine and Kura workloads. There is no evacuation destination at one fleet
   replica. The accepted outcome is a regional outage and cache refill.
   Delete the **Machine**, allowing CAPI to reinstall and return the rented
   server to its pool; do not delete the server at the provider or delete the
   Kubernetes Node to force replacement.
4. First boot converts only an empty, separate XFS `/data` on md. Scaleway can
   create that filesystem without mounting it or adding it to `fstab`. If
   `/data` is not mounted, bootstrap requires exactly one unmounted XFS md
   candidate and mounts it read-only to inspect its contents; ambiguity or
   existing data aborts the join before any wipe. The source
   is journaled before wiping. Retries resume PV/VG/LV creation and preserve
   an already formatted data LV. A joined host or populated filesystem is
   refused. Vultr instead supplies the detached non-ESP RAID leg to the same
   conversion; its OS remains on a single disk.
5. On the replacement, verify `vgs`, `lvs`, `findmnt /data`, and XFS project
   quotas. The data LV must be 128 GiB. Verify that the CSI plugin advertises
   `status.capacity` and subsequently `status.allocatable` for
   `tuist.dev/kura-disk`, excluding the data LV.
6. Set `kuraVolumesCSI.lvmRegions: [scw-fr-par-runners]` on the staging deploy branch.
   In that initial revision this applied the plain LVM class to ordinary accounts
   and retained the encrypted class for flagged accounts. Both requested and limited the
   extended disk resource; neither reserves the data claim as ephemeral
   storage. Confirm the rendered annotation matches the desired revision.
7. Verify a flagged instance obtains its volume key, creates LUKS on an LV,
   reaches Ready and serves checksum-verified PUT/GET. Restart one replica and
   confirm the same volume, LUKS UUID and data return without formatting.
   Repeat for a plain instance: direct XFS on the LV and no LUKS header.
8. Run the same small-object PUT/GET benchmark against the plain LVM instance
   on this host. Record payload size, sample count, warmup, concurrency,
   median and tail latency, and verify response content. Do not compare hosts
   or protocols as evidence of the storage-only difference.

Until step 6, legacy manifests may exceed the replacement's smaller `/data`.
Keep this window bounded and treat it as part of the accepted staging outage.
A mixed fleet is not a way to migrate silently: LVM pods require advertised
capacity and plain claims cannot fall back to files.

## Staging validation, 2026-10-26

The approved Paris Machine replacement used the existing rented server
`tuist-kura-em-staging-1` (`915db32b-344c-42e4-932c-e51ab0a5e9fb`), through
Machine deletion. The replacement is `tuist-tuist-kura-fleet-fm4h8-qmkn8`.
The OS reinstall ran from 21:31 to 21:38 UTC. Its custom layout created XFS on
`/dev/md2` but omitted `/data` and its `fstab` entry; the original mount guard
stopped without wiping. The guarded discovery correction let bootstrap resume,
and the replacement reached Ready at 21:57 UTC.

The live VG is 949,980,495,872 bytes (884.738 GiB). Its `data` LV is exactly
128 GiB, mounted as XFS with `prjquota`. Both Node capacity and allocatable
advertised `tuist.dev/kura-disk: 812541542400` (756.738 GiB), precisely the VG
minus the data LV. Four test replicas each requested and limited `8Gi` of that
resource and reserved no claim bytes as `ephemeral-storage`.

Temporary instances for the existing staging `tuist` and regional smoke
accounts exercised the deployed Paris manifest settings with two replicas
each. They used normal capacity admission and account-scoped cache tokens.
Only these new test server rows were held in the 15-minute drain window so the
private-cache demand sweep would not retire them before validation; the
manifests had no external peers. This validates the volumes and controller,
not an end-to-end runner-demand provisioning flow.

CSI created four LVs, two with LUKS2 and two with direct XFS. The server issued
key version 1 for each encrypted claim. After deleting ordinal 0 of each test
instance, CSI unstaged and restaged both existing volumes, fetched the encrypted
key again, and emitted no formatting event. Both replicas returned the saved
16 KiB object with its original SHA-256. LV and filesystem UUIDs were unchanged;
the encrypted volume's LUKS UUID remained
`86a40585-647f-4e6b-a7e5-d941d04fdccf`. The plain LV had no LUKS header.

The same-host benchmark used Kura's `/api/cache/gradle/{key}` PUT/GET route,
HTTP/1.1 keepalive, concurrency 1, fresh random 16 KiB bodies, 20 warmup pairs
and 200 measured pairs per instance. Each upload declared its SHA-256 and every
GET was compared byte-for-byte. The client ran in the Paris CSI pod and called
the local Kura pod IPs directly.

| Backing | PUT median | PUT p95 | GET median | GET p95 |
| --- | ---: | ---: | ---: | ---: |
| LUKS2 on LVM | 11.47 ms | 18.59 ms | 0.99 ms | 1.23 ms |
| Plain XFS on LVM | 11.88 ms | 17.92 ms | 1.14 ms | 2.16 ms |

The fresh RAID mirror was resynchronizing at about 200 MiB/s. These are
functional same-host measurements under that background load, not a quiet-disk
comparison against the earlier loop-file benchmark or evidence that encryption
is faster. All 440 upload/download pairs, including warmup, passed content
verification. Normal teardown removed all four test claims and LVs; both test
server records reached `destroyed`. Only the 128 GiB data LV remained, with
812,541,542,400 bytes free in the VG. Temporary credentials were removed.

First-boot conversion ran with provider `3d339167`. The final inspection
refinement allows XFS journal replay on the read-only mount, because
`norecovery` could hide committed files from the emptiness check. Its safety
behavior is covered by the shell regression tests; the host was not reinstalled
a second time merely to exercise that option on an already-empty filesystem.
The final staging provider is `3e8f2a29`; server, controller and CSI remain on
`sha-884be9cebbec`, and Kura remains on `sha-6e7fbe5cf700`. The final
[provider build](https://github.com/tuist/tuist/actions/runs/40408421405) and
[staging deployment](https://github.com/tuist/tuist/actions/runs/40409103928)
passed. Benchmark demand also woke the smoke account's pre-existing archived
`ca-east` server; that instance remains under its normal public-cache lifecycle.

## Production preparation (requires separate rollout approval)

No production reinstall is authorized by the staging work.

After staging validation, select one region and inventory every volume's
backing, node and serving role. Deploy additive components first, with the
region setting unchanged. Newly provisioned rented cache hosts use the smaller
`/data`, so coordinate provider adoption with this migration; do not assume an
unmigrated region can use the replacement as a full-size local-path host.

For a region that can accept a bounded outage, the staging sequence is the
simplest reproducible path: explicitly approve the window and cache refill,
reinstall the selected Machines through CAPI, verify the VG/resource, and enable
the regional setting. Reinstall one region at a time, validating recovery before
starting another. Production reinstalls and outages require separate approval.

For continuity, prepare replacement capacity and follow the staged procedure
below. Both plain local-path and same-class encrypted file claims now rebuild
one ordinal at a time using PV backing evidence. Completed backfill and actual
traffic handoff gate each deletion. Do not delete an outgoing Machine until it
has no cache pods or retained claims. See the
[staging rehearsal report](staged-rollout-report.md) for the live evidence and
physical rack limitations; it is not a fleet-wide availability guarantee.

Positive-fence instances retain their existing storage-migration recovery
requirements; do not bypass a hold to make the rollout progress. Avoid enabling
the encryption flag while replacing a controller older than PR #14152: the old
leader can treat the class change as a full teardown.

## Rollback and operations

The node layout is a reinstall boundary, not a Helm rollback. Keep the CSI
driver installed while any CSI PV exists. Rolling back the server/controller
must retain support for `diskResource` and the region's LVM setting; reverting
to ephemeral admission would measure the 128 GiB filesystem instead of the VG.
Disabling the region setting can change storage classes and removes LVM-aware
admission. It can initiate a rebuild onto the smaller `/data`, so it is not a
safe rollback after conversion. Prefer a forward fix or an explicit migration
to a replacement host. An operator `OnDelete` pause stops further migration;
resume through the controller-owned resize hold only after checking the last
replacement's readiness/backfill and available capacity. Do not switch to
`RollingUpdate` while old claims remain pinned to non-LVM hosts.

Moving a pool between the main and rack CSI releases is a separate operation:
their node selectors must never overlap. The rack DaemonSet has a Helm keep
policy so removing it from values does not uninstall a driver with live claims.
Explicitly retire the former owner during a controlled handoff; changing
`rackPools` alone is not sufficient to transfer it back to the main release.

The data LV can grow online with `lvextend` followed by `xfs_growfs /data`.
Reserve those extents first: this reduces the Kura budget the driver advertises
on its next refresh. It cannot reclaim extents held by tenant LVs. XFS does not
shrink online; reducing it requires reprovisioning.

A failed bootstrap leaves `/var/lib/tuist/kura-lvm-device` as conversion intent.
Investigate a refusal before changing this journal or formatting anything.
Deleting a Machine cleans claims pinned by either hostname or the CSI topology
key. Retained volumes still consume capacity until the CSI driver deletes them.

## Staged encrypted migration

Regional LVM enrollment now encrypts every account, without requiring its
feature flag. The plain class remains available for diagnostics. Unenrolled
regions retain their current behavior, including BER1's explicit legacy hold.
The CSI driver now records the actual backing in each PV's volume context.
A same-class encrypted file claim, or an older claim lacking this evidence,
is rebuilt once when the instance starts requesting `tuist.dev/kura-disk`.
This covers same-class migration without an operator deleting PVCs.

1. Deploy the additive driver/controller/server support with region enrollment
   unchanged. Check the pinned driver everywhere a destination may be placed.
2. Prepare spare LVM capacity. Preserve the old host and its serving volumes;
   do not reinstall or delete it to make room. Verify advertised capacity,
   quotas, CSI registration and key-service access on the destination.
3. For racks, first install the plugin through `rack-nodes` using
   `kuraVolumesCSI.rackPools: [rack-storage-ber1]`. The main Helm release excludes
   these pools and the rack release is never waited on. Fresh rack storage
   installations create the VG with curtin; old installations require a
   separately approved migration/reinstall. No live conversion is attempted.
4. Start with a small cohort. Each migrating instance needs at least two
   replicas and enough room for the old and new claims during overlap. Keep
   operator OnDelete/partition pauses until the chosen cohort is ready. A
   enrolled region automatically renders at least two replicas, allowing a
   one-copy instance to create a standby before its original claim is replaced.
   A direct single-replica CR bypassing that policy holds without deleting its
   claim. Positive-fence migrations retain
   their explicit recovery/handover requirements.
5. Change the cohort's desired storage and resource together, with a destination
   selector that can place replacements on prepared hosts. The controller holds
   the StatefulSet, preserves old pods, marks one outgoing pod, moves the client
   and peer pins, and waits for observed endpoint handoff before deleting it.
   It waits for fresh completed-backfill reports before moving the next copy.
6. Continuously PUT/GET through the stable client Service and verify objects
   written before migration on both replacement replicas. Check each PV's
   `backing: lvm`, the LUKS mapping, keys and resource reservations. An HTTP
   failure, checksum mismatch or loss of all ready endpoints stops expansion.
7. Enroll the remaining region only after the cohort passes. Reclaim an old
   host only when every claim/workload has left it. Region enrollment changes
   all manifests in that region; it is not itself a per-account cohort control.

Do not promise continuous availability for a rack with one physical storage
host undergoing reinstall. It needs replacement capacity. Staging has no rack
Linux storage host: a rehearsal using the rack release on a rented staging
host validates the release/CSI contract, not the physical rack installer.
