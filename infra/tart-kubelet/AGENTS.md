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
  requeues the Pod (`ImageCacheSyncing`) for up to `--image-mirror-sync-timeout`.
  The golden keeps the Pod
  image's name and the GC keeps mirror-pulled OCI entries as their upstream's.
- The Pod controller has one reconcile worker, so nothing slow may run inside
  a reconcile: noticing that a VM exited (which frees the scheduler's slot)
  and a Pod's teardown (finalizer removal) wait behind it. A Pod whose
  golden is missing starts its pull in the background (`readyGolden`), stays Pending with `PullingImage`,
  and is re-enqueued when the pull ends; Pods of the same image wait on the
  same pull, including the prewarmer's. One golden materializes at a time per
  host. A failed pull is reported to the waiting Pods for 30 seconds, then
  pulled again. Evidence: on 2026-10-21 the first Pod of a new runner image
  on b04 and b08 pulled from ghcr.io for 532 s and 562 s inside its reconcile,
  and the other VM on each host halted unobserved: its Pod read `Running`
  for up to nine minutes, so the scheduler saw both hosts as full.
- A golden is named after the Pod's image ref string (`goldenVMName`), not
  the content it resolves to, and so are the golden Node labels the
  runners-controller's affinity reads. Catalog RunnerPools name their image
  by digest (`ghcr.io/tuist/tuist-runner@sha256:…`, see
  `runnersFleet.runnerImageDigests` in the tuist chart), so a runner image
  release that only re-tags a profile keeps that profile's golden. A pool
  that pins a tag gets a new golden, and a cold pull, with every new tag.
- The GC (`internal/podagent/garbage.go`) reads the Node's fleet's macOS
  RunnerPools as the prewarmer does. A golden or cached OCI image that no pool
  runs and no Pod on the Node references is reaped on the next pass; one a
  pool still runs, or will run next (the upcoming runner images ConfigMap,
  see staging below), keeps the 24h idle retention. Cached images are matched by
  full ref, except a repository a Pod or pool names by tag keeps every digest.
  A fleet without pools, or a failed RunnerPool or ConfigMap List, falls back
  to retention and the repository match. Evidence: on 2026-10-20 rack hosts held 13 to 21
  goldens, 1 or 2 of them current, because runner images are released several
  times a day and every catalog image shares one repository.
- A release is followed, not re-pulled (`internal/podagent/follow.go`). While
  a host holds the golden of a pool's `status.previousImage` (or of
  `status.observedImage` before the runners-controller has seen the new
  `spec.image`) and not the current one, the GC keeps the previous golden and
  its cached image and pulls the current image in the background, one at a
  time, through `ensureGolden`. The next pass after the pull reaps the
  previous one as superseded. A stacked golden's base stays in Tart's content
  store throughout, so the pull is only the overlay. Bounds: no follow under
  disk pressure or below the prewarmer's 30% free floor, and a golden is kept
  for its successor at most `defaultFollowTimeout` (2h). Evidence: after the
  release of 2026-10-22 13:00 UTC the GC freed about 60 GiB per reaped golden
  per rack host, and the next pull took 10 to 23 s on hosts that still held
  the base against 9.5 to 12.8 minutes on hosts that did not. Every 6 vCPU
  rack pool keeps a warm floor, so the prewarmer below pulls every catalog
  image onto a joining rack host (about 60 GiB each; the rack's disk plan in
  `values-managed-production.yaml` allows for all of them).
- `tart run` needs an Aqua session for the host user. `internal/tart/session.go`
  kicks loginwindow before each run when it is missing; on timeout the error
  names who holds `/dev/console`. `_mbsetupuser` (Setup Assistant from first
  boot) is not fixable by a kick: restart the host. Bootstrap verifies the
  session, so a new host should not reach this (see "The console session" in
  [`cluster-api-provider-tuist`](../cluster-api-provider-tuist/AGENTS.md)).
