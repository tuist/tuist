# Runner Image

Tart VM image hosted on the **customer-runner Mac mini fleet**
(`tuist.dev/fleet=<runnersFleetName>`). One image, one Tart VM
per Pod, one ephemeral GitHub Actions runner per VM, one job per
runner.

## What's in the image

- `/opt/actions-runner/` — GitHub Actions runner binary (no
  registration; we register at runtime via JIT config minted by
  `Tuist.Runners.Reconciler` / `Tuist.Runners.Dispatch`).
- `/opt/tuist/inject-env.sh` — reads tart-kubelet's env mount
  (`/Volumes/My Shared Files/env/tuist.env`) into `/etc/tuist.env`.
- `/opt/tuist/dispatch-poll.sh` — polls
  `TUIST_RUNNER_DISPATCH_URL?pod_uid=…&token=…`. While 204 it
  sleeps; on 200 it runs `./run.sh --jitconfig $JIT`. Captures the
  rc and `sudo shutdown -h now`s the VM via an `EXIT` trap so
  `tart run` returns and tart-kubelet flips the Pod to
  Succeeded — the watcher's GC + warm-pool refill are gated on
  that transition.
- `/Users/admin/Library/LaunchAgents/dev.tuist.runner.plist` —
  the LaunchAgent that auto-runs `inject-env.sh` then
  `dispatch-poll.sh` once admin's user session starts at boot.
  Wraps the entrypoint in `zsh -lc` so `~/.zprofile` is sourced
  (Homebrew shellenv, rbenv init, LANG=en_US.UTF-8, PATH
  additions for the cirruslabs base's pre-installed tools), so
  step shells see the same environment an interactive SSH
  session on the same VM would.
- `/etc/kcpassword` + `autoLoginUser=admin` — macOS auto-login
  config so the desktop session exists at boot and loginwindow
  loads the LaunchAgent. Without this the VM boots to a login
  screen and the agent never starts.
- `/etc/sudoers.d/admin-nopasswd` — passwordless sudo for the
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
  `release-runner-image` job: builds, pushes
  `ghcr.io/tuist/tuist-runner:<semver>` + `:latest`, resolves the
  digest with `crane digest`, rewrites
  `runnersFleet.runnerImage` across managed-env values files
  that already have a digest pin, tags `runner-image@x.y.z`,
  opens a GitHub Release, commits.
- **Ad-hoc rebuilds.** `.github/workflows/runner-image.yml`
  (push-to-main on `infra/runner-image/**` changes, plus a
  manual `workflow_dispatch` trigger) builds + pushes a
  SHA-tagged image without bumping the version. Used during
  bring-up before the auto-bump path was wired and as an escape
  hatch for non-versioned rebuilds.

Both flows run on the bare-metal `vm-image-builder` Mac mini
that also builds xcresult-processor — Tart needs a live GUI
session for Virtualization.framework, so this can't run on
hosted runners. Host-prep runbook: [`../vm-image-builder.md`](../vm-image-builder.md).

## How it ends up serving traffic

1. `runnersFleet.runnerImage` (helm value) is digest-pinned to a
   built image. Server-deployment.yaml's `required` directive
   rejects non-digest values.
2. `Tuist.Runners.Reconciler` creates a Pod with this image as
   `spec.containers[0].image`; tart-kubelet on the target Mac
   mini calls `tart pull`/`tart clone`/`tart run`.
3. The VM boots, auto-login brings up admin's desktop session,
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
