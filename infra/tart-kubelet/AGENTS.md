# macOS runner runtime

`tart-kubelet` maps one Kubernetes Pod to one Tart VM. The host is trusted;
workflow code runs in the guest. Never expose host credentials or masters.

- Node liveness comes from the `kube-node-lease` Lease that
  `internal/nodeagent/lease.go` renews every 10s on its own client, with a
  bounded timeout. A renewal that fails without an API response closes every
  API connection (shared `connrotation` dialer) so the next one redials. Keep
  slow work (guest probes, label scans) in the Node status refresh, never in the
  lease path.
- Built-in cache behavior remains in `internal/podagent/volume*.go` and the
  runner-image dispatch script. Preserve existing Tuist/CAS paths and identities.
- Custom volumes use `internal/podagent/custom_volumes*.go` and the shared
  [`runner-cache`](../runner-cache/AGENTS.md) journal, archive and publication code.
  Enable through `runnersFleet.customCacheVolumes.enabled` after validation.
- Requests travel through a per-Pod UID virtio-fs mailbox. Read bounded regular
  files through os.Root; derive node, pod and platform from trusted host state.
- Publication requires API pod absence, stopped Tart VM, guest clean-detach
  proof, userspace APFS verification on an unmounted device and server publication eligibility. A webhook
  or terminal pod phase alone never fences writers.
- Built-in and custom admission share the existing quota-bounded APFS filesystem
  and account for each other's private-image capacity. Storage failure goes cold.
- Run `go test -race ./internal/podagent` and shared lifecycle tests. Real APFS
  checks require macOS/hdiutil; Linux CI covers the injected lifecycle tests.
- Migration, rollout and validation: [custom-cache-volumes.md](custom-cache-volumes.md).

- Built-in volume telemetry is sampled in the guest at attach and before detach,
  then attributed and queued by the host after finalization. Reports use the
  existing per-machine host token and a private fsynced queue under the cache root.
  Preserve execution binding, bounded guest-file reads, retry idempotency, and the
  separation between a superseded canonical measurement and physical deletion.

- Custom admission locks cover reservation only, never remote downloads or image
  creation. Count remaining growth for running VMs and recover it from journals.
  Background master prefetch is single-slot, bounded, reserved and joined at stop.
- Expose mailboxes while the filesystem is mounted, independently of worker
  readiness. Create pod directories before owner records and serialize owner GC.
- Publication/reclamation runs independently of bounded per-pod mailbox workers.
  Join workers before closing the store, preserve in-flight admission reservations
  during recovery scans, and never hold the global store lock across writer-fence
  API calls. Slow publication or restoration must not starve another guest.
