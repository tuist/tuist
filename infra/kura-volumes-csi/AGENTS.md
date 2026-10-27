# kura-volumes-csi

CSI driver `kura-volumes.tuist.dev` behind the `kura-encrypted-nvme`
StorageClass and the plain-XFS `kura-lvm-nvme` class. Encrypted PVCs get their own LUKS2 container, backed by a
logical volume in the node's `--volume-group` when the node has one, and
otherwise by a preallocated file on the node's `/data` filesystem. The passphrase lives
only on the Tuist server and is fetched on every stage, so a volume can only
be opened by its node while the server agrees.

It runs only as a node DaemonSet. Identity, Controller and Node services share
one binary and one unix socket. `csi-provisioner` runs as a sidecar in
distributed mode (`--node-deployment=true`, `--strict-topology`), so
CreateVolume and DeleteVolume run on the node that owns the volume.

## Contract

- Driver name `kura-volumes.tuist.dev`; topology key
  `topology.kura-volumes.tuist.dev/node`, value = node name (`--node-id`).
- Access: mount only (no block), `SINGLE_NODE_*` modes, fs type empty or
  `xfs`. Controller capability `CREATE_DELETE_VOLUME`; node capabilities
  `STAGE_UNSTAGE_VOLUME`, `GET_VOLUME_STATS`. No expansion.
- Volume id = PV name, validated against `^pvc-<uuid>$` before any path is
  built.
- State dir (`--state-dir`, default `/data/kura-volumes`, must be canonical):
  - `<id>.img`: backing file (file backing only), 0600, fully reserved with
    `fallocate`; capacity is `required_bytes` rounded up to 1 MiB.
    CreateVolume keeps `--reserve-bytes` (default 20 GiB) free on the
    filesystem.
  - `<id>.unformatted`: exists from CreateVolume until the first successful
    `mkfs.xfs`.
  - `<id>.key-version`: decimal key version the volume was formatted under
    (0600, written via `<id>.key-version.new` + rename, fsynced). Written
    before `luksFormat`; every reopen asks the server for exactly this
    version.
  - `<id>.lock`: per-volume `flock`, held for every RPC on the volume.
  - `<id>.img.new`: in-flight CreateVolume; renamed to `.img` after the marker
    is written.
