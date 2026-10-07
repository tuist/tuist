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
It attaches the disk device with `hdiutil -readonly -nomount -noautofsck`, checks
the raw APFS partition with `fsck_apfs -n` without mounting its filesystem in the
host kernel, persists a verification guard, uploads the compressed image, then uses the same clear-epoch lock and HEAD CAS as Linux.
Only an accepted image becomes a local master. A failed upload retries without
reformatting or consuming another verification; a crash during verification
poisons the branch. Expired or cleared generations cannot publish later.

Mount duration remains unknown because host preparation excludes guest attachment.
Usage remains unknown while the guest owns the image; after clean teardown the
host records the guest's lease-bound, validated filesystem usage/capacity sampled
before the successful detach. These measurements do not authorize disk admission.
They are logical filesystem bytes, not unique physical allocation or billing
measurements. APFS shares
extents. Both backends use real free space and local master eviction. Admission
reserves only the remaining growth (capacity minus allocated blocks) of running
custom guests alongside built-in reservations on the same bounded filesystem.
Stopped guests reserve no extra growth while publication retries. A short shared
lock records admission before creation; downloads and image creation run outside
it. Live reservations are recovered from the durable journal after restart.

GitHub Actions, Buildkite and GitLab use the same installed client. macOS
supports native commands and GitLab's shell executor. GitHub container jobs and
Docker actions require Linux. A separately managed Docker VM does not inherit
the APFS mount; no macOS container-volume support is implied.

## Rollout and rollback

Managed canary and production enable custom volumes fleet-wide through
`runnersFleet.customCacheVolumes.enabled`. Workflows opt in per directory with
`tuist/cache-volume@v1`; no project or account allowlist is required. The chart's
self-hosted default remains disabled. Staging also stays disabled: its 40 GiB
cache quota cannot fit the built-in reservation plus the custom admission floor.
Enabling staging requires a separately planned capacity change; setting the flag
alone does not make that fleet capable of retaining custom volumes.

1. Deploy the platform migration and matching server code while macOS custom
   volumes remain disabled. Linux rows retain `platform=linux` and their existing
   identity. Keep both the seven-column legacy index and the platform-aware
   index so old pods can still allocate during rollout and an image rollback.
   The legacy index intentionally prevents identical cross-platform identities
   until enablement. After all server pods use the new conflict target and the
   rollback window closes, `20261007150000_enable_macos_cache_volumes.exs` drops
   `runner_cache_volumes_provider_identity` concurrently. The managed deployment's
   pre-upgrade migration hook runs this before switching the server/host gate on.
   Do not enable custom volumes with pre-platform server replicas still running.
   After enablement, downgrading to pre-platform code requires disabling new
   allocations, draining jobs, reclaiming macOS data/metadata, and running the
   guarded rollback to recreate the legacy index. The rollback refuses any
   remaining macOS rows.
2. Release the runner image with the common client and successful-job detach
   hook. Older images keep built-in caches; they cannot mount custom volumes.
   Update the client before the host verification change: publication now requires
   its lease-bound `.usage` report. Older custom-volume clients without that report
   can still read caches, but their branches are discarded after teardown.
3. Release the CAPI provider/tart-kubelet with the APFS backend and ensure the
   deployment resolves a runner-image release containing the macOS volume client
   and clean-detach hook, rather than the older guest image already on the fleet.
4. Deploy the managed canary then production overlays. Helm renders the server gate and shared agent
   ServiceAccount, and passes the endpoint/namespace/SA through the existing host
   bootstrap configuration. Its normal drift mechanism rolls the host binary
   and launchd flags. Only newly booted VMs receive the custom share.
5. Exercise cold/warm native jobs for all three providers, private PR/MR reads,
   failures, cancellation, concurrent writers, clear during a running job,
   host restart, unavailable object storage and quota pressure. Verify the
   built-in caches still warm existing jobs without workflow edits.
6. Keep self-hosted and additional environment enablement explicit. Unavailable
   capacity falls back to a job-local directory, so successful jobs alone are not
   proof of persistence: require a real APFS mount on the seed run and a cache hit
   with retained contents after publication on the verification run.

For rollback, disable new server allocations first and let active jobs and
agent journals drain before removing host enablement or rolling back binaries.
Do not delete the custom root or downgrade the schema while copies remain.
Disabling allocation leaves existing report/image cleanup endpoints available.
Old built-in volume code and images remain compatible throughout.

## Validation record

For deployed GitHub smoke validation, dispatch `macos-cache-volumes-smoke.yml`
on `main` with a fresh key and phase `seed`. After successful teardown and host
publication, dispatch `verify` with the same key: it requires a warm APFS volume
with the original file contents, symlink and xattr. Run `fail` and then `verify`
to prove failed-job writes are discarded. Clear that dedicated volume and run
`seed` again to check invalidation. Do not use a key belonging to a build cache.

The PR description records executed tests and outstanding staging checks.
Local real APFS coverage creates a 20 GB image, attaches cold and warm copies,
verifies private-write isolation, and preserves symlinks and xattrs. Mocked
storage tests cover retry, rejected publication and interrupted verification;
shared journal tests cover restart and writer fencing. Provider authorization,
clear epochs and expiry remain database-tested server responsibilities.

Interrupted host inspection devices are found by backing-image path and detached
before poisoned-branch cleanup. Cleanup also handles mounts left by older agents.
An unavailable agent retries initialization. Pods receive their mailbox whenever
the cache filesystem is mounted, including before the agent becomes ready. Each
attach attempt has a unique request name and cleans up its response. Clean detach
retries five times for transient busy files; force-detach never permits publication.
A failed detach logs a warning explaining that affected volumes will not publish.

The host scans requests once per second with independent per-pod workers (at most
eight, without a queue), and publishes/reclaims on a separate worker every
30 seconds. Slow verification, uploads and another guest's restore cannot block
an unrelated mailbox. Shutdown joins all workers before closing the store. It
reuses its short-lived token in memory until refresh is due. Tokens are never
written to the mailbox or journal.

Acquisition follows Linux's 25-second host budget and 30-second client budget.
Cancellation reaches APFS creation/cloning, remote restore and admission waits;
an expired response cannot trigger a guest mount. Like Linux, macOS can prefetch
one immutable master after a restore timeout, with a two-minute budget, no queue,
and a separate disk reservation for the archive and expanded image. Agent shutdown
cancels and joins that worker. macOS custom volumes emit the shared
operation/source/result metrics through tart-kubelet's existing metrics endpoint.
Custom admission counts outstanding built-in convergence downloads, and built-in
convergence reserves space for live custom images before starting a download.

## Built-in volume measurements

The existing Xcode/Tuist cache appears in the same volume inventory as custom
volumes after its first measured job. The guest samples the mounted APFS
filesystem at attach and teardown, including capacity, used bytes, mount duration
and warm/cold source. After finalization removes the private branch, tart-kubelet
queues the report durably and retries using its host-scoped identity. The server
resolves the account and repository through the actual executed job's session.

Roll out the additive server migration and endpoint before the host binary and
runner image. Older hosts/images continue running but cannot populate missing
measurements retroactively. New hosts retain reports while the endpoint is
unavailable. Rolling back the host/image stops new observations without changing
built-in publication; leave the additive schema in place when rolling back the
server.

Storage totals track the measured canonical saved image and observed job copies,
not a census of physical host/S3 replicas. Superseding a canonical measurement is
recorded separately from physical deletion. Built-in volumes do not participate
in custom-volume expiry or clear until their backend supports the same fencing
contract; the UI does not expose an unsafe clear action.
