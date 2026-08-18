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
handed over explicitly. Two things are:

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

When adding tooling to the base, check ownership and login-shell
reachability from `runner`, not just presence under `admin`.

A related class of gap is anything GitHub-hosted images pre-seed
that ours do not. When adding parity features, compare against
`actions/runner-images` `images/macos/scripts/build/`, and pair
each one with a check that asserts the behaviour rather than the
ingredient — every gap so far was found by a release failing, not
by the image build.

TCC looked like one of those gaps and was not. Scripted Finder
automation here fails as `AppleEvent timed out (-1712)`, which
reads as a missing `kTCCServiceAppleEvents` approval, and this
template used to seed one. It changed nothing: seeding the
approval into the session user's database and reading the row
back still left every send timing out, because these VMs have no
Finder that answers rather than one that refuses. Do not re-add
it. The DMG step that surfaced this no longer drives Finder at
all (`app/dmg-settings.py`), and if something else needs a GUI
app here, the question to answer first is whether the auto-login
session materialises, not whether it is authorised.

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
- `/Users/runner/work/<owner>/<repo>` — workspace path the JIT
  config sets via `work_folder: "/Users/runner/work"`; matches
  GitHub-hosted's `GITHUB_WORKSPACE`.
- `/opt/tuist/inject-env.sh` — root-owned helper; reads
  tart-kubelet's env mount (`/Volumes/My Shared Files/env/tuist.env`)
  into `/etc/tuist.env`.
- `/opt/tuist/dispatch-poll.sh` — polls
  `TUIST_RUNNER_DISPATCH_URL?pod_uid=…&token=…`. While 204 it
  sleeps; on 200 it runs `./run.sh --jitconfig $JIT`. Captures
  the rc and `sudo shutdown -h now`s the VM via an `EXIT` trap so
  `tart run` returns and tart-kubelet flips the Pod to
  Succeeded — the watcher's GC + warm-pool refill are gated on
  that transition.
  `dispatch-poll.sh` also drives the **per-account cache-volume** flow,
  materialized after dispatch. tart-kubelet attaches
  an *empty* per-VM branch directory as a writable virtio-fs share at
  `/Volumes/My Shared Files/cache`. The cache itself is a **sparse APFS disk
  image** (`cache.sparseimage`) inside that share, not files on it: virtio-fs
  cannot set xattrs on symlinks, and macOS frameworks are versioned bundles
  whose symlinks carry the CLI's signature xattrs, so caching any macOS slice
  onto the share fails (ELOOP). Inside an image the filesystem is real APFS and
  only one regular file crosses virtio-fs.
  The share is empty until dispatch: once the server stamps the pod's account
  label, the host clonefiles that account's master image into the branch and
  writes a `cache-ready` marker. After receiving the JIT and before `./run.sh`,
  the guest calls `wait_for_cache_ready` — a bounded (~60s) wait on that marker
  — then `attach_cache_image` (`hdiutil attach … -owners off`, which maps the
  contents to the guest user and so retires any host/guest uid reconciliation),
  points `TUIST_XDG_CACHE_HOME` at the **mountpoint**
  (`/Users/runner/.tuist-cache-volume`), reads the host-staged per-branch byte
  budget (`cache-max-bytes` in the `status` share) into `TUIST_CACHE_MAX_BYTES`
  for the CLI's LRU self-prune, reads the host-staged base generation
  (`cache-base-generation`) — the HEAD generation the branch was clonefiled from,
  used as the fast-forward base at promote — and snapshots the pre-job inventory.
  Timeout / absent share / failed attach ⇒ cold path, unchanged. A cold first job
  still gets an *empty* image — the guest can only attach what is there, and no
  image would kill the job rather than cost it warmth.
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
  or the pre-flight would 409 the only promote that can unwedge the account. Promotion is a **fast-forward
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
  `setup_cas_store` — called from `attach_cache_image` after the mount — creates
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
  The one gate the CAS DOES need of its own is `drain_cas_publications`, first in
  teardown. The store's objects are uploaded to the remote cache
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
  detach because the spool is inside the image; it is skipped on a failed job
  (which never promotes) and is a no-op for a job that never published, which
  includes every plain `xcodebuild` using Xcode's builtin lane. Not draining
  within `CAS_DRAIN_TIMEOUT` (120s) withholds the promote via
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
- **Steady state.** `feat(runner-image)` / `fix(runner-image)`
  conventional commits on `main` trigger a two-job chain in
  `release.yml`:
  1. `runner-image-build` is a matrix job; its `matrix.xcode` is
     read from `infra/runner-image/profiles.json` (the single source
     of truth) by `check-releases` and expanded via `fromJSON`. One
     entry runs per profile, fanned out across every available
     `vm-image-builder`-labelled host. Each entry
     builds against `ghcr.io/tuist/macos-tahoe-xcode:<dashes>` and
     pushes both immutable (`:macos-<dashes>-<semver>`) and rolling
     (`:macos-<dashes>`) tags. `fail-fast: true` — if any profile
     fails, sibling builds abort so the chart pin doesn't move to a
     partially-published set.
  2. `release-runner-image` (ubuntu) pins `runnersFleet.runnerImage`
     to the default profile's immutable per-release tag
     (`:macos-<profile>-<semver>` — constructed from the version, no
     registry lookup), rewrites the managed-env values files that
     already carry a pin, generates release notes / `CHANGELOG.md`,
     uploads artifacts. Downstream tag + GitHub-Release jobs key off
     this job's `result == 'success'`.

  Concurrency scales with builder count: 2 hosts publish 2 profiles
  in parallel, more hosts cut the wall-clock proportionally. No
  workflow change needed when the fleet grows.
