# Runner Image

Tart VM image hosted on the **customer-runner Mac mini fleet**
(`tuist.dev/fleet=<runnersFleetName>`). One image, one Tart VM
per Pod, one ephemeral GitHub Actions runner per VM, one job per
runner.

## What's in the image

The runtime user is `runner` with home `/Users/runner`, matching
GitHub-hosted macOS runner images. On-disk artifacts that bake
absolute paths (SwiftPM `.build/checkouts/`, Xcode DerivedData,
`actions/cache` payloads) are interchangeable between hosted and
self-hosted runs without per-environment cache keys.

The Cirrus base image's pre-existing `admin` user is kept around
as the Packer SSH provisioning identity but is not used at
runtime — no service, sudo entry, or auto-login targets it.

Because the base images provision as `admin` and jobs run as
`runner`, anything the base installs under `admin` has to be
handed over explicitly. Three things are:

- `/opt/homebrew`. The prefix shipped owned by `admin`, so `brew
  install` from a workflow step failed its writability audit
  while `brew` itself resolved fine on `PATH`. GitHub-hosted
  images build and run under one account, so the job user owns
  the prefix — this image chowns it to `runner` to match.
- `~/.zprofile`. The cirruslabs base writes it for `admin` and
  symlinks `/Users/runner` at `/Users/admin`; this image replaces
  that symlink with a real `runner` account whose home comes from
  macOS's user template and has no `.zprofile`, so the file is
  copied over. Without it the login shell the LaunchAgent (and
  every step shell under it) runs resolves no brew shellenv, no
  rbenv, no node.
- The Metal Toolchain. On Xcode 26.1 a toolchain downloaded by
  `admin` is not usable by `runner`, so the image downloads it again
  as `runner`, with the same explicit `-buildVersion` the base uses
  (see `infra/macos-xcode-image/AGENTS.md`). Base images built before
  the toolchain was added to them have none, and this download is
  what installs it.

When adding tooling to the base, check ownership and login-shell
reachability from `runner`, not just presence under `admin`.

A related class of gap is anything GitHub-hosted images pre-seed
that ours do not. When adding parity features, compare against
`actions/runner-images` `images/macos/scripts/build/`, and pair
each one with a check that asserts the behaviour rather than the
ingredient — every gap so far was found by a release failing, not
by the image build.

TCC is one of those gaps. Scripted Finder automation (`create-dmg`,
anything driving Finder through `osascript`) needs a standing
`kTCCServiceAppleEvents` approval, or the first send waits on a
consent prompt nobody can answer and fails as `AppleEvent timed out
(-1712)`. `dispatch-poll.sh` (`approve_finder_automation`) writes it
at boot. Three details decide whether a row matches, and earlier
attempts got each one wrong:

- **Database.** Only the session user's
  `~/Library/Application Support/com.apple.TCC/TCC.db` is consulted.
  A row in the system database is ignored. The user database only
  exists once `runner` has logged in, which is why this runs at boot
  and not in the Packer template.
- **Client.** TCC charges the event to the responsible process, not
  to `osascript`. For GitHub jobs that is
  `/Users/runner/actions-runner/bin/Runner.Listener`. The Buildkite
  and GitLab agents are started directly by `dispatch-poll.sh`, so
  theirs is expected to be its `/bin/bash`. `log stream --predicate
  'subsystem == "com.apple.TCC"'` names it (`Prompting for access to
  indirect object Finder by …`).
- **Target.** `indirect_object_code_identity` must hold Finder's
  code requirement. A row with it NULL is ignored.

The sanity checks at the end of the Packer template run as `sudo
-u runner -H`. macOS sudoers keeps `HOME`, so dropping `-H`
leaves them pointed at `/Users/admin` and they assert against the
provisioning account's environment instead of the runtime one —
which is how a reachability check stayed green through months of
broken `brew install`s, and how the `brew install hello` check
added to catch that failed on `admin`'s unwritable cache instead.

- `/Users/runner/actions-runner/` — GitHub Actions runner binary
  (no registration; we register at runtime via JIT config minted
  by `Tuist.Runners.Reconciler` / `Tuist.Runners.Dispatch`).
- `/opt/tuist/buildkite-agent` — Buildkite agent binary, for jobs
  dispatched from a customer's Buildkite cluster. Both agents live in
  the one image because which one runs is decided per job at dispatch,
  so a warm Pod has to be able to serve either; forking the image would
  split the warm pool to save one binary.
- `/opt/tuist/buildkite-hooks/` — global agent hooks (`--hooks-path`),
  so they run for every job regardless of what the customer's
  repository defines. `environment` re-exports the cache settings the
  server sent (the agent sanitizes the job environment, so an export
  from `dispatch-poll.sh` does not survive into the job) and stamps the
  job's start; `pre-exit` posts the job's log and its window back to the
  server, authenticating with the job-scoped report token dispatch
  minted rather than the Pod's SA token. The same two hooks ship in the
  Linux image (`infra/linux-runner-image/buildkite-hooks/`) and are kept
  byte-identical: they take their paths from `TUIST_RUNNER_JOB_ENV` and
  `TUIST_RUNNER_STATE_DIR` so nothing platform-specific leaks in. The log comes from `BUILDKITE_JOB_LOG_TMPFILE`, which the
  agent writes because it is started with `--enable-job-log-tmpfile` and
  deletes when the job ends — hence a `pre-exit` hook rather than
  anything later. `pre-exit` also writes the job's outcome as it sees it
  (`succeeded`, `failed` or `canceled`) to `job-result` in its state
  directory, ahead of the credential check, for the cache-volume promote gate
  below. Only the macOS teardown reads it, and only together with the agent's
  exit status (see below). `canceled` comes from `BUILDKITE_JOB_CANCELLED`,
  which the executor sets for the hooks that run after a cancel.
