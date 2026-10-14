# kura-volumes-csi

CSI driver `kura-volumes.tuist.dev` behind the `kura-encrypted-nvme`
StorageClass. Every Kura data PVC gets its own LUKS2 container, backed by a
preallocated file on the node's XFS `/data` partition. The passphrase lives
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
  - `<id>.img`: backing file, 0600, fully reserved with `fallocate`; capacity
    is `required_bytes` rounded up to 1 MiB. CreateVolume keeps
    `--reserve-bytes` (default 20 GiB) free on the filesystem.
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
  pods.
- LUKS2: `aes-xts-plain64`, 512-bit key, PBKDF2 with 1000 iterations (the
  passphrase is already a uniformly random 32 bytes).

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
mapping is still active. Otherwise it runs `cryptsetup erase`, zeroes the
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
