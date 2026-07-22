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
  Teardown order is load-bearing: snapshot the post-job inventory while still
  MOUNTED, then **detach**, then write `cache-dirty` (only after a clean detach —
  its absence is what tells the host to discard, the safe default for any teardown
  that never reaches a clean detach). Promotion is a **fast-forward
  compare-and-swap**, not a direct host clone: the guest uploads the detached
  image to a content-addressed key and reports the HEAD with `base_generation`,
  and the server advances the HEAD only if it is still at that base, returning the
  accepted generation. The guest relays that back into the `status` share as
  `cache-promoted-generation`, and the host's `Finalize` installs the branch as
  the account's local master (a whole-image replace) ONLY on an accepted
  fast-forward — so the local master and the HEAD advance together. A rejected
  fast-forward (a stale base another host advanced past) leaves the marker
  unwritten, and the host discards the branch and lets convergence re-warm it. The
  host clones the promoted image and cannot tell a torn snapshot from a good one,
  so a mount torn down by the VM halting would poison the account's master; if the
  detach fails even with `-force`, the guest withdraws the image from both
  promotion and publication.
  The server also delivers a `cache_signing_grant` in
  the dispatch 200, exported as `TUIST_CACHE_SIGNING_GRANT` so the EE CLI signs
  artifacts with the account scope instead of the machine MAC — which is what
  lets a clonefiled master validate across the account's VMs. The Xcode
  compilation cache (CAS) rides a **separate** path: it can't live on the
  virtio-fs share (llcas's mmap'd file locking SIGBUSes over virtio-fs), so the
  host stages it as a sparse APFS disk *image* (`xcode-cas.sparseimage`) inside
  the same branch share. `attach_cas_image` `hdiutil attach`es it as a real
  block-device volume at `/Users/runner/xcode-cas`, then writes an xcconfig
  pointing `COMPILATION_CACHE_CAS_PATH` at a single per-account
  `CompilationCache.noindex` store on it and exports **`XCODE_XCCONFIG_FILE`**;
  `detach_cas_image` unsets it and unmounts after `./run.sh` so the host promotes
  a quiesced image. The store carries Xcode's own `.noindex` name because that
  suffix is what keeps Spotlight out of it — otherwise `mds` would index a
  multi-GB, high-file-count CAS on a mounted volume. Absent image ⇒ the
  compilation cache runs VM-local (cold), unchanged. Gated on the host's
  `--cache-volume-cas-gib`.
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
  CAS falls back to VM-local; and because an xcconfig sits below
  project/target-defined settings, a project that sets
  `COMPILATION_CACHE_CAS_PATH` itself still wins — an escape hatch, and the
  reason a stray target-level value cannot be forced onto the image.
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

For the customer-facing dispatch label and capacity model see
`server/lib/tuist/runners.ex` and `infra/helm/tuist/values.yaml`
(`runnersFleet.pools[]`) — they're the right place for routing
semantics; this doc is just about the VM image.
