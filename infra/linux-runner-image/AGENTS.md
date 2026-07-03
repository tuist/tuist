# Linux Runner Image

OCI image hosted on the **Linux runner fleet** (Hetzner Cloud
nodes selected via `tuist.dev/fleet=<runnersFleetLinuxName>`). One
ephemeral GitHub Actions runner per Pod, one job per runner. The
same image runs in two roles within a Pod (see "Credential split"
below): a `poller` init container and a `runner` main container.

This is the Linux analog of `infra/runner-image/` (the Tart-based
macOS image). Same single-shot lifecycle, much simpler substrate.

## What's in the image

- `/home/runner/actions-runner/` — GitHub Actions runner binary
  (no registration baked in; we register at runtime via the JIT
  config minted by `Tuist.Runners.dispatch_for_sa/2`).
- `/usr/local/bin/dispatch-poll.sh` — the poll loop, run by the
  `poller` container. POSTs to the dispatch endpoint with the
  projected SA token as Bearer; on 204 it sleeps; on a claim it
  writes the minted JIT to the shared `tuist-runner-jit` volume
  (`TUIST_RUNNER_JIT_OUTPUT_PATH`) and exits 0 for the runner
  container to consume. (If that env is unset it `exec`s `./run.sh`
  in place — a rollout bridge for a controller still mid-upgrade;
  see `infra/runners-controller/AGENTS.md`.)
- `/usr/local/bin/run-job.sh` — the `runner` container's
  entrypoint in the split shape. Reads the JIT the poller staged
  (`TUIST_RUNNER_JIT_PATH`) and `exec`s
  `./run.sh --jitconfig <jit> --disableupdate`, or exits 0 if no
  JIT was staged (410 drain / poller abort). Holds no SA token.
- `/usr/local/bin/vitals.sh` — periodic resource-vitals emitter.
  `run-job.sh` backgrounds it just before exec'ing the runner (the
  dispatch-poll rollout-bridge path does too), so it samples for the
  job's lifetime and its last line lands in the Pod logs -> Loki even
  after the microVM is reaped. Tag `RUNNER_VITALS`; fields cover
  guest-wide memory (`/proc/meminfo`), cgroup memory
  (current/peak/max, `oom_kill`), guest CPU-busy% (`/proc/stat`
  deltas), loadavg, and a best-effort `/dev/kmsg` OOM watcher. PSI
  (`/proc/pressure/*`) avg10 fields are appended only when the guest
  exposes them — the runners-controller sets `psi=1` on the kata
  guest cmdline via a pod annotation, since the kata kernel boots
  with PSI off. The forensic trail for a runner that dies mid-job
  (guest OOM vs CPU/memory starvation), which is otherwise invisible
  from outside the guest. Interval via
  `TUIST_RUNNER_VITALS_INTERVAL` (default 3s).
- `/usr/local/bin/metrics-sampler.sh` — machine-metrics sampler for
  the job detail page's Metrics tab. Unlike `vitals.sh` (which logs to
  stdout from the runner container), this POSTs structured
  CPU/memory/network/disk samples to the server, so it runs in the
  dedicated `metrics` native-sidecar container that holds the dispatch
  SA token (the runner container never sees it). It waits for the
  poller to stage the JIT (a claimed job) before sampling — so
  warm-standby Pods don't post — then samples VM-wide `/proc` plus the
  JIT volume's backing filesystem every `TUIST_RUNNER_METRICS_INTERVAL`
  (default 15s) and POSTs to `…/pods/<pod>/metrics`. Best-effort;
  never affects the job.
- `docker-ce-cli`, `docker-buildx-plugin`, `docker-compose-plugin`
  from the official Docker apt repo — client side only. The
  daemon runs in the `dind` native sidecar (`docker:dind`)
  attached to the same Pod by the runners-controller. The
  runner's `docker` group is pinned to GID 123 to match the
  socket GID dockerd creates in the sidecar.

No `inject-env.sh`, no launchd plist, no VM-halt trap — kubelet
projects env + SA token natively, container exit IS the
substrate's terminal signal.

## Credential split (token isolation)

A Linux runner Pod runs untrusted workflow code (incl. fork PRs),
so the container that runs it must never see the dispatch SA
token — that token is pool-scoped and could claim other tenants'
queued jobs. The controller's `podtemplate.Build` splits the Pod:

- **`poller` init container** — the only container that mounts the
  token. Runs `dispatch-poll.sh` in poller mode; on a claim it
  writes the minted, job-scoped JIT to a shared `tuist-runner-jit`
  emptyDir and exits 0. Runs as root so it can write that
  root-owned emptyDir (it executes only our poll script, never
  customer code).
- **`runner` main container** — no token. kubelet starts it only
  after the poller init container exits, so by then the JIT (if
  any) is already staged. Runs `run-job.sh`, which reads the JIT
  and `exec`s the runner. A leaked JIT post-claim grants nothing
  the runner isn't already running under.

A warm-standby Pod therefore sits in `Pending` (poller polling in
Init) until a job is claimed, not `Running`. macOS keeps the
single-container shape — the Tart VM is the isolation boundary and
tart-kubelet projects the token into it. See
`infra/runners-controller/AGENTS.md` for the full Pod shape.

## docker

dockerd does NOT run in this image. It runs in a sidecar; the
runner reaches it via `DOCKER_HOST=unix:///var/run/docker.sock`
injected by the controller, with the socket mounted from a
shared emptyDir. See `infra/runners-controller/AGENTS.md` for
the sidecar Pod shape + lifecycle.

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
runs on a standard cloud Linux runner (no Tart / GUI session
needed). Steady-state: `feat(linux-runner-image)` /
`fix(linux-runner-image)` conventional commits on `main` trigger
a `release-linux-runner-image` job that builds, pushes
`ghcr.io/tuist/tuist-linux-runner:<semver>` + `:latest`, takes the
digest from the build-push-action's own output, and rewrites
`runnersFleetLinux.pools[*].runnerImage` across managed-env
values files (those whose pin is already non-empty — canary /
production stay empty until the env is flipped on). Ad-hoc
rebuilds for branch validation go through
`.github/workflows/linux-runner-image.yml`: `pull_request` builds
without pushing, `workflow_dispatch` pushes `:sha-<git-sha>` only
(`:latest` and semver tags belong exclusively to the release
flow).

## How it ends up serving traffic

1. `runnersFleetLinux.pools[].runnerImage` (helm value) is
   digest-pinned to a built image.
2. The runners-controller's `RunnerPoolReconciler` creates a Pod
   with this image; kubelet on the Hetzner Cloud node pulls the
   OCI image (cached on subsequent Pods scheduled to the same
   host) and starts the containers.
3. The `poller` init container runs `dispatch-poll.sh`, exchanging
   the projected SA token for a JIT config (200 with the JIT when
   a queue row is claimed, 204 while idle), then stages the JIT
   and exits. The `runner` main container starts, runs the GitHub
   Actions runner single-shot under that JIT (no token), and
   exits. The runner-container exit is what kubelet observes for
   billing + reaping; the rest is identical to the macOS path
   (which keeps the single-container shape — see "Credential
   split" above).

For the customer-facing dispatch label, autoscaling, and capacity
model see `server/lib/tuist/runners.ex` and
`infra/helm/tuist/values.yaml` (`runnersFleetLinux.pools[]`) —
this doc is only about the container image.