- `/Users/runner/work/<owner>/<repo>` — workspace path the JIT
  config sets via `work_folder: "/Users/runner/work"`; matches
  GitHub-hosted's `GITHUB_WORKSPACE`.
- `/opt/tuist/inject-env.sh` — root-owned helper; reads
  tart-kubelet's env mount (`/Volumes/My Shared Files/env/tuist.env`)
  into `/etc/tuist.env`.
- `/opt/tuist/dispatch-poll.sh` — polls
  `TUIST_RUNNER_DISPATCH_URL?pod_uid=…&token=…`. While 204 it
  sleeps; on 200 it runs the agent the response selects: `./run.sh
  --jitconfig $JIT` for a GitHub job, or `buildkite-agent start` with
  `BUILDKITE_AGENT_ACQUIRE_JOB` set for a Buildkite one. The Buildkite
  branch skips the idle watchdog entirely — an acquisition token names
  one job UUID, so there is no window in which a registered agent waits
  to be handed work, which is the whole hazard that watchdog bounds.
  Captures
  the rc and `sudo shutdown -h now`s the VM via an `EXIT` trap so
  `tart run` returns and tart-kubelet flips the Pod to
  Succeeded — the watcher's GC + warm-pool refill are gated on
  that transition.
  `dispatch-poll.sh` also drives the **cache-volume** flow, one volume per
  repository (per account for a job with no repository), materialized after
  dispatch. The guest never learns which volume it got: the server stamps it on
  the Pod and resolves it from there on every promote. tart-kubelet attaches
  an *empty* per-VM branch directory as a writable virtio-fs share at
  `/Volumes/My Shared Files/cache`. The cache itself is a **sparse APFS disk
  image** (`cache.sparseimage`) inside that share, not files on it: virtio-fs
  cannot set xattrs on symlinks, and macOS frameworks are versioned bundles
  whose symlinks carry the CLI's signature xattrs, so caching any macOS slice
  onto the share fails (ELOOP). Inside an image the filesystem is real APFS and
  only one regular file crosses virtio-fs.
  The share is empty until dispatch: once the server stamps the pod's account
  and cache-volume labels, the host clonefiles that volume's master image (or,
  for a repository with no master on the host yet, the account's `tuist-cache`
  master at base generation 0) into the branch and
  writes a `cache-ready` marker. After receiving the JIT and before `./run.sh`,
  the guest calls `wait_for_cache_ready` — a bounded (~60s) wait on that marker
  — then `attach_cache_image` (`hdiutil attach … -owners off`, which maps the
  contents to the guest user and so retires any host/guest uid reconciliation),
  points `TUIST_XDG_CACHE_HOME` at the **mountpoint**
  (`/Users/runner/.tuist-cache-volume`), divides the budget the host stages for
  both caches between them by use (`set_cache_limits`, described with the
  compilation cache below) and exports the binary cache's limit as
  `TUIST_CACHE_MAX_BYTES` for the CLI's LRU prune and download admission, reads
  the host-staged base generation
  (`cache-base-generation`) — the HEAD generation the branch was clonefiled from,
  used as the fast-forward base at promote — and snapshots the pre-job inventory.
  The host also stages its Kubernetes `node-name` there at VM create, which the
  guest relays with its promote so the HEAD row records WHICH host published a
  generation — the Node name rather than `TUIST_RUNNER_POD_NAME`, because the Pod
  is gone minutes later while the Node name is what the
  `tuist.dev/cache-master-<account_id>[.<volume>]` advertisements and the volume affinities
  are keyed on. Attribution only: nothing in the fast-forward reads it, and an
  unstaged name reports empty rather than falling back to the Pod name, since a
  column holding two kinds of name identifies neither. Every value the guest takes
  off the share is sanitised to its own alphabet and length before it reaches a
  request body.
  Timeout / absent share / failed attach ⇒ cold path, unchanged. A cold first job
  still gets an *empty* image — the guest can only attach what is there, and no
  image would kill the job rather than cost it warmth.
  Only a job that **succeeded** promotes. The gate is `JOB_PASSED` (zero exit AND
  a job result of `succeeded`), not the runner's exit status. `run.sh` folds
  every Listener code except a restart into 0, and the GitLab executor exits 0
  for job outcomes by design. Gating on the exit status promoted failed and
  cancelled jobs, about one in ten of one account's HEAD publishes in a week.
  GitHub's verdict is the Listener's `_diag/Runner_*.log` line `finish job
  request for job <id> with result: <Result>`, matched only at a `JobDispatcher`
  trace header, because a later line echoes the job's display name. The Listener
  writes that line on both its normal and its cancel/abandon path, with the value
  it reports to GitHub.
  GitLab's verdict is `/var/log/tuist-runner/job-result`, written by
  `tuist-gitlab-runner --result-file`. Buildkite's is that file as the
  `pre-exit` hook wrote it, turned into `failed` when the agent, started with
  `--reflect-exit-status`, exits non-zero (`buildkite_job_result`). The hook
  alone misses failures the executor settles after it: an automatic artifact
  upload, or a repository or plugin `pre-exit` hook. The status alone misses a
  cancel. The script still exits 0 for any job the hook saw, because the
  runners-controller reads a non-zero runner exit as a runner death. A
  failed, cancelled or missing verdict withholds every promote-only step:
  teardown prune, compaction, dirty marker and HEAD publish. The drain still runs
  for every job. Three sources that look usable are not:
  - the Worker's `Job result after all job steps finish` line is never written
    when a job fails to initialize or its Worker crashes;
  - `ACTIONS_RUNNER_RETURN_JOB_RESULT_FOR_HOSTED` returns 100 + the result, but
    `run.sh` still folds that into 0, and the Listener reports `Succeeded` when
    its dispatch throws;
  - `ACTIONS_RUNNER_HOOK_JOB_COMPLETED` runs as a job step before the result is
    settled, and no status variable reaches it.
  Teardown order is load-bearing: **wait for the compilation cache's
  publications to reach the remote** (`drain_cas_publications`, below), sample
  the signals that need a live mount (fill
  %), then **detach**, then measure the SETTLED image for the digest this job
  publishes (`capture_settled_inventory` re-attaches the detached file READ-ONLY —
  the same view the verifying host uses), then write `cache-dirty` (only after both
  a clean detach and a successful measurement — its absence is what tells the host
  to discard, the safe default for any teardown that reaches neither). The digest
  must NOT be read through the job's own read-write mount, which is what this
  replaced: it is both the HEAD's `tree_digest` and the immutable object key, so it
  is a claim about the bytes the upload sends, and anything writing to the image
  between the measurement and the detach breaks that claim permanently. The window
  is why `detach_cache_image` polls and then forces at all — processes outlive the
  runner (a lingering build service, the compilation cache's own asynchronous store
  flush/prune, busiest for the largest caches) and every `~cas/` line carries a file
  SIZE, so one late append is enough. A HEAD published from a pre-detach snapshot
  names bytes no host can reproduce: convergence verifies the downloaded object and
  declines, so no promote can build on that HEAD — base 0 is rejected while a HEAD
  exists, and a host left at an older generation is rejected for a stale base — and
  the account is stuck fleet-wide (seen in production: one account cold on all nine
  hosts for days). When a host does hit that, it stages the disproved digest as
  `volume-head-unverifiable` in the `status` share and the guest relays it as
  `unverifiable_digest` with BOTH promote requests, which is what lets the server
  retire a HEAD nothing can adopt, from either base — it rides the mint request too,
  or the pre-flight would 409 the only promote that can unwedge the account.
  Between the inventory and the content hash, a successful job whose image changed
  runs `compact_cache_image`: a prune frees blocks inside the image's filesystem
  and none in the image file, so without `hdiutil compact` a master costs the host
  the most it ever held. It leaves the capacity alone. Shrinking the capacity
  instead was measured and dropped: it moves every live block past the new end
  (92 s for 3.6 GiB of live data) and frees nothing compaction does not. It
  rewrites the file, which is why it sits before the content hash and after the
  inventory, which it does not change.
  Alongside the inventory digest, `capture_content_digest` hashes the settled
  image FILE (SHA-256, after the read-only measuring attach detaches and after the
  compaction) into `content_digest`: the inventory digest fingerprints entry names and sizes, so a
  bit flipped INSIDE a cached file sails through it, and the content digest is the
  end-to-end byte claim. It rides both promote requests; the mint response echoes
  the base64 the server signed into the presigned PUT as `checksum_sha256`, the
  guest sends it as `x-amz-checksum-sha256` (only when echoed — the URL's
  signature covers it), the object store verifies the payload at ingest, and the
  converging host verifies the download against the HEAD row's digest before
  adopting (a mismatch stages `volume-head-unverifiable` exactly like an inventory
  mismatch). All of it is optional per hop, so images and servers roll
  independently: no digest, no echoed checksum, or a HEAD row without one just
  degrades to the pre-hash behaviour. Promotion is a **fast-forward
  compare-and-swap**, not a direct host clone: the guest uploads the detached
  image to a content-addressed key and reports the HEAD with `base_generation`,
  and the server advances the HEAD only if it is still at that base (200,
  returning the accepted generation) or rejects a stale base (409). The guest
  captures the HTTP status EXPLICITLY (no `curl -f`, which would collapse a 409
  and a transport error into one failure) and relays the outcome into the
  `status` share as `cache-promote-result`: `accepted <generation>`, `conflict`,
  or `error`. Most promotes lose that race, and the upload blocks the VM halt and
  the host's slot, so the guest sends `base_generation` when MINTING the upload
  URL too and the server 409s there — pre-empting the transfer for a promote that
  cannot win. That pre-check may only ever skip doomed work: it is racy by
  construction (another host can win during the upload), so the bump's
  compare-and-swap stays the authority, an absent `base_generation` disables it
  for older runner images, and any other failure falls back to
  upload-then-arbitrate. The host's `Finalize` installs the branch as the
  account's local master (a whole-image replace) ONLY on `accepted` — so the local
  master and the HEAD advance together. A `conflict` (a stale base another host
  advanced past) or an `error` (upload/network/control-plane failure — kept
  distinct so an outage is not mistaken for cross-host contention) discards the
  branch and lets convergence re-warm it. A rejected promote that got as far as
  uploading leaves an object no HEAD points at, so the server records it as an
  orphan and reclaims it after the URL-TTL grace; a pre-empted one never wrote
  anything to reclaim. The
  host clones the promoted image and cannot tell a torn snapshot from a good one,
  so a mount torn down by the VM halting would poison the account's master; if the
  detach fails even with `-force`, the guest withdraws the image from both
  promotion and publication.
  The server also delivers a `cache_signing_grant` in
  the dispatch 200, exported as `TUIST_CACHE_SIGNING_GRANT` so the EE CLI signs
  artifacts with the account scope instead of the machine MAC — which is what
  lets a clonefiled master validate across the account's VMs. The Xcode
  compilation cache (CAS) is **folded INTO the cache image**: a
  `CompilationCache.noindex` store dir beside `tuist/` inside the one mounted
  image, so it rides the binary cache's whole lifecycle — clone, promote,
  fast-forward HEAD, convergence — with no separate image, mount, or promote
  gate. (It works because the store is on the block-device image, not the
  virtio-fs share — llcas mmaps its store and mmap over virtio-fs SIGBUSes.) When
  the host stages the `cas-enabled` marker (gated on `--cache-volume-cas-gib`),
  `setup_cas_store`, called after the attach-time prune (which can be what makes a full image's store writable), creates
  the store, writes an xcconfig pointing `COMPILATION_CACHE_CAS_PATH` at it, and
  exports **`XCODE_XCCONFIG_FILE`**. There is no separate detach or CAS success
  gate: the cache image's own quiesced detach (and not-promotable-on-failed-detach
  guard) covers it. A compile-only job still persists its CAS because the
  inventory digest includes one `~cas/<relpath>\t<size>` line per store file (a
  content identity, computed identically host- and guest-side), so CAS growth
  flips the digest → dirty → the whole image promotes. The `.noindex` name keeps Spotlight (`mds`)
  out of the multi-GB store. Absent marker ⇒ the compilation cache runs VM-local
  (cold), unchanged. The CAS shares the volume cap with the binary cache, so size
  `--cache-volume-cap-gib` for both and keep HEAD uploads fast
  (`tart_kubelet_cache_volume_upload_seconds` watches the teardown upload that
  blocks slot reclaim).
  **The two caches share one budget.** The host stages `cache-budget-bytes`:
  the image less a reserve of max(2 GiB, 20% of the cap), 24 GiB at a 30 GiB
  cap, and the reserve is the room a job grows into before anything prunes.
  `set_cache_limits` divides it between `tuist/` and `CompilationCache.noindex/`
  by their allocated `du` sizes, with the rule the stores are divided by
  (`split_by_use`, below) and a 2 GiB floor per cache
  (`CACHE_SPLIT_FLOOR_BYTES`). The floor matters for the binary cache, which the
  CLI holds to its limit for the whole job (a download that does not fit is
  rebuilt from source), so a cache that holds nothing yet next to a busy one
  still gets 2 GiB and doubles from there; two caches that each hold under a
  quarter of the budget split it evenly. It runs twice: at attach, before the
  attach prune, and at teardown, before the teardown prune, because the binary
  cache may have grown to its attach-time share during the job and nothing
  prunes it at teardown. Neither cache is handed room the other still holds
  (`within_room`): the compilation cache's limit is capped at the budget less
  what `tuist/` holds, and `limit_binary_cache` exports the binary cache's
  after the attach prune, capped at the budget less what the store holds once
  pruned, since a prune keeps a store's newest generations even past a limit
  that just shrank. The two
  limits therefore never add up to more than the budget. A cache that stops
  being used gives its space back only as fast as its own pruner collects it:
  the CLI's LRU and 7-day age prune for `tuist/`, a rotation for the store. A
  host whose tart-kubelet predates `cache-budget-bytes` stages only the fixed
  split (`cache-max-bytes`, and the `cas-enabled` figure), and
  `set_cache_limits` applies that as is, so the two components roll out in
  either order.
  Each division is staged back for the host in `cache-limits`
  (`stage_cache_limits`), one `<when>\t<cache>\t<held>\t<limit>` line per cache
  at attach and at teardown, which the host exports as
  `tart_kubelet_cache_volume_cache_bytes` and
  `tart_kubelet_cache_volume_cache_limit_bytes`. Those sizes are the only
  per-cache measurement the fleet has, and they are what the rule and its floors
  are retuned from: this log carries the same numbers, but the host re-emits only
  a bounded tail of it, so a verbose job's attach lines never reach the log
  store. Staged at attach AFTER `limit_binary_cache`, so what is recorded is the
  limit that was applied.
  The store is bounded by `prune_cas_stores`, which runs at BOTH ends of a
  job, and by nothing else. `COMPILATION_CACHE_LIMIT_SIZE` bounds a GENERATION, not the directory:
  llcas rotates (new primary, old one demoted) when the chain is over the limit
  and its last handle closes, and only `llcas_cas_prune_ondisk_data` deletes what
  falls off — which no part of a build ever calls, so the store grew without
  bound until the volume filled and the account wedged (`tuist` at 17-18 GB of
  CAS against a 2.2 GB binary cache inside a 20 GiB image, refilling every ~2
  days). The prune runs through `tuist-cas-proxy --prune`, not this shell,
  because the per-machine proxy holds a handle per path for its lifetime and
  only the holder can rotate a store. A store no proxy holds is pruned on its
  generation dirs under the store's `lock` without opening it, so it works on a
  full volume and on stores the compilers or another Xcode wrote. Every lane is
  swept (`plugin`, and `builtin`/`generic` from builds without our plugin),
  discovered by their `v1.N` generation dirs, and the compilation cache's limit
  is SPLIT between them: it budgets the CAS as a whole while llcas only takes a
  per-generation bound per store, so handing each the full figure would let a
  multi-lane job occupy a multiple of the CAS the image was sized for. The split
  is by use (`cas_store_budgets` over `split_by_use`): a store whose need, twice
  its allocated size and at least 256 MiB, is under an even share gets that
  need, and the stores that need more split the rest. An even split gave the few-KB `generic` store,
  present on every volume, half the budget and capped `plugin` at half of what
  the host staged. Teardown is the only place that can count the
  lanes — `COMPILATION_CACHE_LIMIT_SIZE` is staged before any of them exist.
  The teardown pass (second, after the drain) bounds what the FLEET inherits: the
  image is measured and promoted right after it. The attach pass bounds what THIS
  job inherits, and covers the case teardown cannot reach — a master that is
  already over budget can fill the volume mid-build and fail the job, and a
  failed job never promotes, so teardown is skipped and no replacement is ever
  published. That is the wedge that ends in a manual reset; pruning at attach
  gives the job the headroom to succeed so its own teardown publishes the fix.
  The attach pass runs AFTER `CACHE_INVENTORY_BEFORE` is snapshotted, and that
  order is load-bearing: pruning first folds the collection into the baseline, so
  a pure-cache-hit job reads as clean and the host DISCARDS the cleaned image
  (verified both ways — same digest when reversed). Taking the baseline first
  makes the collection itself the change that earns the promote, the same
  reasoning that puts `reclaim_cas_if_disabled` at teardown. The compiler is
  given the compilation cache's whole limit, not half: llcas and the prune
  rotate a store once its primary passes half the limit, so the limit already
  covers the primary and the demoted upstream, which is the warm cache.
  `setup_cas_store` also exports
  `TUIST_COMPILATION_CACHE_CAS_PATH`, because `tuist cache` passes
  `COMPILATION_CACHE_CAS_PATH` on the xcodebuild COMMAND LINE and a command-line
  build setting BEATS `XCODE_XCCONFIG_FILE`: without it that job's store landed
  on the VM's boot volume and died with it. It exports
  `TUIST_CAS_DRAINED_STORE` too: on CI the CAS plugin otherwise makes every cache
  put wait for its upload, because off a runner the store goes away with the job,
  and `drain_cas_publications` does that wait at teardown for spools under this
  directory, after the job has reported its result. The plugin uploads in the
  background only when its own store is inside that path, so a job whose xcconfig
  or command line moves `COMPILATION_CACHE_CAS_PATH` elsewhere keeps waiting, and
  so does every job whose store is VM-local.
  The one gate the CAS DOES need of its own is `drain_cas_publications`, first in
  teardown (the prune is second, and in that order deliberately: a prune deletes
  objects, and deleting one the spool still owed would strand the association
  naming it). The store's objects are uploaded to the remote cache
  asynchronously, through the CAS plugin's spool, while the associations naming
  them are written into the store immediately — so a promote that outruns those
  uploads publishes a master whose keys name objects nothing can produce, for
  every host that later clones it, permanently (the compiler's CAS ABI has no
  delete, and re-putting a key with a different value is refused, so such a key
  fails until the store generation rolls). The gate asks the running proxy
  (`tuist-cas-proxy --drain`, exit 0 drained / 3 owed / anything else "could not
  ask") and falls back to watching `<cas dir>/tuist-spool` itself when no client
  can be found — a record is deleted only by a publication that SUCCEEDED, so an
  empty spool is the proof either way. It runs BEFORE `capture_settled_inventory`
  because that computes the digest this image is promoted under, and before the
  detach because the spool is inside the image; it runs on a failed job too,
  whose uploads the next job still needs even though its verdict gates nothing
  (a failed job never promotes), and is a no-op for a job that never published,
  which includes every plain `xcodebuild` using Xcode's builtin lane. Not
  draining within `CAS_DRAIN_TIMEOUT` (120s) withholds a passing job's promote via
  `mark_cache_not_promotable`: the account keeps its previous master and loses
  this job's warm set, which is the same trade every other teardown that cannot
  reach a safe state already makes. It cannot be complete — a host that panics or
  a job cancelled mid-upload promotes without reaching it — so it complements,
  and does not replace, the plugin's read-side check on a local hit.
  `XCODE_XCCONFIG_FILE` is the mechanism because the common case is a plain
  `xcodebuild build` against a project Tuist never generated and never wraps —
  which the generate-time project mapper and the `tuist xcodebuild` wrapper both
  miss. It is the one layer every xcodebuild invocation honors. (Measured on
  staging: `COMPILATION_CACHE_*` exported as plain env vars does nothing —
  xcodebuild does not read build settings from the environment.) Consequences to
  know: the xcconfig deliberately does **not** set
  `COMPILATION_CACHE_ENABLE_CACHING` (enabling the cache stays the project's
  opt-in; this only says *where* an already-caching build keeps its store); it
  chains a pre-existing `XCODE_XCCONFIG_FILE` via `#include` rather than
  clobbering it, but a workflow exporting that variable *after* us wins and the
  CAS falls back to VM-local; and `XCODE_XCCONFIG_FILE` is an OVERRIDES layer
  (swift-build's `environmentConfigPath`), so it FORCES the CAS path over
  project/target-defined settings — a stray target-level `COMPILATION_CACHE_CAS_PATH`
  does NOT win. The escape hatch is a workflow's own xcconfig, which we `#include`
  LAST, so anything it sets explicitly (the CAS path included) still wins.
- `/opt/tuist/metrics-poll.sh` — the machine-metrics sampler.
  `dispatch-poll.sh` forks it into the background right before it
  starts `./run.sh`, so it samples whole-VM CPU/memory/network/disk
  (`top`/`vm_stat`/`netstat`/`df`) for the job's duration and POSTs to
  `…/pods/<pod>/metrics` with the same SA token, dying with the VM when
  the job ends. Best-effort; never blocks the job.
- `/opt/tuist/tuist-cas-proxy` — the last-resort compilation-cache (CAS) prune
  client, built from `cas-plugin/` alongside `runner-shell-agent` by
  `.github/actions/build-runner-image-binaries`. Every `provisioner "file"` in
  `runner.pkr.hcl` is a MANDATORY input and the template has two callers
  (`runner-image.yml` and `runner-image-release.yml`), so a binary built in
  only one fails the other with `Bad source`. Add new
  provisioned binaries to that action, not to a workflow. `cas_proxy_client` prefers the binary beside the tuist
  that `tuist setup cache` installed (it matches the proxy actually running,
  which is what a drain must talk to) and falls back to this one. It exists
  because a plain `xcodebuild` workflow never runs Tuist, so it installs no
  cas-proxy at all — and those jobs still write the compilers' `builtin` CAS
  lane into the volume, so without a binary here nothing on the machine could
  ever bound it. It is only ever invoked as `--prune`/`--drain`; the image runs
  no CAS daemon of its own.
- `/opt/tuist/runner-shell-agent` — interactive shell bridge.
  `dev.tuist.runner-shell-agent` starts `runner-shell-agent-supervisor.sh`
  at boot and waits until `/etc/tuist.env` and `/etc/tuist-sa-token` are
  materialized, then blocks on `/tmp/tuist-runner-shell-claimed` until
  `dispatch-poll.sh` receives a JIT claim. It polls the server for authorized
  shell sessions and forwards a PTY in the runner VM over the server-owned
  WebSocket tunnel. The binary is built from the Go source in
  `cmd/runner-shell-agent/`, so dashboard terminal access and
  `tuist runner ssh` attach to the same ephemeral job environment without a
  Python runtime dependency.
- `/opt/tuist/runner-shell-agent-supervisor.sh` — restarts the trusted
  shell bridge while the single-shot runner VM is alive. It runs as root
  from a LaunchDaemon so terminal access does not depend on an unlocked
  Aqua session, then drops PTY child shells to the `runner` user.
  `/tmp/tuist-runner-shell-agent.lock` keeps it a singleton, and both uids
  share that one path, so probe the holder with `ps -p` and never with
  `kill -0`: from `runner`, `kill -0` fails with EPERM against the live
  root-owned daemon exactly as it fails with ESRCH against a dead pid.
  An unreadable pid file or a refused `rm` means the lock is held, not
  stale; clearing it there starts a second bridge against the same
  dispatch URL and claim marker. `dispatch-poll.sh`'s
  `shell_agent_lock_active` implements the same protocol and must stay in
  step with it.
- `/Library/LaunchDaemons/dev.tuist.runner-shell-agent.plist` — the
  boot-time LaunchDaemon for the shell supervisor. `dispatch-poll.sh`
  still has a singleton-lock guarded fallback start path for older or
  partially-built images.
- `/Users/runner/Library/LaunchAgents/dev.tuist.runner.plist` —
  the LaunchAgent that auto-runs `inject-env.sh` then
  `dispatch-poll.sh` once runner's user session starts at boot.
  Wraps the entrypoint in `zsh -lc` so `~/.zprofile` is sourced
  (Homebrew shellenv, rbenv init, LANG=en_US.UTF-8, PATH
  additions for the cirruslabs base's pre-installed tools), so
  step shells see the same environment an interactive SSH
  session on the same VM would.
- `/etc/kcpassword` + `autoLoginUser=runner` — macOS auto-login
  config so the desktop session exists at boot and loginwindow
  loads the LaunchAgent. Without this the VM boots to a login
  screen and the agent never starts.
- `SetupAssistant` and `SetupAssistant.managed` defaults — skip
  first-run panes such as Apple Account, Privacy, Siri, Screen Time,
  and automatic software update so VNC opens on the runner desktop
  instead of Setup Assistant.
- `pmset`, `com.apple.screensaver`, and `com.apple.autologout`
  defaults — keep the ephemeral runner desktop from sleeping, locking,
  or auto-logging-out during interactive VNC sessions.
- `/etc/sudoers.d/runner-nopasswd` — passwordless sudo for the
  agent's privileged ops (installing /etc/tuist.env, halting the
  VM at job exit). Single-tenant ephemeral VM — the entire OS is
  the customer's job environment.

## Build

```bash
cd infra/runner-image
mkdir -p build
go build -trimpath -ldflags="-s -w" -o build/runner-shell-agent ./cmd/runner-shell-agent
packer init runner.pkr.hcl
packer build runner.pkr.hcl
```

CI:
- **Releases.** `.github/workflows/runner-image-release.yml` runs on
  pushes to `main` under `infra/runner-image/**` and on
  `workflow_dispatch`, in its own concurrency lane, off the server
  deploy path:
  1. `plan` (`.github/scripts/runner-image-release-plan.sh`) rebuilds a
     profile when the image's sources changed in a releasable commit,
     when the previous release did not carry it, or when its
     `macos-tahoe-xcode` base resolves to a different digest than the
     one in the previous release's `build-manifest.json`. Every other
     profile is carried over. A base-only change releases a patch
     version.
  2. `build` fans the rebuilt profiles across the `vm-image-builder`
     hosts. Each clones its base by digest and pushes
     `:macos-<dashes>-<semver>` and `:macos-<dashes>`.
  3. `carry` re-tags `:macos-<dashes>-<previous>` as
     `:macos-<dashes>-<semver>`, a manifest copy with no layer upload.
  4. `release` checks every profile tag is published, then creates the
     `runner-image@<semver>` tag and GitHub Release with
     `build-manifest.json` attached. The chart's
     `runnersFleet.runnerImageSemver` resolves to that tag at deploy
     time.
  5. `deploy` dispatches `server-production-deployment.yml`, which
     rolls the fleet through canary.

  `macos-xcode-image.yml` dispatches the workflow after publishing a
  base an active profile builds on, so a rebuilt base or a moved beta
  channel reaches the fleet without a repo change.
- **Ad-hoc rebuilds.** `.github/workflows/runner-image.yml`
  (`workflow_dispatch`) builds + pushes a SHA-tagged image for one
  profile without cutting a release.

Both flows run on the bare-metal `vm-image-builder` Mac mini
fleet that also builds xcresult-processor. Tart needs a live GUI
session for Virtualization.framework, so this can't run on
hosted runners. Builder fleet operator runbook:
[`../vm-image-builder.md`](../vm-image-builder.md) — cluster-
managed via the same CAPI provider as the macOS Node fleets;
scale via `buildersFleet.replicas` / `kubectl scale`.

Both flows publish through the shared
[`tart-push`](../../.github/actions/tart-push/action.yml)
action. It bounds registry concurrency, chunks large layers, randomizes
retry timing across builders, and captures registry-path diagnostics.
Keep manual and production image publication on that shared action.

## Layer 1 dependency

This is **Layer 2** on top of
`ghcr.io/tuist/macos-tahoe-xcode:<xcode-version-dashes>` (built by
`infra/macos-xcode-image`). Xcode + dev tools + WWDR certs all
live in Layer 1; this layer just adds the GitHub Actions runner
agent + dispatch loop + runner user / launchd wiring on top. A
Layer 2 rebuild on every runner-image commit costs ~2 min instead
of the ~30 min an all-in-one rebuild used to cost.

## Active profiles + the default

Active profiles are the single source of truth in
`infra/runner-image/profiles.json` — a JSON array, newest first:

```json
// infra/runner-image/profiles.json
["27.2-beta", "27.0", "26.6", "26.5", "26.4.1", "26.3", "26.1.1", "26.0.1"]   // newest first
```

Beta entries follow the `<major>.<minor>-beta` shape (matching the
mirror + base image tags `xcode-xips:27.2-beta`,
`macos-tahoe-xcode:27-2-beta`), so `runs-on: tuist-macos-27-2-beta`
resolves to a runner pool sized by
`runnersFleet.xcodeOverrides["27.2-beta"]`.

The file lives under `infra/runner-image/**`, so editing it triggers
a runner-image release. Adding a profile builds only that profile;
removing one drops it from the next release.

- **Active.** Every release publishes a `:macos-<dashes>-<semver>` tag
  for each entry, rebuilt or carried over as the plan decides.
- **Default profile.** The first entry, by convention. Which
  version `runs-on: tuist-macos` actually resolves to is the
  catalog entry marked `default: true` in
  `runnersFleet.xcodeVersions`, so moving the default means editing
  both this list and that catalog.
- **Out-of-rotation profiles.** Any other `:macos-<dashes>` tag
  that's been published in the past and still exists in GHCR. They
  don't refresh on runner-image releases — customers can keep pinning to them, but new runner-agent /
  dispatch-loop / launchd changes only land in them when the
  operator explicitly refreshes via

      gh workflow run runner-image.yml -f xcode_version=26.X.Y

  That dispatch path doesn't move the chart pin.

Active rebuilds always produce both an immutable tag
(`:macos-<dashes>-<semver>`, the one the chart pins) and a rolling
tag (`:macos-<dashes>`, convenient for humans pulling "latest in
this profile").

Bumping the Xcode customers see on their runners:

1. Publish a Layer 1 image with the new Xcode — first run
   `mise run xcode-mirror:upload 26.X.Y` on a maintainer Mac to put
   the .xip into `ghcr.io/tuist/xcode-xips:26.X.Y`, then
   `gh workflow run macos-xcode-image.yml -f xcode_version=26.X.Y`.
   See `infra/macos-xcode-image/AGENTS.md` for the runbook.
2. Edit `infra/runner-image/profiles.json`: add the new Xcode as an
   additional entry (most common — gives customers it alongside the
   existing default), or put it first to make it the newest / default
   profile. **If you move the first entry, also bump
   `server-production-deployment.yml`'s xcresult-processor
   `XCODE_VERSION` to match** — that image must be at least as new
   as the newest runner profile.
   Commit with a `feat(runner-image): ...` message so the release
   builds the new profile. Once that `runner-image@` release is
   published, add the matching `runnersFleet.xcodeVersions` entry in
   `values-managed-common.yaml` so the fleet renders a pool for it.
3. Once customers have migrated off an older Xcode, drop its entry
   from `profiles.json` (and its `values-managed-common.yaml` pool).
   The `:macos-<dashes>` tag stays in GHCR for any lingering pin; the
   dispatch path above stays available for a one-off refresh if
   security work needs to land there.

### Betas enter as a channel

Xcode betas sit in `profiles.json` like any other profile, but the
entry is a **channel** (`27.0-beta`), not a beta (`27.0-beta-6`).
Two things fall out of that, both wanted:

- The base image `macos-xcode-image` publishes for a beta carries
  both an exact tag and the channel tag, so moving a beta is a
  rebuild of `:27-0-beta`. The entry here already points at it,
  which makes a beta bump a zero-diff change: publishing the channel
  dispatches a runner-image release that rebuilds that profile.
- The channel is what customers' Runner Profiles store in
  `xcode_version`. Retiring a catalog entry a profile still names
  strands it on a RunnerPool that no longer renders, and a
  stranded macOS profile queues its jobs forever rather than
  failing them. A channel outlives the betas behind it, so that
  never comes up.

A beta profile is rebuilt when its channel moves or the image's
sources change, and `fail-fast: true` on the matrix means a beta base
that cannot take the runner layer would abort its siblings. That layer is thin
(runner agent plus launchd, ~2 min) and the risky Xcode work all
happens in Layer 1, which fails in `macos-xcode-image` instead, so
the exposure is small. Full runbook: "Promoting an Xcode beta" in
[`../macos-xcode-image/AGENTS.md`](../macos-xcode-image/AGENTS.md).

## Profile tagging

Push tags are per-Xcode-profile: `:macos-26-4-1` (rolling, latest
in that profile) plus `:macos-26-4-1-<semver>` (immutable, for
rollbacks and traceability). The tag form is the Xcode version
with dots → dashes, matching Layer 1's tag scheme: a 26.4.1 Layer
1 produces a `:macos-26-4-1` runner image, a 26.5 Layer 1
produces `:macos-26-5`. The chart pins the immutable per-release
tag (`:macos-<profile>-<semver>`), so multiple Xcode profiles can
coexist in GHCR — the runner-fleet config currently selects one as
the default but the structure is ready for the future
customer-facing profile selection.

## How it ends up serving traffic

1. Each `runnersFleet.pools[].runnerImage` (helm value) is pinned to
   a profile's immutable per-release tag
   (`ghcr.io/tuist/tuist-runner:macos-<profile>-<semver>`). The
   chart's `required` directive only enforces non-empty; the
   release flow writes the immutable tag (not a digest) because
   the semver is monotonic, so the ref is reproducible without a
   registry lookup.

   > **Transitional:** today there's a single pool (`name: default`)
   > and the release pins it to the first matrix profile (the
   > "default profile"). The chart is built for one pool per profile
   > — once #10970 lands the pool-per-profile values, each pool pins
   > its own profile tag and the "default" goes away.
2. `Tuist.Runners.Reconciler` creates a Pod with this image as
   `spec.containers[0].image`; tart-kubelet on the target Mac
   mini calls `tart pull`/`tart clone`/`tart run`.
3. The VM boots, auto-login brings up runner's desktop session,
   loginwindow loads the LaunchAgent, and the agent's entrypoint
   runs `inject-env.sh` then `dispatch-poll.sh`. The dispatch
   script exchanges the projected SA token for a JIT config (200
   with the JIT when a queue row is claimed, 204 while idle),
   runs the GitHub Actions runner single-shot, traps the exit,
   halts the VM. tart-kubelet sees `tart run` exit, the Pod goes
   Succeeded, the RunnerPoolReconciler reaps the Pod + sibling
   SA and boots a replacement to keep the pool at
   `spec.replicas`.

   The trap writes its exit code to `runner-rc` in the `status`
   share on its way out, and tart-kubelet publishes that as the
   Pod's terminated container state. Nothing else carries it off
   the guest: the trap halts the VM on *every* path, so `tart run`
   exits zero whether the job finished or the runner died on boot,
   and a macOS runner death otherwise reaches the cluster as a
   bare `Succeeded` with no exit code, no reason and no log. Three
   consumers in the runners-controller read that field — the
   `runner pod terminated` forensics line, the abnormal-end
   death-log capture, and the `finishedAt` that dates the billing
   session — and all three were Linux-only until the guest started
   reporting. Written from inside the trap rather than after the
   runner exits, so it also covers the aborts that never reach a
   runner. Absent on hosts with no `status` share (it rides on the
   cache-volume feature), which the host reports as
   `TartRunExited` rather than laundering tart's zero into a clean
   runner exit.

   The exit code alone is not enough, because it does not separate
   the two cases that matter: a runner that finished its job and a
   runner that halted without ever taking one both report 0. So the
   trap also publishes `runner.log` — `dispatch-poll.sh`'s own
   output — into the same share, and tart-kubelet re-emits a bounded
   tail of it to its own stdout before teardown deletes the share.
   That stdout is already tailed by the host log shipper, so the
   trail reaches Loki without the shipper having to discover
   per-VM shares. Copied from the trap rather than `tee`d as the
   script runs, so a still-running tee cannot flush a duplicate tail
   after the copy. Same `status`-share dependency as `runner-rc`:
   pools with cache volumes off keep the old behaviour of logging
   only inside the guest, and a guest killed before its trap runs
   publishes nothing — that case already arrives distinguishably as
   `TartRunExited`.

   Both of those describe a runner that *ended*. `runner-heartbeat`
   in the same share covers the runner that does not: the poll loop
   rewrites it every iteration with the state it is in (`polling`
   while warm, `claimed` once it takes a job), and the file's mtime
   is the beat. It exists because a macOS Pod's phase and Ready
   condition are synthesized from "the VM process is alive and has
   an IP" — tart-kubelet runs no container probes — so a guest whose
   poller died reads 1/1 Running for the rest of the VM's life, and
   nothing bounds that life: warm standby is deliberately unbounded
   and in practice a warm macOS runner is recycled only when its SA
   token expires around the 8h mark. tart-kubelet publishes the beat
   as the `tuist.dev/runner-heartbeat-state` and
   `tuist.dev/runner-heartbeat-at` Pod annotations and the
   runners-controller stops counting a stale one as warm capacity.
   `claimed` is written once and then never refreshed — from there
   the script is blocked in `wait` on `run.sh` — so it is the state,
   not the age, that marks the Pod busy; it also does so
   independently of the server's best-effort owner label. Same
   `status`-share dependency as the two above, and the absence is
   read as "no signal" rather than "dead", so a pool with cache
   volumes off keeps counting as capacity.

For the customer-facing dispatch label and capacity model see
`server/lib/tuist/runners.ex` and `infra/helm/tuist/values.yaml`
(`runnersFleet.pools[]`) — they're the right place for routing
semantics; this doc is just about the VM image.

## GitLab CI

`/opt/tuist/tuist-gitlab-runner` executes a server-acquired GitLab job with the upstream shell executor. Its source is in `infra/linux-runner-image/gitlab-runner/` and the shared `build-runner-image-binaries` action builds its darwin/arm64 binary for Packer. Dispatch stages the assignment as private JSON and reuses the normal VM lifecycle. Reusable GitLab runner tokens never enter the VM.

- GitLab parsing uses `/opt/homebrew/bin/jq`, checked before acquisition independently of launchd PATH. Stage assignments in a private `mktemp` file and atomically rename only after successful parsing; failures remove temporary credentials and terminate the claimed runner.
