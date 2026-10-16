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
- Default custom capacity is 20 decimal GB. Built-in Tuist/CAS macOS caches keep
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
- Reconcile generation/digest master sidecars against HEAD and evict stale or
  idle masters. Preserve os.Root cleanup and no-follow Linux mount operations.

- Acquisition uses the request context with a 25-second host budget and a
  30-second client timeout. Propagate cancellation through downloads, expansion,
  commands and shared-master/admission waits. Incomplete restores cannot publish;
  reclaim their journals only after the existing writer fences pass.
- Emit bounded operation/source/result metrics without keys, paths or signed URLs.
  Linux exposes them on port 9091; macOS uses tart-kubelet's metrics registry.
- Linux and macOS may prefetch one immutable master after a timed-out warm acquisition,
  bounded to two minutes with no queue and the same disk reserve. Never create
  a private branch, publish, or extend the foreground budget from prefetch.

- APFS admission records a reservation under the built-in lock, then releases it
  before downloads or formatting. Reserve remaining growth only for running VMs;
  retain journal recovery and bounded, separately reserved prefetch work.
  Cold creation needs one image's capacity; restoration and prefetch also need
  the archive budget. Keep the backend check and host reservation consistent.
  After local-master eviction, the optional shared-filesystem reclamation hook
  may reclaim built-in macOS masters. Remeasure free space before admitting;
  successful deletion alone does not prove that CoW blocks were freed. Linux
  has no shared reclaimer and retains its existing admission behavior.
- Per-pod cleanup errors must not prevent cleanup of other fenced pods.
- Pod cleanup checks external writer fences outside the global allocation lock,
  then rechecks the durable lease under that lock before removing a mailbox.
