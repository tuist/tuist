# Implemented thin CSI contract

The opt-in `thin-luks-xfs-v1` layout uses LUKS2, XFS with project quotas, and a
shared thin pool. Only **`ceiling-backed-v1`** is implemented. Every virtual LV
is fully reserved against pool data capacity, including pending create intents,
retained volumes and incomplete deletions. Shrinking a grant or reclaiming
mapped blocks never releases that reservation. There is no physical overcommit,
floor-only admission, fairness policy or runtime budget-lease implementation.
The allocator in #14825 must consume this interface after #14152 lands.

## Sizing and admission

The PVC request denotes useful cache ceiling bytes, rounded up to MiB. CSI
returns the complete virtual device capacity in the PV, calculated as:

```
quota_hard_bytes = grant_cache_bytes + 2 GiB
virtual_bytes = round_up_64MiB(ceiling_cache_bytes + 2 GiB + 288 MiB
                               + ceil(ceiling_cache_bytes / 20))
```

The 2 GiB allowance is runtime staging/rotation workspace inside project 1.
The additional 288 MiB and 5% are outside its quota for the LUKS header, bounded
64 MiB XFS log, allocation groups and filesystem metadata. This versioned sizing
profile must still be measured against final Kura object distributions; it is
not a claim that arbitrary small-file workloads can use every useful cache byte.
Unknown profiles, invalid sizes and unaligned grant changes are rejected.

Fresh thin filesystems explicitly use a 4 KiB XFS log stripe while retaining
device-derived data alignment. This prevents large thin-device alignment hints
from padding small journal writes. Log size remains 64 MiB; encryption, quotas,
reserves and durability barriers are unchanged. Existing formatted volumes keep
their geometry on restage: adopting this format on one requires the normal
staged replacement, never an in-place reformat of populated storage.

`floor_cache_bytes`, `grant_cache_bytes` and `ceiling_cache_bytes` are separate
record fields. Initial floor and grant equal the ceiling. The trusted allocator
may change floor and grant within `1 MiB <= floor <= grant <= ceiling`. The
controller requests **virtual_bytes**, including overhead, as
`tuist.dev/kura-disk`; Kubernetes extended-resource requests and limits remain
equal. This conservative mode does not realize the projected shared-XFS regional
capacity gains. CSI independently serializes admission and rejects any create
whose complete virtual size does not fit, even if Kubernetes scheduled the pod.

Pool geometry is explicit: fresh pools use 512 KiB chunks; the driver also
qualifies existing 64 KiB pools. Changing geometry requires a new pool. Larger
chunks reduce mapping overhead but retain more allocation around small live
extents. Thin LUKS mappings retain encryption workqueues and submit writes from
those workers (`--perf-submit_from_crypt_cpus`); the flag applies at mapping open,
not retroactively to already open mappings. Pool chunk
zeroing must be enabled, discard must be processed, and `error_if_no_space` must
be set. Data reserves are at least 64 MiB. Metadata provisioning must cover
128 bytes per pool chunk, 1 MiB per admitted device slot, plus at least 16 MiB
of explicit metadata reserve. Default settings leave 1 GiB of data and 64 MiB
of metadata reserve, with 128 device slots. This intentionally conservative
metadata profile does not permit snapshots, external origins or unmanaged LVs.

Full ceiling backing bounds allocation despite fragmented files, open deleted
files, failed TRIM or an absent allocator. No new grant transaction is needed
for ordinary writes within that backed device. Missing/stale observations,
unknown pool members, identity changes, exceeded reserves, an unhealthy pool,
or quota/record disagreement refuse new creates and grant increases. Node
capacity is removed (JSON merge-patch `null`, not a present zero) on failed
observations. The scheduler cannot place new resource-requesting pods there;
Kubernetes 1.34's [kubelet admission](https://github.com/kubernetes/kubernetes/blob/v1.34.1/pkg/kubelet/lifecycle/predicate.go)
ignores absent extended resources when re-admitting resident pods. CSI still
refuses new allocation without a healthy observation, including for manually
bound pods. `kubelet_restart_test.rb` rehearses this on a disposable kind node;
hosted kubelets have not been restarted under it.
Reductions and cleanup remain
available. Pool extension is not required for safety and is not automatic.
Physical device failures and unauthorized administrative changes remain storage
failures; quotas do not make such failures harmless.

