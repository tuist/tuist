# Shared runner cache lifecycle

Linux and macOS custom volumes share the durable Store journal, HTTPTransfer,
immutable object uploads, HEAD compare-and-swap, bounded checksummed archives,
and seven-day master eviction. The server owns scope, trust and clear epochs.

- Linux LocalImages uses ext4 and reflinks. Preserve syncfs/error verification,
  durable checking guards, CRI plus API writer fences and no-follow cleanup.
- APFSImages uses private APFS sparse images. While a VM runs, its branch image
  has one name, `cache.sparseimage` in its own virtio-fs share (`expose`), and
  `<image>.shared` records its device and inode; `Seal` links it back to its
  private name only after the VM stopped and the share still holds that inode
  (`claim`), else `ErrReplaced`. Never keep a second name while the VM runs: its
  sandboxed virtio-fs server opens files by inode, which macOS checks against
  the name last looked up, so any host lookup of a private name denies the
  guest's next open (`permission denied`). Find a running branch through
  `APFSBranchFile`/`APFSHasBranch`. Masters stay private.
  Require clean guest detach, API absence AND stopped Tart VM before verifying
  and publishing. Never mount guest-written APFS on the host; use an unmounted read-only device
  and userspace fsck. Validate lease-bound guest usage separately from admission.
- Only accepted publication becomes a master. Failed upload retries and restart
  recovery retain the same journal identity. Clear conflicts discard the branch.
- Default custom capacity is 20 decimal GB; the server may choose 1 to 100 GB
  per volume, up to the host maximum.
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
  Kubelet unmounts those SubPath mounts only on a backoff retry after the
  agent's unmount, so the loop device often outlives it by tens of seconds:
  `detach` then returns `ErrReleasePending`. A branch that passed its checks
  becomes `.detaching` (not poisoned) and is verified once the device is gone;
  a branch being deleted keeps `Slot.Discard` so later passes delete it instead
  of sealing it again. Neither fails maintenance.
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
- `ExecutionWaits` gives each runner Pod one 25-second wait (`ExecutionWait`) for
  GitHub to report its job, shared by its checkout and every volume; both the
  Linux and macOS agents use it.
- Every agent request to the server (`authorize`, `checkout`, `report`, `image`)
  goes through `DoServer`: up to four attempts on a connection failure or a
  502/503/504, jittered backoff from 250 ms to 2 s, never past the request
  context (an attach keeps its 25 s budget). The server keeps them idempotent:
  an allocation returns the pod's existing use, a report restates a use, and an
  `image` request reads a HEAD, signs another URL or returns the generation the
  use already published. A new endpoint must stay idempotent before it uses
  `DoServer`. Never retry the object-storage PUT this way; the Store retries
  publication. Retries log `cache server request retried` and `recovered`.
  Agents build their server clients with `NewServerClient`, which closes a
  connection idle for `ServerIdleTimeout` (10 s), below Bandit's 15 s keep-alive
  timeout, so a request never goes out on a connection the server is closing.
- Emit bounded operation/source/result metrics without keys, paths or signed URLs.
  Linux exposes them on port 9091; macOS uses tart-kubelet's metrics registry.
  The Linux agent's phase log line carries a failure's `error` text, URLs replaced.
- Every `Observation` carries a `Subject` (`Observer.For(slot)`/`With`) that
  agents append to their phase log line, never to a metric label: `scope` (64
  hex; node labels use its first 48), `use`, `kind` (`custom`, `managed`,
  `checkout`, or absent when the host cannot tell), `key` (managed only),
  `volume_key` (checkout digest), `generation`, `mounted_generation`,
  `checkout_generation` and `pod`. Fields with no value are left out. Never add
  account or repository names or a customer-chosen key: `Identity.ManagedKey`
  is set by the agent from the request through `ManagedKey`, which keeps only
  Tuist's managed keys.
