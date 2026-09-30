# macOS runner runtime

`tart-kubelet` maps one Kubernetes Pod to one Tart VM. The host is trusted;
workflow code runs in the guest. Never expose host credentials or masters.

- Built-in cache behavior remains in `internal/podagent/volume*.go` and the
  runner-image dispatch script. Preserve existing Tuist/CAS paths and identities.
- Custom volumes use `internal/podagent/custom_volumes*.go` and the shared
  [`runner-cache`](../runner-cache/AGENTS.md) journal, archive and publication code.
  Enable through `runnersFleet.customCacheVolumes.enabled` after validation.
- Requests travel through a per-Pod UID virtio-fs mailbox. Read bounded regular
  files through os.Root; derive node, pod and platform from trusted host state.
- Publication requires API pod absence, stopped Tart VM, guest clean-detach
  proof, host APFS verification and server publication eligibility. A webhook
  or terminal pod phase alone never fences writers.
- Built-in and custom admission share the existing quota-bounded APFS filesystem
  and account for each other's private-image capacity. Storage failure goes cold.
- Run `go test -race ./internal/podagent` and shared lifecycle tests. Real APFS
  checks require macOS/hdiutil; Linux CI covers the injected lifecycle tests.
- Migration, rollout and validation: [custom-cache-volumes.md](custom-cache-volumes.md).