## Node-local API

With thin configuration enabled, the same CSI process serves HTTP over
`/data/kura-volumes/allocator.sock`, a `0600` Unix socket that also requires
Linux `SO_PEERCRED` UID 0 on each connection. Do not mount
this socket into tenant containers. There is no TCP listener and no separate
privileged quota agent. The trusted node allocator needs access to this socket,
not host devices or a shell. CSI and API handlers that change commitments,
grants or trims (create, delete, grant, reclaim) and observations take the pool
lock, then the per-volume lock. Node staging and publication take only the
volume lock and reapply the durable grant, so a stage waiting on the key service
does not stall the pool. An observation can see a volume mid-stage; a failed
observation only withdraws capacity until the next one.

- `GET /v1/node` returns schema `version: 1`, mode, node and pool identities,
  observation timestamp/duration, exact chunk/data/metadata byte counters,
  reserves, full committed bytes, available commitment, health and all volumes.
  Each volume includes stable CSI ID, LV UUID, pool UUID, floor/grant/ceiling,
  generation, bound pod UID, mapped bytes, and quota-used/hard bytes when mounted.
  Pending and retained records remain present; an unmounted device is activated
  only for reading its mapping counters, without obtaining its encryption key.
- `POST /v1/grant` accepts the request below, persists the new grant intent,
  updates XFS project 1 and verifies its hard limit. The response is the durable
  volume record with its advanced generation. A hard limit below current usage
  prevents further allocation but never deletes existing files. Eviction remains
  the runtime's responsibility. A retry with the same operation, old generation
  and exact floor/grant is idempotent. A different stale generation fails.
- `POST /v1/reclaim` uses the same identity fields and current generation. CSI
  flushes the filesystem, calls fstrim, and reads mapped sectors and pool counters
  again. It reports before/after counters and the smaller positive observed
  decrease. `commitment_released_bytes` is always zero in this mode. A failed
  trim returns an error; successful trim with no decrease returns zero release.

