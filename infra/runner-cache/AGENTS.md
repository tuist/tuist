# Shared runner cache lifecycle

Linux and macOS custom volumes share the durable Store journal, HTTPTransfer,
immutable object uploads, HEAD compare-and-swap, bounded checksummed archives,
and seven-day master eviction. The server owns scope, trust and clear epochs.

- Linux LocalImages uses ext4 and reflinks. Preserve syncfs/error verification,
  durable checking guards, CRI plus API writer fences and no-follow cleanup.
- APFSImages uses private APFS sparse images. Guests mount an image hard link
  through their own virtio-fs share. Host image paths and masters stay private.
  Require clean guest detach, API absence AND stopped Tart VM before verifying
  and publishing. Never mount guest-written APFS on the host; use an unmounted read-only device
  and userspace fsck. Validate lease-bound guest usage separately from admission.
- Only accepted publication becomes a master. Failed upload retries and restart
  recovery retain the same journal identity. Clear conflicts discard the branch.
- Default custom capacity is 20 decimal GB; the server may choose 1 to 100 GB
  per volume, up to the host maximum. Built-in Tuist/CAS macOS caches keep
  their existing separate identities, capacity and retention policy.
- Unknown measurements remain unknown; never report unavailable usage as zero.
- Run `go test -race ./...` here, the Linux agent/client suites, and macOS podagent
  suites. Real APFS and real ext4 tests complement mocked command tests.
- Do not move provider trust or publication decisions into workflow wrappers.

- Journal before creation; format only an unexposed temporary image and rename
  it durably before exposure. Retrying an existing branch never reformats it.
- Linux transport binds requests to source IP, node and UID. Its writer fence
  requires no ready CRI sandbox or non-exited container. Kubelet directory
  absence is only a cleanup fence: waiting for it before unmounting deadlocks
  on propagated SubPath mounts. Terminal phase and timeouts are not fences.
- Publish synchronously after verification: compress, preflight, upload,
  fast-forward, then install the accepted master. Bound compressed and expanded
  downloads and verify checksums. Require reflinks without byte-copy fallback.
- Archives store only non-zero data extents (`SEEK_DATA`/`SEEK_HOLE`) in zstd so
  save and restore cost scales with data, not the logical image size. Restore
  must keep accepting legacy full-image gzip masters until they age out.
- Reconcile generation/digest master sidecars against HEAD and evict stale or
  idle masters. Preserve os.Root cleanup and no-follow Linux mount operations.

- Acquisition uses the request context with a 25-second host budget and a
  30-second client timeout. Propagate cancellation through downloads, expansion,
  commands and shared-master/admission waits. Incomplete restores cannot publish;
  reclaim their journals only after the existing writer fences pass.
- Emit bounded operation/source/result metrics without keys, paths or signed URLs.
  Linux exposes them on port 9091; macOS uses tart-kubelet's metrics registry.
- Linux may prefetch one immutable master after a timed-out warm acquisition,
  bounded to two minutes with no queue and the same disk reserve. macOS queues
  prefetches (see tart-kubelet). Never create a private branch, publish, or extend
  the foreground budget from prefetch.
- APFS `Attach` never downloads. It clones the base master, else the newest older
  master of the same scope (recorded in `<image>.base` and
  `Slot.MountedGeneration`), else formats an empty image marked `<image>.cold`.
  A cold branch reports `Warm=false` and `Seal` returns `ErrWithheld`, which the
  Store treats like a poisoned branch: deleted, never published.
- APFS `Seal` also withholds a branch whose guest `.usage` says `changed: false`
  (`ErrUnchanged`) or that is at least 99% full (`ErrFull`, the server's
  out-of-space rule). A missing `changed` field means changed. `Measure` reads a
  detached branch's `.usage` before sealing so a withheld branch still reports its size.
