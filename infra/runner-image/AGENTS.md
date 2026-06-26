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
- `/opt/tuist/metrics-poll.sh` — the machine-metrics sampler.
  `dispatch-poll.sh` forks it into the background right before it
  starts `./run.sh`, so it samples whole-VM CPU/memory/network/disk
  (`top`/`vm_stat`/`netstat`/`df`) for the job's duration and POSTs to
  `…/pods/<pod>/metrics` with the same SA token, dying with the VM when
  the job ends. Best-effort; never blocks the job.
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
- `/etc/sudoers.d/runner-nopasswd` — passwordless sudo for the
  agent's privileged ops (installing /etc/tuist.env, halting the
  VM at job exit). Single-tenant ephemeral VM — the entire OS is
  the customer's job environment.

## Build

```bash
cd infra/runner-image
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
["26.5", "26.4.1", "26.3"]   // first entry = newest / default profile
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