- A Node this process creates (a host joining or rejoining the cluster), or
  a registered Node whose disk has never held a runner image (a host
  reinstalled in place keeps its Node), is tainted
  `tuist.dev/prewarming:NoSchedule` while `podagent.Prewarmer` pulls the
  images of its fleet's macOS RunnerPools that keep a warm floor or have
  `spec.replicas > 0`, warm floors first, through `ensureGolden` (the path a
  Pod's first VM takes). An image the rack's image cache is still fetching
  (`errMirrorSyncing`) is asked for again every 30 seconds, not skipped.
  Decision: a taint, not a cordon, because the operator cordons rack hosts by
  hand and tart-kubelet must never lift that. Runner Pods
  do not tolerate it, and the runners-controller leaves tainted Nodes out of
  fleet capacity (`nodeFilterReason`), so the allocator agrees with the
  scheduler. "Never held a runner image" is no golden and no
  `<user-data dir>/.holds-runner-images` marker (`podagent.HostDisk`), which
  `ensureGolden` writes whenever a golden exists and an erase removes. A
  restart on any other registered Node never taints or prewarms, including an
  idle host whose goldens a release just superseded: that host is serving, and
  a deploy rolling both runner images and tart-kubelet would otherwise empty
  the fleet. A failed probe counts as not fresh. Pulls stop below 30% free
  disk (a golden is tens of GB) and the taint lifts after an hour regardless;
  a leftover taint is removed on the next start. Evidence: on 2026-10-14 b04-b09 joined untainted
  and their first VM per image sat in `CreatingVM` for 5+ minutes downloading;
  on 2026-10-21 ber1-runner-b05 came back from `tuist.dev/os-reinstall`
  untainted with no goldens and took runner Pods that waited on downloads.
- Every host then stages, once a minute and in the background, the goldens it
  is about to need (`podagent.Prewarmer.stage`, `internal/podagent/stage.go`):
  for each pool of its fleet it served in the last 24 hours (it held the
  golden of the image the pool ran then), the pool's current image and the
  one it moves to next, when the host lacks them. The next image comes from
  ConfigMaps labelled
  `tuist.dev/upcoming-runner-images=true`, keyed `<xcode>.<variant>`, which
  the `announce` job of `runner-image-release.yml` writes into canary and
  production. A deploy holds each pool on its current image until every
  Ready, schedulable Node holding the current image's golden label also
  holds the new one (`.github/scripts/runner-image-staging-gate.sh`, run by
  `server-deployment.yml` before the chart upgrade), and `announce` waits for
  the same before it dispatches the release's deploy. Both give up an hour
  after the announcement (`tuist.dev/runner-image-announced-at`), and a
  release dispatched with `skip_staging` moves the pools at once
  (`tuist.dev/runner-image-staging: skip`). A pool is
  matched by its `tuist.dev/xcode-version` and `tuist.dev/runner-image-variant`
  (`standalone` or `stacked`) labels, which the chart renders only on catalog
  pools that follow releases; an entry outside the pool's repository is
  ignored. Staging uses `ensureGolden`, so a Pod of the same image joins the
  pull. It starts no pull while a Pod waits on one, or below 30% free disk,
  and skips an image the rack's image cache is still fetching until the next
  pass. A Pod of another image that arrives during a staged pull waits for it,
  since a host pulls one golden at a time. Following a pool to its new image
  also covers a pool moved before its hosts staged it (the timeout or a
  skip). A host that never served a pool still pulls on its first Pod.
  `tart_kubelet_golden_staged_total{result}` counts what staging did; the
  pools' materialized and reused counts show whether Pods still pull.
  Evidence: in the week to 2026-10-22 ber1-runner-b03 to b09 each pulled 24
  to 42 goldens from ghcr.io, 6 to 7 minutes each on average, over 19 runner
  image releases, and a release reaches production about 20 minutes after
  its deploy is dispatched. The rack's image cache only moves those pulls onto
  the rack network; it does not take them off a job's path.
- Custom cache volumes are the only runner cache on macOS hosts. The volume
  they share is `CacheSpace` (`internal/podagent/volume*.go`): the APFS volume
  at `--runner-cache-root`, which holds `custom/`. Every five minutes it
  removes the built-in cache's leftovers and nothing else: top-level
  directories named by a decimal account ID, `_converge/`, `usage-reports/`
  and `branches/`, keeping `branches/<vm>` while that VM runs or `tart`
  cannot say. Unknown entries stay and are logged at debug level.
  Runner Pods (`tuist.dev/runner=true`) always get the guest-writable `status`
  share (`StatusDirForPod`), which carries `runner-rc`, `runner.log` and
  `runner-heartbeat`; they never get a `cache` share.
- Custom volumes use `internal/podagent/custom_volumes*.go` and the shared
  [`runner-cache`](../runner-cache/AGENTS.md) journal, archive and publication code.
  Enable through `runnersFleet.customCacheVolumes.enabled` after validation.
- Requests travel through a per-Pod UID virtio-fs mailbox. Read bounded regular
  files through os.Root; derive node, pod and platform from trusted host state.
  Publish responses by writing `<request>.response.tmp` and hard-linking it to
  `<request>.response`: guests never read a partial response, and an existing
  path (including a guest symlink) is never followed or replaced.
- A running VM's branch image lives only in its share; never stat or open it by
  `images/<use>.img` (absent then) and never give it a second name outside the
  share. Measure and find it with `cachevolumes.APFSBranchFile`/`APFSHasBranch`.
  Evidence: on 2026-10-21 two of three macOS saves failed because the guest's
  open of a hard-linked image was denied after the host's 30-second
  reservation refresh looked the image up by its private name.
- Publication requires API pod absence, stopped Tart VM, guest clean-detach
  proof, userspace APFS verification on an unmounted device and server publication eligibility. A webhook
  or terminal pod phase alone never fences writers.
  `verifyCustomImage` also returns the unmounted container's in-use bytes
  (`diskutil apfs list`), which `Seal` compares with the guest's measurement:
  writes the guest made through its share can be lost, and such an image passes
  fsck (result `incomplete`, see `runner-cache/AGENTS.md`).
  The guest side of the clean detach (`tuist-cache-volume --detach-all`, and
  `dispatch-poll.sh` stopping the Tuist CLI's launch agents first) ships in the
  runner image, not with tart-kubelet, so it rolls out with an image release.
- Custom and checkout admission share the quota-bounded APFS filesystem.
  Storage failure goes cold. `--runner-cache-budget-gib` caps the free space
  and capacity they see below the quota (`volume_space.go`), so the budget can
  change without a new volume; APFS cannot change a quota after the volume is
  created. Admission and cache eviction also preserve the host's 15% physical
  free-space floor. Custom admission evicts its own masters first, then idle
  checkout copies (`reclaim`); remeasure actual space after deletion because
  running CoW clones can pin blocks. Never reclaim live branches.
  A background prefetch the server listed for the host gives way first: job
  admission cancels it and drops its reservation (twice its volume size)
  before evicting any master (`displaceSpareLocked`).
  Among custom masters, eviction takes superseded generations and unused spare
  prefetches first and the lineages a running or attaching job holds last
  (`LocalImages.InUse`); see `runner-cache/AGENTS.md`.
- The heartbeat labels the Node `tuist.dev/cache-volume-capacity-gib` with that
  budgeted capacity (`CustomVolumes.CapacityNodeLabels`), and none while the
  cache filesystem is unmounted. The server subtracts the volumes of every job
  with an open runner session here, attached or only predicted, because a job
  reserves its volumes at attach, minutes after dispatch. Dispatch affinity and
  macOS Pod placement prefer this host for a job only while its volumes fit.
- Run `go test -race ./internal/podagent` and shared lifecycle tests. Real APFS
  checks require macOS/hdiutil; Linux CI covers the injected lifecycle tests.
- Migration, rollout and validation: [custom-cache-volumes.md](custom-cache-volumes.md).
- Logs: `logger=custom-cache-volumes` carries `cache phase` (one per
  `Observation`, with the volume's subject fields), `cache master evicted`, and
  `admission cancelled a background prefetch` (the cancelled prefetch's `scope`
  plus the `for_*` subject it made room for), and `removed leftovers from the
  runner-cache root` (`removed`, `freed_bytes`). Fields are listed in [`runner-cache`](../runner-cache/AGENTS.md).
  The `tuist_runner_cache_volume_*` metrics keep only operation/source/result.
  Everything that happened to one volume on a host:

  ```logql
  {job="tuist-macos-tart-kubelet", instance="<host>"} |= "<scope>"
    | json | logger="custom-cache-volumes"
    | line_format "{{.msg}} {{.operation}} {{.reason}} {{.result}} gen={{.generation}} pod={{.pod}}"
  ```

  Searching for the 48-hex prefix from a `tuist.dev/cache-volume-<prefix>` node
  label matches the same lines. The Linux agent logs the same fields as JSON
  under `cache volume operation` and `cache master evicted`.

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
  empty image marked `.cold` that reports a miss and is withheld from publication
  unless the report response pairs `seal` with `cold_publish: true` (the Store's
  `publish` action); either way its base is queued. A superseded master used in the last day stays
  until its successor is downloaded through the queue (`LocalImages.Replace`).
  An unchanged branch of its own base reinstalls that master if admission
  evicted it during the job (see `runner-cache/AGENTS.md`).
  The host maximum is `--custom-cache-max-volume-gb` (100 GB by default, env
  `TART_KUBELET_CUSTOM_CACHE_MAX_VOLUME_GB`), sent as `max_volume_bytes` with every
  authorization alongside the guest's valid `requested_volume_bytes`; a 507 is
  reason `capacity`. Reserve what the job is expected to write
  (`Identity.ExpectedBytes`, capped at `Identity.VolumeBytes`, 20 GB when the
  server sends none) for every attach, and the rest of it for a running VM, not
  the capacity: on 2026-10-21 six volumes of one job asked for 130 GB of a 240 GiB
  rack cache disk while holding under 25 GB, and jobs ran cold for "no room".
  Jobs can then write past their reservations: the gap between the budget and
  the APFS quota is the safeguard, so keep the budget well below the quota.
  `relieve` evicts idle custom masters once reservations no longer fit, and
  `notePressure` marks running branches `.pressure` (withheld, never published)
  with under 2 GB left before the quota or the host disk is full. See
  [custom-cache-volumes.md](custom-cache-volumes.md).
  For prefetch, which also
  holds the archive, twice `HeadSizeBytes` (twice the capacity when the head size
  is unknown), in both the shared-filesystem check (`reserveBytes`/`reserveSpare`)
  and the custom reservation (`customAdmissionBytes`): if they disagree, the
  second rejects what the first admitted. A warm copy smaller than its capacity
  is grown with `hdiutil resize -imageonly` before exposure; never attach it on
  the host to grow it. The guest grows the APFS container. Prefetch downloads
  into `staging/` without the lineage lock, and
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

- Cached checkouts (spec #99) are custom volumes with the reserved key
  `checkout`, written only by the host. The populator is the shared
  `cachevolumes.Checkouts` (`infra/runner-cache/checkout.go`, with
  `APFSCheckoutImages`); it keeps one master per (scope, clear generation) under
  `<custom root>/checkouts` with real git and a pinned, checksum-verified git-lfs
  that `checkout_git_lfs.go` installs into `checkouts/.bin`; the host needs the Command Line Tools (bootstrap installs
  them) and otherwise leaves checkouts off. The host never fetches from GitHub.
  After the job the guest writes `checkout-export/` (pack, head, shallow, LFS
  objects) into its share; `collectCheckout` moves it to `checkouts/.incoming/`
  when the pod's share is cleaned, only for a pod the host granted a checkout,
  and only a real directory. Never mount guest APFS for this. Everything in an
  export is untrusted (runner-cache `checkout_export.go`): read through `os.Root` without
  following links and bounded, the pack goes through `git index-pack --strict`
  after the shallow boundary is recorded, LFS objects are hashed against their
  names, and the host writes the working tree and the index itself. Only LFS
  objects the exported commit references are kept, an export is capped at half
  an image (and 200,000 LFS entries), and a build reserves twice its size. A
  master's tip only moves to a default-branch job's commit (`default_branch_job`
  is the server's verified `trusted`, never the branch name) whose LFS objects
  are all present: its tree is handed to every later job, and a pointer left in
  it would be served as the file. While the lineage has no HEAD
  (`base_generation` 0), a job with `may_start_master` (a same-repository writer
  branch its profile saves from; never forks or pull_request_target) may also
  start the master at its own verified commit, or at its pull request's test
  merge of it (two parents, one of them that commit); once a master exists, its
  exports only add objects. Branches stay
  `refs/remotes/origin/*` (actions/checkout deletes local branches before
  fetching) and job commits live under `refs/tuist/recent/*`. Wait past the
  smudged files' mtimes before the final `update-index --really-refresh`: racily
  clean LFS entries turn back into pointers in a guest that has not configured
  the LFS filter.
- A master whose tip moved (a default-branch commit, or a started lineage) is
  published under the job's use (`Checkouts.Transfer`, bounded by the checkout capacity, not the custom
  one); a cold host with a HEAD restores it in the background instead. A cold
  answer journals no branch and reports the use deleted at once. A host without
  working git answers `denied`, so guests do not export. `Track` maps the
  server's stable `volume_key` to the current scope and drops the previous
  scope's copies after a clear. Custom-volume admission evicts idle checkout
  copies before refusing. Pressure eviction skips masters with a live or attaching
  clone (`Checkouts.InUse = Store.InUse`).
- A guest asks with `{"checkout": true}` in the mailbox (15 s budget); the host
  allocates through `/checkout`, marks the identity `Kind: checkout` itself,
  strips the HEAD fields (the branch is a clone of this host's master) and seeds
  the branch from the master (`APFSImages.Seed`), never an empty image.
  Checkout branches are never publishable. Builds reserve disk through the
  custom admission (`checkoutReserved`) and evict LRU checkout masters only when
  that can make the room; a build refused for room is retried every reconcile
  for an hour.
  Run the real-tools test with `TUIST_CHECKOUT_E2E=1 go test -run CheckoutMasterEndToEnd .` in
  `infra/runner-cache`; the podagent tests cover the mailbox and collection.

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
