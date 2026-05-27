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
  conventional commits on `main` trigger `release.yml`'s
  `release-runner-image` job: iterates `infra/runner-image/XCODE_VERSIONS`,
  rebuilds every **active** line (skips `inactive` ones), pushing
  each as `ghcr.io/tuist/tuist-runner:macos-<xcode-version-dashes>-<semver>`
  (immutable) and `:macos-<xcode-version-dashes>` (rolling, e.g.
  `:macos-26-4-1`). Resolves the **first active profile's** digest
  with `crane digest`, rewrites `runnersFleet.runnerImage` across
  managed-env values files that already have a digest pin, tags
  `runner-image@x.y.z`, opens a GitHub Release, commits.
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

## Profiles file: `infra/runner-image/XCODE_VERSIONS`

Each non-comment line is `<xcode-version> [active|inactive]` (the
annotation defaults to `active`). Comments start with `#`.

```
# default profile (chart pin tracks this one)
26.5
26.4.1
26.0.1   inactive
```

Three concepts to keep straight:

- **Default profile.** The first **active** line. The chart's
  `runnersFleet.runnerImage` digest pin tracks this profile, so a
  new fleet rollout = make the desired profile the first active line.
- **Active profiles.** Rebuilt on every `release-runner-image` run
  (i.e. every `feat(runner-image)` / `fix(runner-image)` commit
  landing on `main`). Each adds ~30 min to the release on the
  singleton `vm-image-builder` host, so keep this set small — the
  Xcodes the fleet is currently rolling onto, typically 1-3.
- **Inactive profiles.** Stay published in GHCR — customers can keep
  pinning their workflows to them — but don't refresh on every
  release. Use this for older Xcodes that customers haven't migrated
  off yet. To roll a new runner-agent / dispatch-loop / launchd
  change into an inactive profile:

      gh workflow run runner-image.yml -f xcode_version=26.X.Y

Each line — when active and rebuilt — produces both an immutable
tag (`:macos-<dashes>-<semver>`) and a rolling tag (`:macos-<dashes>`,
which is what the chart resolves through its digest pin).

Bumping the Xcode customers see on their runners:

1. Publish a Layer 1 image with the new Xcode — first run
   `mise run xcode-mirror:upload 26.X.Y` on a maintainer Mac to put
   the .xip into `ghcr.io/tuist/xcode-xips:26.X.Y`, then
   `gh workflow run macos-xcode-image.yml -f xcode_version=26.X.Y`.
   See `infra/macos-xcode-image/AGENTS.md` for the runbook.
2. Edit `infra/runner-image/XCODE_VERSIONS`: add a new active line
   for the Xcode (most common — gives customers it as an option
   alongside the existing default), or put it at the top of the
   active list to make it the new chart default. Commit with a
   `feat(runner-image): ...` message — check-releases triggers the
   rebuild against every active profile, and the chart pin moves to
   the first active profile's digest.
3. Once customers have migrated off an older Xcode, demote its line
   to `inactive` so it stops paying the release-time cost. The tag
   stays in GHCR for any lingering pin.

## Profile tagging

Push tags are per-Xcode-profile: `:macos-26-4-1` (rolling, latest
in that profile) plus `:macos-26-4-1-<semver>` (immutable, for
rollbacks and traceability). The tag form is the Xcode version
with dots → dashes, matching Layer 1's tag scheme: a 26.4.1 Layer
1 produces a `:macos-26-4-1` runner image, a 26.5 Layer 1
produces `:macos-26-5`. The chart pins by digest, not tag, so
multiple Xcode profiles can coexist in GHCR — the runner-fleet
config currently selects one as the default but the structure is
ready for the future customer-facing profile selection.

## How it ends up serving traffic

1. `runnersFleet.runnerImage` (helm value) is digest-pinned to a
   built image. Server-deployment.yaml's `required` directive
   rejects non-digest values.
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