- APFS `Seal` poisons a branch whose share no longer exposes the branch image
  itself (`ErrReplaced`, result `replaced`): the guest's writes went elsewhere.
  `publish` withholds a branch whose content digest equals its base's
  (`ErrIdentical`, result `identical`): the guest reported changes that never
  reached the host, and publishing would only advance the generation.
- `LocalImages` (Linux) decides the same on the host, while the volume is still
  mounted and before verification: `ErrFull` from `MeasureFS`, `ErrUnchanged`
  when the top-level entries match `<image>.entries` and no entry's ctime is
  newer than the one it recorded. The first attach writes `.entries` after the
  marker; later attaches of the branch keep it. A missing baseline means changed;
  a `.verified` or `.checking` branch skips the check.
- `Identity.VolumeBytes` is the capacity the server chose for this use; zero
  means the host default (`SizeGB`). `HeadSizeBytes` is the saved head's measured
  used bytes, zero when unknown. `Store.MaxVolumeBytes` is the host maximum each
  agent configures (`DefaultMaxVolumeBytes`, 32 GB, when unset); `Acquire`
  rejects larger volumes, journal reads do not. Images are created at
  `volumeBytes(slot)`; never size an image from `SizeGB` directly. Attach
  admission uses `Identity.ExpectedBytes`: the head's used bytes plus half again
  (at least `GrowthBytes`), else `UnmeasuredVolumeBytes`, capped at the capacity.
  A job can write past it; the reservation is an estimate, not a quota.
  `Relieve` evicts idle masters (never an `inUse` scope) while free space is
  below a minimum, without reclaiming other caches. `APFSImages.MarkPressure`
  makes `Seal` withhold a branch (`ErrPressure`) that was written near the hard
  limit, where a failed host write may have left it silently incomplete. Guest usage
  validation and transfer `MaxBytes` use the host maximum, so grown masters pass.
- Guests may request a size: `RequestedSize` decodes any JSON value and keeps
  only whole decimal GB from 1 to 100 GB. Agents forward it as
  `requested_volume_bytes` with `max_volume_bytes`; a 507 from `/authorize` is
  `ErrCapacity`, never retried.
- A warm copy smaller than `Identity.VolumeBytes` grows before exposure and
  never shrinks; failure leaves it warm at its saved size. Linux truncates the
  clone up before the durable rename and runs `resize2fs` on the loop device
  after mounting when the ext4 superblock is smaller than the image. APFS calls
  the injected `Grow` on the private copy, which only extends the image
  (`-imageonly`); the guest grows the container.
- Linux attach admission is `MinFreeBytes` plus whatever the expected size
  exceeds `SizeGB` by. APFS prefetch needs `Identity.RestoreBytes`: twice the head's used
  bytes, else twice the capacity.
- `HTTPTransfer.Download` keeps the archive at `<path>.part` and resumes it with
  `Range` requests: a fresh link per attempt, at most five attempts, an attempt
  abandoned after two minutes without bytes, `DownloadClient` without a whole-
  transfer timeout. A context that ends while bytes arrive returns
  `ErrDownloadIncomplete` and keeps the partial; a complete archive that does not
  restore is deleted. Callers resume only by passing the same path again.
- `prefetch` downloads into `staging/<scope>-<generation>-<content digest>.img`
  and takes the scope lock only to install;
  `maintainMaster` asks for the HEAD before taking it. Never hold a scope lock
  across a network call: APFS jobs clone under that lock. With `Replace` set, maintenance keeps a superseded master
  used in the last day while its successor is queued, instead of removing it.
- `PrefetchSpare` admits only into free space and never evicts or reclaims; use it
  for speculative downloads no job waits on. `HasMaster` reports a warm identity's master.
- `MasterNodeLabels(root)` advertises one `tuist.dev/cache-volume-<first 48 hex of
  scope>` label per lineage with an installed `*.img` master. tart-kubelet
  publishes it on the node heartbeat and the Linux agent merges it into its Node
  patch, removing labels of evicted lineages.
