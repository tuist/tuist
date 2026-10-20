# macOS runner runtime

`tart-kubelet` maps one Kubernetes Pod to one Tart VM. The host is trusted;
workflow code runs in the guest. Never expose host credentials or masters.

- Node liveness comes from the `kube-node-lease` Lease that
  `internal/nodeagent/lease.go` renews every 10s on its own client, with a
  bounded timeout. A renewal that fails without an API response closes every
  API connection (shared `connrotation` dialer) so the next one redials. Keep
  slow work (guest probes, label scans) in the Node status refresh, never in the
  lease path.
- Golden bases pull through `--image-mirror` (`internal/podagent/image_mirror.go`)
  when the host has one: the rack's VM image cache (see "The rack's VM image
  cache" in `infra/rack-nodes/AGENTS.md`). Tart has no mirror support, so the
  host probes the mirror's manifest, pulls `<mirror>/<repo>@<digest>` with
  `--insecure`, and falls back to the image's own registry when the mirror is
  down, lacks the image or fails the pull. A mirror still fetching the image
  requeues the Pod (`ImageCacheSyncing`) for up to `--image-mirror-sync-timeout`
  instead of blocking the single reconcile worker. The golden keeps the Pod
  image's name and the GC keeps mirror-pulled OCI entries as their upstream's.
- A golden is named after the Pod's image ref string (`goldenVMName`), not
  the content it resolves to, and so are the golden Node labels the
  runners-controller's affinity reads. Catalog RunnerPools name their image
  by digest (`ghcr.io/tuist/tuist-runner@sha256:…`, see
  `runnersFleet.runnerImageDigests` in the tuist chart), so a runner image
  release that only re-tags a profile keeps that profile's golden. A pool
  that pins a tag gets a new golden, and a cold pull, with every new tag.
- `tart run` needs an Aqua session for the host user. `internal/tart/session.go`
  kicks loginwindow before each run when it is missing; on timeout the error
  names who holds `/dev/console`. `_mbsetupuser` (Setup Assistant from first
  boot) is not fixable by a kick: restart the host. Bootstrap verifies the
  session, so a new host should not reach this (see "The console session" in
  [`cluster-api-provider-tuist`](../cluster-api-provider-tuist/AGENTS.md)).
