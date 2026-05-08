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
  rc and `shutdown -h now`s the VM via an `EXIT` trap so
  `tart run` returns and tart-kubelet flips the Pod to
  Succeeded — the watcher's GC + warm-pool refill are gated on
  that transition.
- `/Library/LaunchDaemons/dev.tuist.runner.plist` — auto-runs
  `inject-env.sh` then `dispatch-poll.sh` on first boot.

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
hosted runners.

## How it ends up serving traffic

1. `runnersFleet.runnerImage` (helm value) is digest-pinned to a
   built image. Server-deployment.yaml's `required` directive
   rejects non-digest values.
2. `Tuist.Runners.Reconciler` creates a Pod with this image as
   `spec.containers[0].image`; tart-kubelet on the target Mac
   mini calls `tart pull`/`tart clone`/`tart run`.
3. The launchd plist runs on first boot inside the VM. The
   dispatch-poll script exchanges the per-Pod token for a JIT
   config (200 immediately for pre-bound, 200 once a webhook
   binds an on-demand Pod), runs the GitHub Actions runner
   single-shot, traps the exit, halts the VM. tart-kubelet sees
   `tart run` exit, the Pod goes Succeeded, the watcher GCs the
   Pod + assignment row and (if `min_warm > 0`) refills.

For the customer-facing dispatch label and capacity model see
`server/lib/tuist/runners/pool_config.ex` and the PR description
that introduced the runner pool — they're the right place for
the routing semantics, this doc is just about the VM image.