- Linux refreshes a superseded master used in the last day to the new HEAD in
  the background (one at a time, prefetch admission) before removing it.
  Maintenance and admission skip the scope a refresh download holds. Only a
  master the refresh installed under the scope lock inherits the stale master's
  last use. macOS leaves `RefreshWithin` zero: refreshes use LocalImages admission,
  not APFS reservations.
  Maintenance validates every master even when one lineage cannot be reached.

- APFS admission records a reservation under the built-in lock, then releases it
  before downloads or formatting. Reserve remaining growth only for running VMs;
  retain journal recovery and bounded, separately reserved prefetch work.
  An attach needs its expected size; restoration and prefetch also need
  the archive budget. Keep the backend check and host reservation consistent.
  After local-master eviction, the optional shared-filesystem reclamation hook
  may reclaim built-in macOS masters. Remeasure free space before admitting;
  successful deletion alone does not prove that CoW blocks were freed. Linux
  has no shared reclaimer and retains its existing admission behavior.
- Per-pod cleanup errors must not prevent cleanup of other fenced pods.
- Pod cleanup checks external writer fences outside the global allocation lock,
  then rechecks the durable lease under that lock before removing a mailbox.

- `Identity.Kind` is set by the host agent, never decoded from a guest or
  trusted from a custom allocation. `checkout` identities carry their volume's
  clear `Generation`, have no HEAD, can never publish, and their branches are
  seeded from a host-built master; attach fails rather than format an empty image.
  The host publishes and restores checkout masters itself, with `CompressImage`
  and the same `HTTPTransfer`; a checkout branch never goes through `Seal`.
- A restore downloads into `restore-<generation>-<content digest>` beside the
  master, because the transfer resumes a partial it finds at the same path: a
  fixed name let a restart splice another HEAD's archive into this one. Other
  HEADs' partials are removed before a restore, and `Maintain` drops downloads
  nobody wrote for an hour.
- `Checkouts` (`checkout.go`) is the one populator for both hosts: it builds,
  ingests, publishes, restores and evicts checkout masters, and the host only
  wires it to its admission (`Room`), transfer and tools. `CheckoutImages` is the
  only platform part. `APFSCheckoutImages` (macOS) keeps the tree at the image
  root and leaves ownership to the guest's `-owners off` attach.
  `Ext4CheckoutImages` (Linux) formats sparse ext4 with inode tables and journal
  zeroed at mkfs (free on a sparse file, and no clone's mount starts the
  kernel's background zeroing), clones with `cp --reflink=always`, loop-mounts
  builds in the agent, keeps the tree in `checkout/` beside the volume's own
  files, and chowns it to the job's UID. git runs as root on that tree, so the
  populator passes `safe.directory=*` per command. A Linux checkout slot is
  seeded through `LocalImages.Seed`, never formatted, and admitted only while
  free space covers the whole checkout image, since it holds the job's workspace.
  That check never evicts (`reserveSpare`); the usual reserve admission does.
- `Checkouts.InUse` (each host passes `Store.InUse`) keeps pressure eviction
  off masters a job holds or is attaching: their blocks are shared, so evicting
  them frees nothing and the attaching job loses its seed.
- `ReceiveCheckoutExport` unpacks a streamed export (Linux has no writable host
  share): regular files named `head`, `shallow`, `pack` or `lfs/<oid>` only,
  within the export bounds, written through `os.Root`, else the whole stream is
  refused. Sparse entries are refused and no write may exceed what the stream
  carried, so holes cannot expand into real bytes. Its `admit` hook asks for room
  per entry; the Linux agent admits above the job reserve and caps exports held
  on the host. `openCheckoutExport` validates it again before a build.
- Run the real-tools checkout test with `TUIST_CHECKOUT_E2E=1 go test -run
  CheckoutMasterEndToEnd .`; on Linux it runs as root with
  `TUIST_CHECKOUT_E2E_ROOT` on a reflink filesystem (`scripts/test-cache-filesystem.sh`
  in runners-controller provides one).