- A Node this process creates (a host joining or rejoining the cluster) is
  tainted `tuist.dev/prewarming:NoSchedule` while `podagent.Prewarmer` pulls
  the images of its fleet's macOS RunnerPools that keep a warm floor or have
  `spec.replicas > 0`, warm floors first, through `ensureGolden` (the path a
  Pod's first VM takes). An image the rack's image cache is still fetching
  (`errMirrorSyncing`) is asked for again every 30 seconds, not skipped.
  Decision: a taint, not a cordon, because the operator cordons rack hosts by
  hand and tart-kubelet must never lift that. Runner Pods
  do not tolerate it, and the runners-controller leaves tainted Nodes out of
  fleet capacity (`nodeFilterReason`), so the allocator agrees with the
  scheduler. A restart on a registered Node never taints or prewarms: that
  host is serving, and a deploy rolling both runner images and tart-kubelet
  would otherwise empty the fleet. Pulls stop below 30% free disk (a golden is
  tens of GB) and the taint lifts after an hour regardless; a leftover taint is
  removed on the next start. Evidence: on 2026-10-14 b04-b09 joined untainted
  and their first VM per image sat in `CreatingVM` for 5+ minutes downloading.
- Built-in cache behavior remains in `internal/podagent/volume*.go` and the
  runner-image dispatch script. Preserve existing Tuist/CAS paths and identities.
- Custom volumes use `internal/podagent/custom_volumes*.go` and the shared
  [`runner-cache`](../runner-cache/AGENTS.md) journal, archive and publication code.
  Enable through `runnersFleet.customCacheVolumes.enabled` after validation.
- Requests travel through a per-Pod UID virtio-fs mailbox. Read bounded regular
  files through os.Root; derive node, pod and platform from trusted host state.
  Publish responses by writing `<request>.response.tmp` and hard-linking it to
  `<request>.response`: guests never read a partial response, and an existing
  path (including a guest symlink) is never followed or replaced.
- Publication requires API pod absence, stopped Tart VM, guest clean-detach
  proof, userspace APFS verification on an unmounted device and server publication eligibility. A webhook
  or terminal pod phase alone never fences writers.
  The guest side of the clean detach (`tuist-cache-volume --detach-all`, and
  `dispatch-poll.sh` stopping the Tuist CLI's launch agents first) ships in the
  runner image, not with tart-kubelet, so it rolls out with an image release.
- Built-in and custom admission share the existing quota-bounded APFS filesystem
  and account for each other's private-image capacity. Storage failure goes cold.
  Admission, convergence and cache eviction also preserve the host's 15% physical
  free-space floor. Custom admission reclaims its own masters first, then built-in
  masters/convergence staging under the shared lock; remeasure actual space after
  deletion because running CoW clones can pin blocks. Never reclaim live branches.
  A background prefetch the server listed for the host gives way first: built-in
  and custom job admission cancel it and drop its 40 GB reservation before
  evicting any master (`displaceSpareLocked`).
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
  Master prefetch runs one download at a time from a bounded, deduplicated queue:
  masters a job asked for but did not get within its 25 seconds first, then the
  custom HEADs the server lists for the host class (free space only, no eviction).
  Jobs never wait on it. It is reserved and joined at stop. Unavailable responses
  carry a bounded `reason` and the host logs why; a 425 retried until the
  deadline is `execution_pending`, not `denied`.
  A job never waits for a download. Without its base locally it mounts the newest
  older master of the same lineage (reported as `mounted_generation`), or else an
  empty image marked `.cold` that reports a miss and is withheld from publication;
  either way its base is queued. A superseded master used in the last day stays
  until its successor is downloaded through the queue (`LocalImages.Replace`).
  Reserve 20 GB for every attach and 40 GB for prefetch, which also holds the
  archive. Prefetch downloads into `staging/` without the lineage lock, and
  maintenance asks for HEADs before taking it; keep network calls out of that lock.
- Expose mailboxes while the filesystem is mounted, independently of worker
  readiness. Create pod directories before owner records and serialize owner GC.
- Publication/reclamation runs independently of bounded per-pod mailbox workers.
  Join workers before closing the store, preserve in-flight admission reservations
  during recovery scans, and never hold the global store lock across writer-fence
  API calls. Slow publication or restoration must not starve another guest.

- Readiness: without a `readinessProbe`, a Pod is Ready once its VM has an IP
  (customer runner Pods stay here). An `httpGet`/`tcpSocket` probe runs in
  `internal/podagent/readiness.go` on its own goroutine against the guest IP
  (`httpGet.host` ignored, timeout capped at 10s, kubelet threshold
  semantics). `podStatus` only reads the cached result; transitions
  re-enqueue the Pod. `exec`/`grpc` probes fall back to VM-IP readiness with
  a Warning event. Deletion cancels the prober without waiting. A new prober
  seeds from the Pod's published readiness for the same VM so a tart-kubelet
  restart does not flap Ready. A wrong probe stalls rollouts and PDBs, so
  probes stay opt-in per PodSpec.

## Tart versions

The operator installs Tart in place (see
[`macos-host-bootstrap/AGENTS.md`](../macos-host-bootstrap/AGENTS.md)), so a host
runs VMs started by the previous version beside new invocations of the current
one, and a fleet runs mixed versions while a release rolls. tart-kubelet must
work against every release the operator image carries (`TART_RELEASES` in
`cluster-api-provider-tuist/Dockerfile`).

What tart-kubelet relies on, checked from 2.32.1 to 2.41.1:

- VM directories: a standalone VM is `config.json`, `disk.img` and `nvram.bin`
  in both, and running is a `fcntl` lock on `config.json` in both. Existing
  goldens, clones and OCI cache entries are reused after an upgrade, not
  re-pulled, and `tart stop`/`delete` from either version manage the other's
  VMs. 2.36 adds stacked layouts (`manifest.json` + `overlay.asif`), and 2.32
  cannot read one, so rolling back below 2.36 is only safe while no host holds
  one. Rack pools run stacked runner images when `rackFleet.runners
  .stackedImages` is on (see `infra/runner-image/AGENTS.md`). tart-kubelet
  handles them with the same pull, clone and run: the golden and each job VM
  are a manifest and an overlay, and the read-only base sits once in Tart's
  content store (`~/.tart/cache/content`). Deleting a local VM leaves the
  store alone, so the GC runs `tart prune --gc` after it reaps a golden, and
  before it re-measures free space under disk pressure.
- `tart run` stays a foreground process for the life of the VM, so the
  `Setsid` launch and the `pgrep` liveness check are unchanged.
- JSON: `list` and `get` print humanized sizes in text output only (2.36). JSON
  keeps `Size` numeric in `list` and a quoted decimal in `get`, and `Disk` may
  be `null` (2.39). `VM` decodes all of them (`TestVMUnmarshalAcrossTartVersions`).
- `clone` refuses an existing destination without `--overwrite` from 2.40.1,
  even one too incomplete for `tart delete` to remove, and older releases reject
  the flag. `CloneFrom` retries with it only after that refusal.
- `pull --insecure` and image references naming a `host:port` registry, which
  the rack's image cache needs, behave the same.

The Node reports the Tart the host runs as its container runtime version
(`tart://2.41.1`, the CONTAINER-RUNTIME column of `kubectl get nodes -o wide`).