- **Ad-hoc rebuilds.** `.github/workflows/runner-image.yml`
  (push-to-main on `infra/runner-image/**` changes, plus a
  manual `workflow_dispatch` trigger) builds + pushes a
  SHA-tagged image without bumping the version. Used during
  bring-up before the auto-bump path was wired and as an escape
  hatch for non-versioned rebuilds.

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
["26.6", "26.5", "26.4.1", "26.3", "26.0.1"]   // first entry = newest / default profile
```

`check-releases` reads this into the `runner-image-matrix` output and
`runner-image-build`'s `matrix` expands it via `fromJSON`. Because the
file lives under `infra/runner-image/**` — the component's only
include path in `mise/tasks/release/components.json` — editing the
list both reshapes the build matrix and triggers a runner-image
release, with no `release.yml` edit. Unrelated `release.yml` churn no
longer rebuilds the images.

- **Active.** Rebuilt on every `release-runner-image` run (every
  `feat(runner-image)` / `fix(runner-image)` commit landing on
  `main`). Each adds ~30 min on a single builder; matrix-fanned across
  the fleet so adding a third builder lets you carry a third profile
  at the same wall-clock cost.
- **Default profile.** The first matrix entry. The chart's
  `runnersFleet.runnerImage` pin tracks its immutable
  `:macos-<dashes>-<semver>` tag, so a new fleet rollout = put the
  desired profile first.
- **Out-of-rotation profiles.** Any other `:macos-<dashes>` tag
  that's been published in the past and still exists in GHCR. They
  don't refresh on `release.yml` runs — customers can keep pinning
  to them, but new runner-agent / dispatch-loop / launchd changes
  only land in them when the operator explicitly refreshes via

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
   `release.yml`'s xcresult-processor `XCODE_VERSION` to match** —
   that image must be at least as new as the newest runner profile.
   Also add the matching `runnersFleet.xcodeVersions` entry in
   `values-managed-common.yaml` so the fleet renders a pool for it.
   Commit with a `feat(runner-image): ...` message so check-releases
   triggers the rebuild.
3. Once customers have migrated off an older Xcode, drop its entry
   from `profiles.json` (and its `values-managed-common.yaml` pool).
   The `:macos-<dashes>` tag stays in GHCR for any lingering pin; the
   dispatch path above stays available for a one-off refresh if
   security work needs to land there.

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

For the customer-facing dispatch label and capacity model see
`server/lib/tuist/runners.ex` and `infra/helm/tuist/values.yaml`
(`runnersFleet.pools[]`) — they're the right place for routing
semantics; this doc is just about the VM image.
