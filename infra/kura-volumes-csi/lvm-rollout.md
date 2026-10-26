# Moving rented Kura volumes to LVM

The node owns one `kura-volumes` volume group. Its 128 GiB `data` logical volume
holds kubelet, containerd, CSI metadata and legacy local-path directories on XFS
with project quotas. Each new CSI data claim gets its own logical volume.
Accounts with `kura_encrypted_volumes` use LUKS2; other accounts use plain XFS.
Rack nodes remain on their existing storage layout.

The design removes the extra filesystem journal flush imposed by loop-backed
LUKS. The staging measurements recorded in PR #14152 on 2026-10-26 were 3.3 ms
for a synced 16 KiB plain write, 3.4 ms for LUKS on LVM, and 6.9 ms for LUKS on
a backing file; corresponding median Kura uploads were 17, 18 and 32 ms. These
are prior measurements, not validation of this rollout.

## Prerequisites and staging sequence

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
   `tuist.dev/kura-disk`, excluding the data LV. No rack node should gain it.
6. Set `kuraVolumesCSI.lvmRegions: [scw-fr-par-runners]` on the staging deploy branch.
   This applies the plain LVM class to ordinary accounts and retains the
   encrypted class for flagged accounts. Both must request and limit the
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

## Proposed production rollout (requires approval)

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

For continuity, prepare replacement capacity and rehearse the migration before
approving it. Plain local-path claims change class and rebuild one ordinal at a
time. **An existing encrypted claim keeps the same StorageClass**, so changing
only its disk resource does not recreate its PV: a restarted pod would still be
pinned to the old non-LVM host, which cannot satisfy that resource. Explicit
replica/PVC migration and held workload templates must be sequenced around this
case; a blanket regional toggle followed by evacuation is insufficient. Use
completed backfill and actual traffic handoff as gates. Do not delete an
outgoing Machine until it has no cache pods. This continuity sequence remains
a required rehearsal, not a zero-downtime guarantee from the unit tests.

Positive-fence instances retain their existing storage-migration recovery
requirements; do not bypass a hold to make the rollout progress. Avoid enabling
the encryption flag while replacing a controller older than PR #14152: the old
leader can treat the class change as a full teardown.

## Rollback and operations

The node layout is a reinstall boundary, not a Helm rollback. Keep the CSI
driver installed while any CSI PV exists. Rolling back the server/controller
must retain support for `diskResource` and the region's LVM setting; reverting
to ephemeral admission would measure the 128 GiB filesystem instead of the VG.
Disabling the region setting changes storage classes for plain instances and
can initiate a rolling cache rebuild on `/data`, so it is not an immediate
safe rollback after conversion. Prefer a forward fix or an explicit migration
to a replacement host.

The data LV can grow online with `lvextend` followed by `xfs_growfs /data`.
Reserve those extents first: this reduces the Kura budget the driver advertises
on its next refresh. It cannot reclaim extents held by tenant LVs. XFS does not
shrink online; reducing it requires reprovisioning.

A failed bootstrap leaves `/var/lib/tuist/kura-lvm-device` as conversion intent.
Investigate a refusal before changing this journal or formatting anything.
Deleting a Machine cleans claims pinned by either hostname or the CSI topology
key. Retained volumes still consume capacity until the CSI driver deletes them.
