# Linux local cache images

Local reflink branches of sparse ext4 images, with the same object storage and
HEAD publication protocol as the macOS cache. See [runbook](../../cache-volumes.md).

- Never expose host images, masters, journals or signed URLs to workflows.
  Guests see only `pods/<pod UID>` through kubelet SubPathExpr.
- Bind requests to source IP, node and UID; resolve scope/trust on the server.
- Journal before creation; format only an unexposed temporary image and atomically
  rename it before mount. Retries never format an existing branch.
- Seal/delete require API pod absence AND host CRI proof that the pod UID has no
  ready sandbox or non-exited container. Runtime errors fail closed. Waiting for
  kubelet-directory absence before unmounting deadlocks on propagated SubPath
  child mounts; directory cleanup still waits for kubelet after unmounting.
  A webhook, terminal phase, timeout or failed API request is not a writer fence.
- Publish synchronously: detach, compress, preflight, upload, fast-forward, then
  install the accepted master. Failed/rejected uploads never become masters.
- Local masters use generation/digest filenames; checksummed downloads are
  restored sparsely, with bounds on compressed and expanded input.
- Require reflinks with no byte-copy fallback. Use actual filesystem free space
  for admission/LRU; shared extents make summed file sizes misleading.
- Reconcile local master metadata against the shared HEAD, and evict stale or
  idle masters. An acknowledged sealed journal allows private image reclamation.
- Use no-follow mount operations and os.Root for job-controlled tree cleanup.
- Keep the fleet disabled until deployed Kata and provider smoke validation.
- Run `go test -race ./internal/cachevolumes ./cmd/cache-volumes` and
  `scripts/test-cache-filesystem.sh` (real Linux loop mounts/reflinks in Docker).
- New images default to 20 decimal GB. Configurable per-volume capacity and
  macOS custom volumes remain follow-ups.