- Device chain: `losetup --direct-io=on` loop, dm-crypt mapping `kura-<id>`
  (no discards; default workqueues, which keep throughput at the loop
  device's level where the inline `--perf-no_*_workqueue` modes cost 70%), XFS
  mounted `nodev,nosuid,noatime` at the staging path and bind mounted into
  pods. On an LV the dm-crypt mapping sits on the LV instead of a loop device.
- LUKS2: `aes-xts-plain64`, 512-bit key, PBKDF2 with 1000 iterations (the
  passphrase is already a uniformly random 32 bytes).

## Backing

- LVM (`--volume-group`, the chart's `kura-volumes`): LV `<vg>/<id>`, created
  by `lvcreate --wipesignatures y --zero y` after the unformatted marker is
  written, sized to the request rounded up to whole extents (an existing LV
  only has to hold the request). The volume group is Kura's alone, so no
  reserve is kept. Stage runs `lvchange --activate y` and `vgmknodes`, since
  nothing guarantees the device node after a reboot. Every LVM command passes
  `--config` disabling udev sync, the devices file and metadata backups; the
  DaemonSet shares `/run/lock/lvm` with the host. On staging (EPYC 7232P,
  same partition) a synced 16 KiB write took 3.4 ms on LVM against 3.3 ms on
  plain XFS and 6.9 ms on a loop file, whose inner journal flush also forces
  the outer filesystem's.
- File, on a node without the volume group: `<id>.img` in the state dir. The
  marker, key-version and lock files live in the state dir for both.
- A volume keeps the backing it was created with. Lookup checks for the LV
  first, then the file, so a node that gains the volume group serves both.

## Key fetch

`POST <--key-service-url>/_internal/kura/volume-keys` with
`Authorization: Bearer <projected token>` (audience
`kura-volume-keys.tuist.dev`, read from `--token-path` on every request) and
`{"volume_id", "public_key", "key_version"}`, where `public_key` is a fresh
X25519 key per request and `key_version` is omitted when the volume has no
recorded version yet (the server then uses the account's active key). The
server answers `{"key_version", "ephemeral_public_key", "nonce",
"ciphertext"}`. The client derives
`HKDF-SHA256(X25519 shared, salt = server_eph_pub || client_pub,
info = "kura-volume-key-transport/v1", 32)` and opens AES-256-GCM with
AAD = volume id; the plaintext is the 32-byte LUKS passphrase. 5xx and
network errors are retried and surface as `Unavailable`; 401/403 become
`PermissionDenied`, 404 `NotFound`. A response without a positive
`key_version`, or with a different version than the one requested, is an
`Internal` error.

## Deletion

DeleteVolume refuses (`FailedPrecondition`) while a loop device or the
mapping is still active. An LV gets the same erase and 32 MiB wipe and is then
`lvremove`d. Otherwise it runs `cryptsetup erase`, zeroes the
first 32 MiB of the file (header, backup header and keyslots), fsyncs, then
removes the file, marker, key-version file and lock. Without a header the
remaining ciphertext is unrecoverable even with the server key. A volume this
node does not have deletes successfully.

## Invariants

- Never format a device that is neither LUKS2 nor marked unformatted.
- Never guess a key version: a malformed or non-regular key-version file is
  `FailedPrecondition`. A LUKS volume with no key-version file is opened with
  the active key, and that version is recorded only after the open succeeds.
- The passphrase reaches cryptsetup on stdin only; it is never in argv, on
  disk or in logs, and the buffer is zeroed after use.
- Loop and dm devices do not survive a reboot; kubelet's re-stage rebuilds
  them and fetches the key again. There is no other recovery path.
- Mounts are verified through `/proc/self/mountinfo` (mapper path or device
  number); a foreign mount at a staging or target path is an error.

## Testing

```bash
cd infra/kura-volumes-csi
go test ./...
go vet ./...
```

Host commands and the mount table sit behind `Runner`, `MountTable` and
`Host`; the driver tests assert exact command sequences with fakes. The key
client test seals with an independent server-side implementation against an
`httptest` TLS server.

## Plain LVM and scheduling

`kura-lvm-nvme` selects `encryption: none`, which requires the VG and refuses
LUKS headers; the encrypted class retains its existing immutable parameters.
The driver advertises `tuist.dev/kura-disk` as VG size minus non-Kura LVs,
including the 128 GiB `data` LV. It advertises total reservable capacity, not
free extents: kube-scheduler subtracts pod reservations. The server additionally
accounts for retained volumes. The driver removes capacity on nodes without the
VG and does not silently use files for plain volumes. Prepare replacement LVM
capacity before regional enrollment. Retain CSI and LVM-aware admission across
rollback; disabling enrollment is not a safe rollback onto the smaller `/data`.

## Staged encrypted migration and racks

CreateVolume returns `backing: lvm` or `backing: file` for both fresh allocations
and idempotent retries. The controller uses this immutable PV context to migrate
old file claims even when their encrypted StorageClass is unchanged. Old PVs
without this evidence are conservatively rebuilt once after LVM enrollment.
Deploy the new driver before enrolling any region.

The rack plugin lives in `infra/helm/rack-nodes`, outside the waited main release,
with explicitly configured `kuraVolumesCSI.rackPools`. Its regression render
checks the shared host/key contract and disjoint pool ownership against the
rented plugin. `go test ./...` requires Helm for this check. LVM-enrolled regions
now encrypt by default; plain CSI remains available for diagnostics. Rack fresh
installation uses curtin LVM; old hosts need a planned migration/reinstall.

Keep the reusable [rollout probe](cmd/rollout-probe/AGENTS.md) under `cmd/`;
generated run output belongs outside the source tree.

## Key custody and admission

[Security runbook and tests](security/AGENTS.md) cover KMS wrapping, resumable
rewrap and recovery gates. The main chart owns three retained fail-closed
admission policies restricting the shared CSI identity to its token-bound node,
immutable PV/PVC ownership and its own disk-capacity field. PVC writes/events
are namespaced to `kura`. Cluster administrators and privileged host access
remain trusted. Never claim hosted KMS custody before the live migration gates
in `security/key-management.md` pass.
