# Custom macOS cache volumes

## Compatibility decision

Keep the automatic built-in volume and add separate opt-in custom volumes.
The built-in image contains Tuist's `tuist/` cache tree and the Xcode
`CompilationCache.noindex` store. Dispatch exports the Tuist cache home and CAS
configuration, assigns their shared byte budget, prunes CAS, and compares a
specialized inventory before publishing. Workflows already rely on that wiring,
including plain xcodebuild jobs that never invoke Tuist.

Changing those images to opt-in would silently turn existing workflows cold.
Using the built-in inventory for arbitrary directories would fail to notice
changes outside its known trees. Neither is compatible. Existing `tuist-cache`
and `repo-*` HEADs, objects, local masters, capacities and retention remain in
place. No migration deletes or renames them. Custom-volume clear affects only
that custom identity; it does not clear the built-in Tuist or Xcode cache.

New identities include platform, preventing APFS and ext4 image reuse even when
repository, key, architecture and UID happen to match. Existing Linux UUIDs and
scope hashes remain unchanged. Public HTTP/MCP/CLI responses already have a
string platform field; the dashboard now renders each volume's actual platform.

## Shared lifecycle and macOS transport

`infra/runner-cache` contains the existing Linux journal, compressed image
checksums, HTTP transfers, HEAD publication, and idle master reclamation. Linux
continues using its ext4 backend. macOS adds APFS images to that same lifecycle,
with a 20 decimal GB capacity and the existing server's seven-day idle expiry.

The host creates a private branch inode and exposes a hard link through a
per-VM virtio-fs share. The guest mounts that image as APFS, preserving symlinks
and xattrs, and the common client symlinks the requested directories into it.
Each job has a distinct branch. Host masters and infrastructure credentials
never enter the share. The mailbox carries key and execution UID only; the host
supplies pod, node and architecture, and the server resolves actual execution,
provider instance, immutable repository/pipeline scope and publication policy.

Successful job teardown cleanly detaches each image. Failure, cancellation,
forced detach and abrupt shutdown produce no eligible marker. The host waits
for API Pod absence **and** a stopped Tart process before inspecting the image.
It verifies APFS read-only with diskutil, persists a verification guard, uploads
the compressed image, then uses the same clear-epoch lock and HEAD CAS as Linux.
Only an accepted image becomes a local master. A failed upload retries without
reformatting or consuming another verification; a crash during verification
poisons the branch. Expired or cleared generations cannot publish later.

Usage remains unknown while the guest owns the image; after clean teardown the
host records verified filesystem usage/capacity. These are logical filesystem
bytes, not unique physical allocation or billing measurements. APFS shares
extents. Both backends use real free space and local master eviction. Admission
reserves each live custom image alongside existing built-in reservations on the
same quota-bounded filesystem. Custom allocation is serialized with built-in
admission, including a required cold download; this favors a simple correct
capacity bound over simultaneous materialization on the two-guest hosts.

GitHub Actions, Buildkite and GitLab use the same installed client. macOS
supports native commands and GitLab's shell executor. GitHub container jobs and
Docker actions require Linux. A separately managed Docker VM does not inherit
the APFS mount; no macOS container-volume support is implied.

## Rollout and rollback

1. Deploy the platform migration and matching server code while macOS custom
   volumes remain disabled. Linux rows retain `platform=linux` and their existing
   identity. The migration replaces the allocation uniqueness index; old server
   processes cannot allocate against the new index and requests fall back cold
   until those processes are replaced. Existing report/image operations continue.
   For an application downgrade, disable allocations and drain jobs, reclaim all
   macOS data and remove its metadata, then run the guarded migration rollback
   to restore the old index before starting old code. The rollback refuses to
   collapse any remaining macOS rows into Linux identities.
2. Release the runner image with the common client and successful-job detach
   hook. Older images keep built-in caches; they cannot mount custom volumes.
3. Release the CAPI provider/tart-kubelet with the APFS backend. Keep
   `runnersFleet.customCacheVolumes.enabled=false` until staging validation.
4. Enable that value in staging. Helm renders the server gate and shared agent
   ServiceAccount, and passes the endpoint/namespace/SA through the existing host
   bootstrap configuration. Its normal drift mechanism rolls the host binary
   and launchd flags. Only newly booted VMs receive the custom share.
5. Exercise cold/warm native jobs for all three providers, private PR/MR reads,
   failures, cancellation, concurrent writers, clear during a running job,
   host restart, unavailable object storage and quota pressure. Verify the
   built-in caches still warm existing jobs without workflow edits.
6. Enable other environments only after these checks. This implementation does
   not change managed production values.

For rollback, disable new server allocations first and let active jobs and
agent journals drain before removing host enablement or rolling back binaries.
Do not delete the custom root or downgrade the schema while copies remain.
Disabling allocation leaves existing report/image cleanup endpoints available.
Old built-in volume code and images remain compatible throughout.

## Validation record

The PR description records executed tests and outstanding staging checks.
Local real APFS coverage creates a 20 GB image, attaches cold and warm copies,
verifies private-write isolation, and preserves symlinks and xattrs. Mocked
storage tests cover retry, rejected publication and interrupted verification;
shared journal tests cover restart and writer fencing. Provider authorization,
clear epochs and expiry remain database-tested server responsibilities.

Interrupted host inspection mounts use a deterministic host-only path; poisoned
branch cleanup detaches any retained read-only mount before deleting its image.
An unavailable agent retries initialization and leaves ordinary jobs cold instead
of stopping tart-kubelet.
