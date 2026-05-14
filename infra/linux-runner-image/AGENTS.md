# Linux Runner Image

OCI image hosted on the **Linux runner fleet** (Hetzner Cloud
nodes selected via `tuist.dev/fleet=<runnersFleetLinuxName>`).
One container per Pod, one ephemeral GitHub Actions runner per
container, one job per runner.

This is the Linux analog of `infra/runner-image/` (the Tart-based
macOS image). Same single-shot lifecycle, much simpler substrate.

## What's in the image

- `/home/runner/actions-runner/` — GitHub Actions runner binary
  (no registration baked in; we register at runtime via the JIT
  config minted by `Tuist.Runners.dispatch_for_sa/2`).
- `/usr/local/bin/dispatch-poll.sh` — polls the dispatch
  endpoint with the projected SA token as Bearer. On 204 it
  sleeps; on 200 it `exec`s `./run.sh --jitconfig <jit>`. When
  the runner exits, PID 1 exits, the container exits, kubelet
  flips the Pod to Succeeded/Failed, the RunnerPoolReconciler
  reaps the Pod + sibling SA and boots a replacement.

No `inject-env.sh`, no launchd plist, no VM-halt trap — kubelet
projects env + SA token natively, container exit IS the
substrate's terminal signal.

## Build

```bash
cd infra/linux-runner-image
docker build --pull -t ghcr.io/tuist/tuist-linux-runner:dev .
```

`RUNNER_VERSION` is a `--build-arg` (default lives in the
Dockerfile). Renovate keeps it bumped to the latest
`actions/runner` release; the value flows into `helm` via the
release-pipeline digest rewrite, same shape as the macOS image.

## CI

The release pipeline mirrors `release-runner-image` for macOS but
runs on a standard GitHub-hosted Linux runner (no Tart / GUI
session needed). Steady-state: `feat(linux-runner-image)` /
`fix(linux-runner-image)` conventional commits on `main` trigger
a `release-linux-runner-image` job that builds, pushes
`ghcr.io/tuist/tuist-linux-runner:<semver>` + `:latest`, resolves
the digest with `crane digest`, and rewrites
`runnersFleetLinux.pools[*].runnerImage` across managed-env
values files. Ad-hoc rebuilds via `.github/workflows/linux-runner-image.yml`
on push-to-main or `workflow_dispatch`.

## How it ends up serving traffic

1. `runnersFleetLinux.pools[].runnerImage` (helm value) is
   digest-pinned to a built image.
2. The runners-controller's `RunnerPoolReconciler` creates a Pod
   with this image; kubelet on the Hetzner Cloud node pulls the
   OCI image (cached on subsequent Pods scheduled to the same
   host) and starts the container.
3. The container's PID 1 is `dispatch-poll.sh`. It exchanges the
   projected SA token for a JIT config (200 with the JIT when a
   queue row is claimed, 204 while idle), runs the GitHub Actions
   runner single-shot, exits when the runner exits. The container
   exit is what kubelet observes; the rest is identical to the
   macOS path.

For the customer-facing dispatch label, autoscaling, and capacity
model see `server/lib/tuist/runners.ex` and
`infra/helm/tuist/values.yaml` (`runnersFleetLinux.pools[]`) —
this doc is only about the container image.