The experimental `borrowed_units: v1` parent additionally exposes
`POST /v1/units` for fenced create/drain/release/abort operations. CSI owns the
child lifecycle, mount propagation and control-file publication under these same
locks. See the [child contract](borrowed/README.md#child-lifecycle-contract) and
[qualification limits](borrowed/validation.md). Whole-device deletion can release
a child's backing; lowering its quota or trimming alone cannot. Ordinary runtime
builds and enrollment do not enable this prototype.

Example grant request (identities come from the fresh node observation):

```json
{
  "volume_id": "pvc-00000000-0000-0000-0000-000000000001",
  "lv_uuid": "<observed LV UUID>",
  "pool_uuid": "<observed pool UUID>",
  "pod_uid": "11111111-1111-1111-1111-111111111111",
  "generation": 2,
  "operation_id": "22222222-2222-2222-2222-222222222222",
  "floor_cache_bytes": 1073741824,
  "grant_cache_bytes": 2147483648
}
```

The CSI ID and LV UUID survive pod replacement. Kubelet's projected pod UID
binds publication to one pod incarnation; a different pod cannot bind until all
old targets have been unpublished. Publication/unpublication advances generation
and invalidates prior operations. Requests cannot supply device or mount paths.
Only the last operation is retained; this is bounded retry deduplication, not an
unbounded transaction-history service. The runtime allocator must fence its own
budget leases using this pod UID and generation and must not infer a lease from
a filesystem's free space.

Observations serialize administration, not tenant writes: counter reads are not
an atomic workload snapshot. Concurrent writes can obscure reclamation. Never
credit fstrim's reported bytes, deletions, an absent pod, or a terminating PVC.
Only confirmed physical observations describe released blocks, and only confirmed
LV deletion plus durable-record cleanup releases a ceiling commitment.

## Crash recovery and security

CSI writes/fsyncs `<volume>.thin.json` before creating its LV and retains it until
LV removal is confirmed. It records the LVM identities after creation. Retry can
complete an interrupted create; incomplete records continue to consume capacity.
A grant intent is durable before the quota command. Failed application makes
observations unhealthy until the operation is retried or re-stage reapplies the
recorded grant. Re-stage verifies LV and pool identities, assigns project 1 to
the tree, restores the hard quota and reads it back before publication.

The existing key service and versioned passphrases are unchanged. Thin opens add
`--allow-discards`; XFS is mounted with `prjquota`, and reflinks are disabled.
Discards expose which encrypted blocks are allocated or freed and reveal usage
patterns. They do not reveal plaintext, but this is a deliberate confidentiality
tradeoff required for physical reclamation. Keys remain stdin-only and are
cleared from memory after cryptsetup. Root on the host and CSI administrators
remain trusted; project quotas are not a boundary against either.

## Staged node enrollment and existing thick volumes

1. Deploy the new CSI and controller binaries with thin configuration absent.
   Old file/thick volumes keep their existing behavior. The new immutable class
   is `kura-thin-encrypted-nvme`; its allowed topology excludes legacy nodes.
2. Prepare landing capacity. The host must provide the `dm_thin_pool` kernel
   module before pool creation and after reboot. Confirm `dmsetup targets`
   lists `thin-pool`; arrange module loading through the host's normal bootstrap
   configuration. The CSI container does not mount host kernel modules or load
   them itself. `prepare_pool.rb` checks this prerequisite before any mutation.
   On a node with sufficiently free VG extents, run
   `prepare_pool.rb` with explicit VG, new pool name, data/metadata sizes, reserves,
   maximum volume count and canonical existing state directory. It creates only
   a new pool and writes private `thin-pool.json`. It never converts/shrinks an
   existing LV or consumes 100%FREE. Leave VG repair/recovery headroom separately.
   If a populated VG lacks free extents, use another prepared node and evacuate
   before rebuilding; there is no in-place shared-pool conversion shortcut.
3. Restart only this node's CSI pod. It loads the config once, advertises thin
   topology and reports pool capacity. Read `/v1/node`, validate local quota,
   encryption, restart/reclaim behavior, then explicitly mark the node
   `tuist.dev/kura-thin-ready=true`. Do not label unqualified capacity as ready.
4. Select the thin class for an isolated instance. Preserve the existing
   `tuist.dev/kura-lvm-migrate=true` single-source cordon gate. Thick source PVs
   do not bypass it. Catch-up, endpoint handoff, single-copy standby, retained
   claims, partition pauses and deletion safeguards still apply. Transition one
   source at a time using sufficient landing space for that source's claims.
5. Observe complete cleanup and healthy replacement replicas before preparing
   the next source. A single-host region still needs another host for an online
   migration. This design does not assume fleet-wide double capacity.

The node-local config is preferred for mixed fleets. Fleet-wide
`kuraVolumesCSI.thin` arguments are only for homogeneous prepared deployments;
setting them across unprepared nodes withdraws their capacity. Rack and rented
plugins have the same contract. Self-hosted defaults remain disabled.

Rollback stops new enrollment and preserves the thin-capable CSI, pool config,
ledger, key service and existing PVs. Never downgrade a node with thin PVs to the
old binary or reinterpret a thin PV as thick. Returning data to a different
layout requires the existing safe replacement/migration process. A layout grant
reduction alone never shrinks or replaces XFS.