- Every master removal logs `cache master evicted` (`LocalImages.Log`) or
  `checkout master evicted` (`Checkouts.Log`) with `scope`, `generation` or
  `checkout_generation`, `bytes` (allocated; blocks shared with clones stay in
  use) and `reason`. Admission (`reserveBytes`) logs the `evictionOrder` reason
  (`superseded`, `speculative`, `idle`, `in_use`) under pressure or `expired`
  (unused 7 days) without, with `needed_bytes`, `free_bytes` and the `for_*`
  subject it ran for (`WithSubject`). Maintenance logs `expired`, `superseded`
  (with `head_generation`), `head_conflict` (lineage cleared or expired) or
  `no_metadata`. Checkouts log `expired`, `idle` (LRU under pressure) or
  `cleared` (the checkout volume's scope changed). The `evict` observation also
  names the master's `scope` and `generation`.
- The Linux agent prefetches the assigned master after a warm acquisition that
  found no local copy of it (mounted older, started empty, or timed out; checked
  with `HasMaster`), one at a time with no queue and the same disk reserve. Like
  refreshes, a prefetch has no deadline: its download ends on a stall or after
  its attempts. macOS queues
  prefetches (see tart-kubelet). Never create a private branch, publish, or extend
  the foreground budget from prefetch.
- `Attach` never downloads, on either host (`LocalImages.cloneLocal`). It clones
  the base master, else the newest older master of the same scope (recorded
  durably in `<image>.base` before the branch exists, and in
  `Slot.MountedGeneration`), else formats an empty image marked `<image>.cold`.
  A cold branch reports `Warm=false` and `Seal` returns `ErrWithheld`, which the
  Store treats like a poisoned branch: deleted, never published. Only the Store's
  `publish` action (the server's size rule, see `CacheVolumes`) sets
  `Slot.PublishCold` for that one seal; the full, unchanged, identical and
  generation checks still apply. Linux checks `.cold` before its unchanged and
  full checks.
- APFS `Seal` also withholds a branch whose guest `.usage` says `changed: false`
  (`ErrUnchanged`) or that is at least 99% full (`ErrFull`, the server's
  out-of-space rule). A missing `changed` field means changed. `Measure` reads a
  detached branch's `.usage` before sealing so a withheld branch still reports its size.
- APFS `Seal` poisons a branch whose share no longer exposes the branch image
  itself (`ErrReplaced`, result `replaced`): the guest's writes went elsewhere.
  `publish` withholds a branch whose content digest equals its base's
  (`ErrIdentical`, result `identical`): the guest reported changes that never
  reached the host, and publishing would only advance the generation.
- APFS `Verify` returns the bytes the image's container holds, which equals
  the guest's `.usage` `used_bytes` (statfs before detach) when every write
  arrived. `Seal` and `keepUnchanged` poison a branch holding more than
  max(32 MiB, 1%) less (`ErrIncomplete`, result `incomplete`). This also
  catches a cold branch, which has no base digest for `ErrIdentical`. Evidence:
  on 2026-10-21 a guest wrote 100 MB into a new volume and measured 149,708,800
  bytes; the published image held every data band (114,298,880 allocated bytes)
  but mounted as the formatted volume (49,688,576 bytes), and the next job
  restored it empty. The guest halts gracefully after detaching, so the writes
  were lost, not left in its cache: a stronger guest flush would not help.
- `LocalImages` (Linux) decides the same on the host, while the volume is still
  mounted and before verification: `ErrFull` from `MeasureFS`, `ErrUnchanged`
  when the top-level entries match `<image>.entries` and no entry's ctime is
  newer than the one it recorded. The first attach writes `.entries` after the
  marker; later attaches of the branch keep it. A missing baseline means changed;
  a `.verified` or `.checking` branch skips the check.
- An `ErrUnchanged` branch cloned from its own base (no `.base` or `.cold`) becomes
  that generation's local master when the host no longer holds it, after the
  same verification publication runs (`keepUnchanged`, `keep` observation).
  Admission may evict a master while a job runs, and an unchanged lineage never
  publishes, so otherwise only a download brings its copy back. Linux removes
  the `.verified` marker afterwards so a retried seal withholds it again.
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
  abandoned after two minutes without bytes (response headers included),
  `ObjectClient` (else `Client` with its timeout cleared) without a whole-transfer
  timeout: never bound a transfer by a whole-request deadline. A context that ends while
  bytes arrive returns `ErrDownloadIncomplete` and keeps the partial; a complete
  archive that does not restore is deleted. Callers resume only by passing the
  same path again.
- `HTTPTransfer.Publish` (`upload.go`) retries inside the call, so a retry never
  recompresses. An archive of at least two 128 MiB parts asks `upload` with
  `multipart`; the server starts a multipart upload (S3-compatible storage only)
  or answers with a single PUT link. Parts go eight at a time, links signed 16 at
  a time by `upload_parts` for each part's `Content-MD5` (hashed before the links
  are asked for); `complete` assembles them and answers once the object is
  readable, and `publish` fast-forwards. One connection to Tigris carries about
  55 to 110 MB/s from a rack host; 4, 8 and 16 parts carried 260, 417 and
  582 MB/s (4 GiB, b07, 2026-10-22). Tigris answers a completion before the
  object is readable (2 to over 30 s), so the server waits up to 20 s and
  otherwise answers 503. A smaller archive, or an older server, is one
  PUT carrying the server-signed SHA-256. A retried attempt resumes with the parts
  storage does not hold; asking for links again returns `ErrConflict` once the
  lineage advanced. Attempts that store nothing are bounded by four (one that
  stores parts restarts the count), back off 10 s times the count, and a request
  that sends nothing for two minutes is abandoned. Only transport errors, stalls
  and 5xx/429/408 are retried; once storage holds the archive only `publish` is.
  A call that gives up sends `abort`; the server also aborts every multipart
  upload once its links expired (`AbortVolumeMasterUploadWorker`). Each retry
  logs `cache upload retry` with `attempt`, `parts_stored`, `sent_bytes`,
  `elapsed_ms` and `error`. Transport errors keep the network's own text
  (`transport error: <cause>`) with URLs replaced, and a `RemoteError` carries
  the object store's `<Code>` when it sent one. A restore verifies the whole
  archive's SHA-256.
- `prefetch` and refreshes download into
  `staging/<scope>-<generation>-<content digest>.img` and take the scope lock only
  to install (`fetchMaster`), one download per staging name at a time;
  `maintainMaster` asks for the HEAD before taking it. Never hold a scope lock
  across a network call: APFS jobs clone under that lock. With `Replace` set, maintenance keeps a superseded master
  used in the last day while its successor is queued, instead of removing it.
- `PrefetchSpare` admits only into free space and never evicts or reclaims; use it
  for speculative downloads no job waits on. `HasMaster` reports a warm identity's master.
- Pressure eviction (`reserveBytes`, `evictionOrder`) removes, in order: generations a
  newer local master of their lineage supersedes; speculative masters (`<master>.spare`,
  written by a spare prefetch of a lineage with no used copy here, removed by the
  first clone); the rest least recently used first (mtime). Lineages
  `LocalImages.InUse` (each host passes `Store.InUse`) reports held or attaching go
  last: their clones share the masters' blocks, and an attaching job would lose its
  base and go cold. The order never changes what admission can free, only what goes
  first. Each removal is an `evict` observation whose source is the reason.
- `MasterNodeLabels(root)` advertises one `tuist.dev/cache-volume-<first 48 hex of
  scope>` label per lineage with an installed `*.img` master. tart-kubelet
  publishes it on the node heartbeat and the Linux agent merges it into its Node
  patch, removing labels of evicted lineages.
- Linux refreshes a superseded master used in the last day to the new HEAD in
  the background (one at a time, prefetch admission, no deadline) before removing it. A job
  attaching that lineage meanwhile clones the stale master. Maintenance and
  admission skip the scope a refresh is downloading. Only a
  master the refresh installed under the scope lock inherits the stale master's
  last use. macOS leaves `RefreshWithin` zero: refreshes use LocalImages admission,
  not APFS reservations.
  Maintenance validates every master even when one lineage cannot be reached.

- APFS admission records a reservation under the shared admission lock, then releases it
  before downloads or formatting. Reserve remaining growth only for running VMs;
  retain journal recovery and bounded, separately reserved prefetch work.
  An attach needs its expected size; restoration and prefetch also need
  the archive budget. Keep the backend check and host reservation consistent.
  After local-master eviction, the optional shared-filesystem reclamation hook
  may reclaim idle macOS checkout copies. Remeasure free space before admitting;
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
  populator passes `safe.directory=*` per command, and `gc.autoDetach=false`: a
  repack git detaches (every ingest adds a pack; past 50 one starts) keeps the
  image busy and no build can unmount it again. A Linux checkout slot is
  seeded through `LocalImages.Seed`, never formatted, and admitted only while
  free space covers the whole checkout image, since it holds the job's workspace.
  That check never evicts (`reserveSpare`); the usual reserve admission does.
- `Checkouts.InUse` (each host passes `Store.InUse`) keeps pressure eviction
  off masters a job holds or is attaching: their blocks are shared, so evicting
  them frees nothing and the attaching job loses its seed.
- A checkout master's tip only moves to a `DefaultBranchJob`'s commit. While the
  lineage has no HEAD (`BaseGeneration` 0), a `MayStartMaster` job's checkout may
  also start it: its own commit, or a two-parent merge naming that commit (a
  pull request's test merge, read with `cat-file commit` because a depth-1 fetch
  leaves its parents out). That master is published like a moved tip. Once a
  master exists, other exports only add objects.
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
- `KindDocker` (`docker.go`) is a repository's Docker data root. Overlay2 needs a
  filesystem native to the guest kernel, so the guest loop-mounts the branch
  image itself: `Attach` links the image into the pod's directory as
  `docker.img` (`exposeDocker`) and never runs losetup or mount; `detach` is a
  no-op. Never mount a Docker image on the host and never run a filesystem
  parser on it: a privileged guest writes it at the block level. `Seal`
  (`sealDocker`) requires the guest's `docker.json` (`ReadDockerReport`, read
  without following links, bounded and validated) to say it unmounted cleanly,
  the pod's link to still be the branch (`sameFile`), and the superblock's fixed
  fields to show no journal to recover and no errors (`ext4Clean`); a report
  saying unchanged is `ErrUnchanged` (it can only withhold), and a branch whose
  blocks exceed `DockerPublishBytes` is `ErrFull`. Measurements are the image's
  allocated bytes and logical size. `Delete` and `Keep` remove the pod directory
  (guest-written files only) and the image. A Docker identity always has
  `DockerVolumeBytes`, above the host maximum for other volumes
  (`kindMaxVolumeBytes`, `HTTPTransfer.maxBytes`), and admission expects its saved
  bytes plus `DockerGrowthBytes`. Empty images are formatted with
  `dockerFormatArgs` so the guest's kernel has no background zeroing to do.
- A Docker branch whose lineage another job saved since it was mounted is merged,
  not lost: `ExposeDockerHead` clones that head (downloading it when this host
  lacks it) next to the branch as `.merge`, records it in `.merge.json` and links
  it into the pod's directory as `head.img`; the guest loads the images only one
  side keeps into the other. A report naming `merged_generation` and
  `merged_into` (`sealDockerMerge`) must name the head this host offered; a
  merge into `head` renames the clone over the branch after the same inode and
  superblock checks, then the use is rebased on the server (`Rebaser`, the
  `rebase` image operation; a conflict is `ErrSuperseded`) and published as any
  branch. Without a merge a branch whose HEAD moved stays `ErrSuperseded`.
